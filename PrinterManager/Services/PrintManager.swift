import Foundation
import Combine
import AppKit

/// Ana yazdırma yöneticisi - reaktif state yönetimi
@MainActor
class PrintManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isPrinting: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPage: Int?
    @Published var totalPages: Int = 0
    @Published var progress: Double = 0.0
    @Published var timeRemaining: TimeInterval = 0
    @Published var isCleaningPhase: Bool = false
    @Published var logs: [String] = []
    @Published var showFlipPagesDialog: Bool = false
    /// Kullanıcıdan karar bekleyen soru (ön kontrol, büyük sayfa...)
    @Published var prompt: PrintPrompt?
    
    /// Tahmini kalan toplam süre (saniye)
    var estimatedTimeRemaining: TimeInterval {
        guard isPrinting, let current = currentPage, totalPages > 0 else { return 0 }
        let remainingPages = totalPages - current
        let perPageTime = printDelay + cleanDelay
        return TimeInterval(remainingPages) * perPageTime + timeRemaining
    }
    
    /// Bu boyutun üstündeki sayfa verisi için göndermeden önce sorulur.
    /// Ölçümler (1200x600): yoğun renkli sayfa ~1,7 MB, tam sayfa görsel ~3,3 MB,
    /// en kötü durum (rastgele gürültü) ~14 MB. Yazıcı belleği 32 MB.
    static let largePageWarningBytes = 8_000_000
    
    // MARK: - Private Properties
    private var printTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    private var pendingDuplexContinuation: CheckedContinuation<Void, Never>?
    private var promptContinuation: CheckedContinuation<PrintPrompt.Choice, Never>?
    private var pdfURL: URL?
    private var printerName: String = ""
    private var printDelay: TimeInterval = 30
    private var cleanDelay: TimeInterval = 8
    private var isDuplex: Bool = false
    private var isGrayscale: Bool = false
    private var backend: PrintBackend?
    
    // MARK: - Public Methods
    
    /// Yazdırma işlemini başlatır
    func startPrinting(
        pdf: URL,
        printer: String,
        printDelay: TimeInterval,
        cleanDelay: TimeInterval,
        duplex: Bool,
        grayscale: Bool = false,
        driver: DriverSettings
    ) async {
        guard !isPrinting else { return }
        
        self.pdfURL = pdf
        self.printerName = printer
        self.printDelay = printDelay
        self.cleanDelay = cleanDelay
        self.isDuplex = duplex
        self.isGrayscale = grayscale
        self.isCancelled = false
        self.isPrinting = true
        self.showFlipPagesDialog = false
        
        addLog("Yazdırma başlatılıyor...")
        
        // ÖNCELİKLE: Yazıcı bağlı mı kontrol et
        addLog("Yazıcı kontrol ediliyor: \(printer)")
        if !PrinterService.shared.isPrinterAvailable(printer) {
            addLog("❌ HATA: '\(printer)' yazıcısı bağlı değil veya erişilemiyor!")
            addLog("Lütfen yazıcının bağlı ve açık olduğundan emin olun.")
            await cleanup()
            return
        }
        addLog("✓ Yazıcı erişilebilir")
        
        do {
            switch driver.mode {
            case .system:
                addLog("Sürücü: sistem sürücüsü (lp)")
                
                // PrinterManager kuyruğu PDF'leri basmaz, uygulamaya geri getirir
                let queue = PrinterService.shared.cupsQueueName(for: printer)
                if PrinterService.shared.queueStatus(queue)?.makeAndModel.contains("PrinterManager") == true {
                    addLog("❌ Sistem sürücüsü bu yazıcıyla kullanılamaz; \"Kendi sürücü\" modunu seçin.")
                    await cleanup()
                    return
                }
                
                // PDF'i böl
                addLog("PDF sayfalara bölünüyor...")
                var pageURLs = try await PDFProcessor.shared.splitPDF(at: pdf)
                
                // Çift yönlü ve sayfa sayısı tek ise boş sayfa ekle
                if duplex && pageURLs.count % 2 != 0 {
                    addLog("Tek sayıda sayfa (\(pageURLs.count)) - çift yön için boş sayfa ekleniyor...")
                    let blankPage = try await PDFProcessor.shared.createBlankPage()
                    pageURLs.append(blankPage)
                }
                
                backend = .system(pageURLs: pageURLs)
                totalPages = pageURLs.count
            
            case .own:
                addLog("Sürücü: kendi sürücü (Ghostscript + foo2qpdl, ham gönderim)")
                guard let job = try await prepareOwnDriver(pdf: pdf, printer: printer, duplex: duplex, settings: driver) else {
                    addLog("Yazdırma başlatılmadı")
                    await cleanup()
                    return
                }
                backend = .own(job)
                totalPages = job.sheetCount
            }
            
            addLog("\(totalPages) sayfa hazırlandı")
            
            // Sayfa sırasını belirle
            let pagesToPrint: [Int]
            if duplex {
                // İlk geçiş: tek sayfalar (1, 3, 5...)
                pagesToPrint = Array(stride(from: 0, to: totalPages, by: 2))
                addLog("Çift yönlü yazdırma - İlk geçiş: \(pagesToPrint.count) sayfa (tek sayfalar)")
            } else {
                // Tüm sayfalar
                pagesToPrint = Array(0..<totalPages)
            }
            
            // Sayfaları yazdır
            try await printPages(pageIndices: pagesToPrint, isSecondPass: false)
            
            // Çift yönlü ise ikinci geçiş
            if duplex && !isCancelled {
                // Kullanıcıya kağıtları çevirmesini söyle
                showFlipPagesDialog = true
                addLog("Kağıtları çevirmeniz bekleniyor...")
                
                await withCheckedContinuation { continuation in
                    self.pendingDuplexContinuation = continuation
                }
                
                if !isCancelled {
                    // İkinci geçiş: çift sayfalar TERS SIRADA (son çift sayfadan ilke doğru)
                    // Örnek: 6 sayfalı PDF için -> [5, 3, 1] indeksleri (sayfa 6, 4, 2)
                    let evenPages = Array(stride(from: 1, to: totalPages, by: 2))
                    let reversedEvenPages = evenPages.reversed().map { $0 } // Ters çevir
                    addLog("Çift yönlü yazdırma - İkinci geçiş: \(reversedEvenPages.count) sayfa (çift sayfalar, ters sırada)")
                    try await printPages(pageIndices: reversedEvenPages, isSecondPass: true)
                }
            }
            
            if !isCancelled {
                addLog("✅ Tüm sayfalar yazdırıldı!")
            }
        
        } catch {
            addLog("❌ Hata: \(error.localizedDescription)")
        }
        
        // Temizlik
        await cleanup()
    }
    
    /// Yazdırmayı iptal eder
    func cancel() {
        isCancelled = true
        isPaused = false
        pendingDuplexContinuation?.resume()
        pendingDuplexContinuation = nil
        if promptContinuation != nil {
            answerPrompt(.cancel)
        }
        addLog("⚠️ Yazdırma iptal edildi")
    }
    
    /// Yazdırmayı duraklatır
    func pause() {
        guard isPrinting && !isPaused else { return }
        isPaused = true
        addLog("⏸ Yazdırma duraklatıldı")
    }
    
    /// Yazdırmaya devam eder
    func resume() {
        guard isPrinting && isPaused else { return }
        isPaused = false
        addLog("▶️ Yazdırma devam ediyor")
    }
    
    /// Durdur/Devam değiştirir
    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }
    
    /// Çift yönlü yazdırmada devam et
    func continueWithEvenPages() {
        showFlipPagesDialog = false
        pendingDuplexContinuation?.resume()
        pendingDuplexContinuation = nil
    }
    
    /// Ekrandaki soruya verilen cevap
    func answerPrompt(_ choice: PrintPrompt.Choice) {
        prompt = nil
        promptContinuation?.resume(returning: choice)
        promptContinuation = nil
    }
    
    /// Log ekler
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }
    
    /// Logları temizler
    func clearLogs() {
        logs.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func printPages(pageIndices: [Int], isSecondPass: Bool) async throws {
        for (index, pageIndex) in pageIndices.enumerated() {
            guard !isCancelled else { break }
            
            currentPage = pageIndex + 1
            isCleaningPhase = false
            
            // 1) ÖNCE YAZDIR - hemen başla
            var didSend = false
            do {
                didSend = try await sendPage(at: pageIndex)
                if didSend {
                    addLog("✓ Sayfa \(pageIndex + 1) yazıcıya gönderildi")
                }
            } catch {
                addLog("⚠️ Sayfa \(pageIndex + 1) yazdırma hatası: \(error.localizedDescription)")
            }
            
            guard !isCancelled else { break }
            
            // Sayfa atlandıysa kağıt geçmedi, beklemeye gerek yok
            guard didSend else { continue }
            
            // 2) SONRA BEKLE - yazdırma süresi (sayfa basılsın diye)
            if index < pageIndices.count - 1 {
                addLog("Sayfa \(pageIndex + 1) basılıyor, bekleniyor...")
                await waitWithProgress(duration: printDelay, phase: .printing)
                
                guard !isCancelled else { break }
                
                // 3) Temizlik beklemesi
                isCleaningPhase = true
                addLog("Belt temizleme bekleniyor...")
                await waitWithProgress(duration: cleanDelay, phase: .cleaning)
            }
        }
    }
    
    /// Sayfayı seçili sürücüyle gönderir; gönderilmediyse (atlandı / iptal) false
    private func sendPage(at pageIndex: Int) async throws -> Bool {
        switch backend {
        case .system(let pageURLs):
            addLog("Sayfa \(pageIndex + 1) yazıcıya gönderiliyor...")
            try await PrinterService.shared.printPage(at: pageURLs[pageIndex], to: printerName, grayscale: isGrayscale)
            return true
        case .own(let job):
            return try await sendOwnDriverPage(at: pageIndex, job: job)
        case nil:
            return false
        }
    }
    
    private enum WaitPhase {
        case printing
        case cleaning
    }
    
    private func waitWithProgress(duration: TimeInterval, phase: WaitPhase) async {
        var remainingDuration = duration
        
        while remainingDuration > 0 && !isCancelled {
            // Duraklatıldıysa bekle
            while isPaused && !isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            guard !isCancelled else { break }
            
            let stepStart = Date()
            let stepDuration: TimeInterval = 0.1 // 100ms adımlar
            
            // Kalan süreyi güncelle
            self.timeRemaining = remainingDuration
            self.progress = 1.0 - (remainingDuration / duration)
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Eğer duraklatılmadıysa süreyi azalt
            if !isPaused {
                let elapsed = Date().timeIntervalSince(stepStart)
                remainingDuration -= elapsed
            }
        }
        
        self.progress = 1.0
        self.timeRemaining = 0
    }
    
    private func cleanup() async {
        isPrinting = false
        isPaused = false
        currentPage = nil
        progress = 0
        timeRemaining = 0
        isCleaningPhase = false
        showFlipPagesDialog = false
        backend = nil
        
        // Temp dosyaları temizle
        await PDFProcessor.shared.cleanupTempFiles()
    }
    
    /// Soruyu ekrana getirir ve cevabı bekler
    private func ask(_ prompt: PrintPrompt) async -> PrintPrompt.Choice {
        await withCheckedContinuation { continuation in
            self.promptContinuation = continuation
            self.prompt = prompt
        }
    }
    
    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Own Driver

extension PrintManager {
    /// Kendi sürücü için ön kontroller. Sorun varsa kullanıcıya sorar; nil → başlatma.
    private func prepareOwnDriver(pdf: URL, printer: String, duplex: Bool, settings: DriverSettings) async throws -> OwnDriverJob? {
        // 1) Araçlar
        guard let ghostscript = ToolLocator.ghostscript(customPath: settings.ghostscriptPath),
              let ghostscriptVersion = ToolLocator.version(of: ghostscript, argument: "--version") else {
            addLog("❌ Ghostscript bulunamadı")
            let choice = await ask(.missingGhostscript(customPath: settings.ghostscriptPath))
            if choice == .alternate {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install ghostscript", forType: .string)
                addLog("Komut panoya kopyalandı: brew install ghostscript")
            }
            return nil
        }
        guard let foo2qpdl = ToolLocator.foo2qpdl(customPath: settings.foo2qpdlPath),
              ToolLocator.version(of: foo2qpdl, argument: "-V") != nil else {
            addLog("❌ foo2qpdl bulunamadı")
            _ = await ask(.missingFoo2qpdl(customPath: settings.foo2qpdlPath))
            return nil
        }
        addLog("✓ Ghostscript \(ghostscriptVersion): \(ghostscript.path)")
        addLog("✓ foo2qpdl: \(foo2qpdl.path)")
        
        // 2) Kuyruk
        let customQueue = settings.rawQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let queue = customQueue.isEmpty ? PrinterService.shared.cupsQueueName(for: printer) : customQueue
        guard let status = await fetchQueueStatus(queue) else {
            addLog("❌ Kuyruk bulunamadı: \(queue)")
            _ = await ask(.queueNotFound(queue))
            return nil
        }
        if status.isStopped || !status.isAcceptingJobs {
            addLog("❌ Kuyruk durdurulmuş: \(queue) (\(status.stateReasons))")
            _ = await ask(.queueStopped(queue))
            return nil
        }
        if !status.isCLP300 {
            addLog("⚠️ Kuyruk CLP-300 gibi görünmüyor: \(status.makeAndModel) \(status.deviceURI)")
            guard await ask(.notCLP300(status)) == .proceed else { return nil }
        }
        if status.isOffline {
            addLog("⚠️ Yazıcı kapalı ya da bağlantısı yok görünüyor (\(status.stateReasons))")
            guard await ask(.printerOffline(status)) == .proceed else { return nil }
        }
        if !status.pendingJobs.isEmpty {
            addLog("⚠️ Kuyrukta bitmemiş iş var: \(status.pendingJobs.joined(separator: ", "))")
            guard await ask(.pendingJobs(status)) == .proceed else { return nil }
        }
        addLog("✓ Ham gönderim kuyruğu: \(queue) (\(status.deviceURI))")
        
        // 3) PDF'in kopyası: gönderim sürerken dosya değişse de etkilenmesin,
        //    gs korumalı klasörlere (Masaüstü, Belgeler) ayrıca erişmek zorunda kalmasın
        let directory = try await PDFProcessor.shared.workingDirectory()
        let source = directory.appendingPathComponent("source.pdf")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.copyItem(at: pdf, to: source)
        
        guard let pageCount = PDFProcessor.shared.pageCount(of: source), pageCount > 0 else {
            throw PDFProcessorError.noPagesFound
        }
        
        // Çift yönlü ve sayfa sayısı tek ise boş sayfa ekle
        var sheetCount = pageCount
        if duplex && pageCount % 2 != 0 {
            addLog("Tek sayıda sayfa (\(pageCount)) - çift yön için boş sayfa ekleniyor...")
            sheetCount += 1
        }
        
        addLog("Kalite: \(settings.resolution.title), \(isGrayscale ? "siyah-beyaz" : "renkli")")
        
        return OwnDriverJob(
            driver: QPDLDriver(tools: QPDLTools(ghostscript: ghostscript, foo2qpdl: foo2qpdl)),
            pdf: source,
            title: pdf.deletingPathExtension().lastPathComponent,
            pageCount: pageCount,
            sheetCount: sheetCount,
            resolution: settings.resolution,
            queue: queue,
            directory: directory
        )
    }
    
    /// Sayfayı orijinal PDF'ten render eder, gerekirse sorar, ham gönderir
    private func sendOwnDriverPage(at pageIndex: Int, job: OwnDriverJob) async throws -> Bool {
        let pageNumber = pageIndex + 1
        let isBlank = pageIndex >= job.pageCount
        let color = !isGrayscale && !isBlank
        var resolution = job.resolution
        
        addLog(isBlank ? "Boş sayfa hazırlanıyor..." : "Sayfa \(pageNumber) hazırlanıyor...")
        
        var page: QPDLPage
        do {
            page = try await render(job: job, pageIndex: pageIndex, color: color, resolution: resolution)
        } catch {
            addLog("❌ Sayfa \(pageNumber) hazırlanamadı: \(error.localizedDescription)")
            if await ask(.renderFailed(page: pageNumber, error: error)) == .proceed {
                addLog("Sayfa \(pageNumber) atlandı")
            } else if !isCancelled {
                cancel()
            }
            return false
        }
        
        // Olağan dışı büyük veri: göndermeden önce sor
        if page.byteCount > Self.largePageWarningBytes {
            addLog("⚠️ Sayfa \(pageNumber) verisi çok büyük: \(Self.formatBytes(page.byteCount))")
            let canLower = resolution != .dpi600
            switch await ask(.largePage(page: pageNumber, bytes: page.byteCount, canLowerResolution: canLower)) {
            case .alternate:
                resolution = .dpi600
                addLog("Sayfa \(pageNumber) 600 dpi ile yeniden hazırlanıyor...")
                page = try await render(job: job, pageIndex: pageIndex, color: color, resolution: resolution)
            case .proceed:
                break
            case .cancel:
                if !isCancelled {
                    cancel()
                }
                return false
            }
        }
        
        // Önceki iş takılı kaldıysa (yazıcı kapalı, kağıt bitti...) bitmesini bekle
        await waitForEmptyQueue(job.queue)
        guard !isCancelled else { return false }
        
        addLog("Sayfa \(pageNumber) yazıcıya gönderiliyor (\(Self.formatBytes(page.byteCount)))...")
        let title = isBlank ? "\(job.title) – boş sayfa" : "\(job.title) – s.\(pageNumber)"
        try await PrinterService.shared.printRaw(at: page.url, queue: job.queue, title: title)
        try? FileManager.default.removeItem(at: page.url)
        return true
    }
    
    private func render(job: OwnDriverJob, pageIndex: Int, color: Bool, resolution: QPDLResolution) async throws -> QPDLPage {
        let output = job.directory.appendingPathComponent("page_\(pageIndex + 1).\(color ? "zc" : "zm")")
        let page: QPDLPage
        if pageIndex >= job.pageCount {
            page = try await job.driver.renderBlankPage(resolution: resolution, to: output)
        } else {
            page = try await job.driver.renderPage(pdf: job.pdf, page: pageIndex + 1, color: color, resolution: resolution, to: output)
        }
        
        let seconds = String(format: "%.1f", page.duration)
        addLog("Sayfa \(pageIndex + 1) hazır: \(Self.formatBytes(page.byteCount)), \(seconds) sn (\(resolution.rawValue))")
        if !page.messages.isEmpty {
            // Bozuk PDF'lerde gs uyarı verip devam eder; ilk satırlar yeterli
            let summary = page.messages.split(separator: "\n").prefix(3).joined(separator: " | ")
            addLog("ℹ️ Ghostscript/foo2qpdl: \(summary)")
        }
        print("[QPDL] page \(pageIndex + 1) \(page.byteCount) bytes\n\(page.messages)")
        return page
    }
    
    /// Kuyrukta bitmemiş iş varsa ya da kuyruk durdurulduysa bekler (iptal edilebilir)
    private func waitForEmptyQueue(_ queue: String) async {
        var didLog = false
        while !isCancelled {
            guard let status = await fetchQueueStatus(queue),
                  !status.pendingJobs.isEmpty || status.isStopped else { return }
            if !didLog {
                let reason = status.isStopped ? "kuyruk durdurulmuş" : "bitmemiş iş: \(status.pendingJobs.joined(separator: ", "))"
                addLog("⏳ Yazıcı hazır değil (\(reason)). Yazıcıyı kontrol edin; bekleniyor...")
                didLog = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
    
    /// lpoptions/lpstat ~250 ms sürüyor; ana iş parçacığını bekletmesin
    private nonisolated func fetchQueueStatus(_ queue: String) async -> PrinterQueueStatus? {
        PrinterService.shared.queueStatus(queue)
    }
}

// MARK: - Types

/// Sayfaların yazıcıya nasıl gideceği
private enum PrintBackend {
    /// Sistem sürücüsü: PDFKit ile bölünmüş tek sayfalık PDF'ler `lp` ile
    case system(pageURLs: [URL])
    /// Kendi sürücü: orijinal PDF'ten gs + foo2qpdl, `lp -o raw`
    case own(OwnDriverJob)
}

private struct OwnDriverJob {
    let driver: QPDLDriver
    /// Geçici klasördeki kopya
    let pdf: URL
    let title: String
    /// Belgedeki sayfa sayısı; bunun üstündeki indeksler boş sayfa
    let pageCount: Int
    /// Basılacak toplam yaprak yüzü (çift yön boş sayfası dahil)
    let sheetCount: Int
    let resolution: QPDLResolution
    let queue: String
    let directory: URL
}

/// Yazdırma sırasında kullanıcıya sorulan karar
struct PrintPrompt: Identifiable {
    enum Choice {
        case proceed
        case alternate
        case cancel
    }
    
    struct Action: Identifiable {
        let title: String
        let choice: Choice
        var id: String { title }
    }
    
    let id = UUID()
    let title: String
    let message: String
    let actions: [Action]
    
    static func missingGhostscript(customPath: String) -> PrintPrompt {
        let location = customPath.isEmpty
            ? "Şu klasörlerde arandı: \(ToolLocator.searchDirectories.joined(separator: ", "))."
            : "Ayarlardaki yol çalışmıyor: \(customPath)"
        return PrintPrompt(
            title: "Ghostscript bulunamadı",
            message: """
            Kendi sürücü sayfaları Ghostscript ile hazırlar. \(location)

            Kurmak için Terminal'de şu komutu çalıştırın:
            brew install ghostscript

            Homebrew yoksa önce brew.sh adresindeki kurulum komutunu çalıştırın. \
            Ghostscript başka bir yerdeyse yolunu Ayarlar'a (⌘,) girin. \
            Geçici olarak "Sistem sürücüsü" moduna da geçebilirsiniz.
            """,
            actions: [
                Action(title: "Komutu Kopyala", choice: .alternate),
                Action(title: "Tamam", choice: .cancel),
            ]
        )
    }
    
    static func missingFoo2qpdl(customPath: String) -> PrintPrompt {
        let detail = customPath.isEmpty
            ? "Uygulama paketinde olması gerekiyordu (Contents/Helpers/foo2qpdl). Uygulamayı yeniden indirip kurun."
            : "Ayarlardaki yol çalışmıyor: \(customPath). Yolu düzeltin ya da boş bırakın (paketteki kullanılır)."
        return PrintPrompt(
            title: "foo2qpdl bulunamadı",
            message: detail,
            actions: [Action(title: "Tamam", choice: .cancel)]
        )
    }
    
    static func queueNotFound(_ queue: String) -> PrintPrompt {
        PrintPrompt(
            title: "Yazıcı kuyruğu bulunamadı",
            message: "'\(queue)' adlı bir CUPS kuyruğu yok. Ayarlar'daki (⌘,) ham kuyruk adını kontrol edin ya da boş bırakın.",
            actions: [Action(title: "Tamam", choice: .cancel)]
        )
    }
    
    static func queueStopped(_ queue: String) -> PrintPrompt {
        PrintPrompt(
            title: "Yazıcı kuyruğu durdurulmuş",
            message: """
            '\(queue)' kuyruğu durdurulmuş ya da iş kabul etmiyor.

            Sistem Ayarları > Yazıcılar ve Tarayıcılar > Yazdırma Sırası'nı açıp "Sürdür" deyin \
            ya da Terminal'de: cupsenable \(queue) && cupsaccept \(queue)
            """,
            actions: [Action(title: "Tamam", choice: .cancel)]
        )
    }
    
    static func notCLP300(_ status: PrinterQueueStatus) -> PrintPrompt {
        PrintPrompt(
            title: "Bu yazıcı CLP-300 değil gibi",
            message: """
            Kendi sürücü yalnızca Samsung CLP-300'ün anladığı veriyi üretir. \
            Seçili kuyruk: \(status.queue) (\(status.makeAndModel), \(status.deviceURI)).

            Başka bir yazıcıya gönderilirse anlamsız sayfalar basılabilir.
            """,
            actions: [
                Action(title: "Yine de Gönder", choice: .proceed),
                Action(title: "Vazgeç", choice: .cancel),
            ]
        )
    }
    
    static func printerOffline(_ status: PrinterQueueStatus) -> PrintPrompt {
        PrintPrompt(
            title: "Yazıcı kapalı görünüyor",
            message: """
            macOS, \(status.queue) yazıcısına ulaşamadığını bildiriyor. Yazıcının açık ve USB \
            kablosunun takılı olduğundan emin olun.

            Yine de başlatırsanız sayfalar yazıcı açılana kadar kuyrukta bekler.
            """,
            actions: [
                Action(title: "Yine de Başlat", choice: .proceed),
                Action(title: "Vazgeç", choice: .cancel),
            ]
        )
    }
    
    static func pendingJobs(_ status: PrinterQueueStatus) -> PrintPrompt {
        PrintPrompt(
            title: "Kuyrukta bekleyen iş var",
            message: """
            \(status.queue) kuyruğunda bitmemiş \(status.pendingJobs.count) iş var: \
            \(status.pendingJobs.joined(separator: ", ")).

            Takılı kalmış olabilirler; yeni sayfalar bunların arkasında bekler. \
            Yazdırma Sırası penceresinden silebilir ya da yazıcıyı kontrol edebilirsiniz.
            """,
            actions: [
                Action(title: "Yine de Başlat", choice: .proceed),
                Action(title: "Vazgeç", choice: .cancel),
            ]
        )
    }
    
    static func largePage(page: Int, bytes: Int, canLowerResolution: Bool) -> PrintPrompt {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        var actions: [Action] = []
        if canLowerResolution {
            actions.append(Action(title: "600 dpi ile Gönder", choice: .alternate))
        }
        actions.append(Action(title: "Yine de Gönder", choice: .proceed))
        actions.append(Action(title: "Yazdırmayı İptal Et", choice: .cancel))
        return PrintPrompt(
            title: "Sayfa \(page) çok büyük",
            message: """
            Sayfa \(page) için üretilen yazıcı verisi \(size). Olağan sayfalar 1–4 MB arası; \
            yazıcının belleği 32 MB. Yazıcı bu sayfada hata sayfası basabilir.
            \(canLowerResolution ? "\n600 dpi veriyi yaklaşık yarıya indirir." : "")
            """,
            actions: actions
        )
    }
    
    static func renderFailed(page: Int, error: Error) -> PrintPrompt {
        PrintPrompt(
            title: "Sayfa \(page) hazırlanamadı",
            message: """
            \(error.localizedDescription)

            Sayfayı atlayıp devam edebilirsiniz. Çift yönlü yazdırmada atlanan sayfa \
            arka yüz sırasını bozar.
            """,
            actions: [
                Action(title: "Sayfayı Atla", choice: .proceed),
                Action(title: "Yazdırmayı İptal Et", choice: .cancel),
            ]
        )
    }
}
