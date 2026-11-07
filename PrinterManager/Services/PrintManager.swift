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
    /// Yazıcı hatası nedeniyle duraklatıldıysa sebebi
    @Published var pauseReason: String?
    /// Sayfa geçişi yazıcının durumuna göre (süreler tahmin)
    @Published var usesSmartTiming: Bool = false
    /// Baskı sırası: geçişler ve adımlar. İş bitince gözden geçirmek için kalır.
    @Published private(set) var queue: PrintQueue?
    /// Şu an basılan adım
    @Published private(set) var currentStepID: UUID?
    /// Kağıt çevirme / yükleme penceresinin metni
    @Published private(set) var flipMessage = ""
    /// Son müdahalenin açıklaması (sıra panelinde gösterilir)
    @Published private(set) var lastIntervention: String?
    /// Son müdahale, o sayfa bitmeden geri alınabilir
    @Published private(set) var canUndoIntervention = false
    
    var currentStep: PrintStep? {
        currentStepID.flatMap { queue?.step($0) }
    }
    
    /// Tahmini kalan toplam süre (saniye)
    var estimatedTimeRemaining: TimeInterval {
        guard isPrinting, let queue = queue else { return 0 }
        let perPageTime = usesSmartTiming ? cycleEstimate : pageWait
        return TimeInterval(queue.pendingCount) * perPageTime + timeRemaining
    }
    
    /// Akıllı modda bir sayfanın (baskı + temizlik) tahmini süresi: son ölçümlerin
    /// ortalaması. Soğuk yazıcıda ilk sayfa ~40 sn sürdü.
    private var cycleEstimate: TimeInterval {
        let recent = cycleDurations.suffix(3)
        return recent.isEmpty ? 45 : recent.reduce(0, +) / Double(recent.count)
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
    /// Sabit modda (ve akıllı modda durum okunamazsa) sayfalar arası bekleme
    private var pageWait: TimeInterval = 38
    /// Akıllı modda ölçülen sayfa süreleri (gönderimden yeniden "Hazır"a)
    private var cycleDurations: [TimeInterval] = []
    /// Yazıcıya gönderilmiş adımlar (iptalde basıldı sayılır)
    private var sentStepIDs: Set<UUID> = []
    /// Geri alma için müdahaleden önceki sıra
    private var undoSnapshot: PrintQueue?
    private var isDuplex: Bool = false
    private var isGrayscale: Bool = false
    private var backend: PrintBackend?
    
    // MARK: - Public Methods
    
    /// Yazdırma işlemini başlatır
    func startPrinting(
        pdf: URL,
        printer: String,
        pageWait: TimeInterval,
        duplex: Bool,
        grayscale: Bool = false,
        timing: PageTimingMode = .fixed,
        driver: DriverSettings
    ) async {
        guard !isPrinting else { return }
        
        self.pdfURL = pdf
        self.printerName = printer
        self.pageWait = pageWait
        self.cycleDurations = []
        self.sentStepIDs = []
        self.undoSnapshot = nil
        self.canUndoIntervention = false
        self.lastIntervention = nil
        self.queue = nil
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
            
            // Yazıcının kendi bildirdiği durum (USB): sıkışma, kapak, kağıt, toner...
            let printerStatus = await fetchPrinterStatus()
            if let printerStatus = printerStatus {
                logPrinterStatus(printerStatus)
                if printerStatus.blocksPrinting {
                    guard await ask(.printerProblem(printerStatus)) == .proceed else {
                        addLog("Yazdırma başlatılmadı")
                        await cleanup()
                        return
                    }
                }
            }
            
            // Sayfa geçişi: yazıcı durumu okunabiliyorsa ona göre, değilse sabit süre
            switch (timing, printerStatus) {
            case (.smart, .some):
                usesSmartTiming = true
                addLog("Sayfa geçişi: akıllı (her sayfa basılıp kayış temizlenince)")
            case (.smart, .none):
                usesSmartTiming = false
                addLog("⚠️ Yazıcı durumu okunamadı; sabit süre kullanılacak (\(Int(pageWait)) sn)")
            case (.fixed, _):
                usesSmartTiming = false
                addLog("Sayfa geçişi: sabit süre (\(Int(pageWait)) sn)")
            }
            
            // Baskı sırası: çift yönde önce tek sayfalar (1, 3, 5...), kağıtlar
            // çevrilince çift sayfalar ters sırada (..., 6, 4, 2)
            let documentPages = PDFProcessor.shared.pageCount(of: pdf) ?? totalPages
            queue = PrintQueue(documentPageCount: documentPages, sheetPageCount: totalPages, duplex: duplex)
            if duplex {
                addLog("Çift yönlü yazdırma: önce \((totalPages + 1) / 2) ön yüz, sonra \(totalPages / 2) arka yüz")
            }
            
            try await runQueue()
            
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
    
    /// Kağıtlar çevrildi / yüklendi, sonraki geçişe devam et
    func continueWithEvenPages() {
        showFlipPagesDialog = false
        pendingDuplexContinuation?.resume()
        pendingDuplexContinuation = nil
    }
    
    // MARK: - Interventions
    
    /// Adımda kullanılabilecek müdahaleler (tekrar yazdır, kağıt bozuk, çift kağıt)
    func actions(for step: PrintStep) -> [PrintQueue.Action] {
        guard isPrinting else { return [] }
        return queue?.actions(for: step.id, currentStepID: currentStepID) ?? []
    }
    
    /// Müdahaleyi uygular: sıra hemen değişir, sonraki gönderimde geçerli olur
    func intervene(_ action: PrintQueue.Action, on step: PrintStep) {
        guard var updated = queue else { return }
        let snapshot = updated
        guard let message = updated.apply(action, to: step.id) else { return }
        queue = updated
        undoSnapshot = snapshot
        canUndoIntervention = true
        lastIntervention = message
        addLog("✋ \(message)")
    }
    
    /// Son müdahaleyi geri alır (o sırada basılan sayfa bitmeden)
    func undoIntervention() {
        guard canUndoIntervention, let snapshot = undoSnapshot else { return }
        queue = snapshot
        undoSnapshot = nil
        canUndoIntervention = false
        lastIntervention = nil
        addLog("↩︎ Son müdahale geri alındı")
    }
    
    /// Yeni belge ya da sıfırlama: biten işin sırasını temizle
    func clearQueue() {
        guard !isPrinting else { return }
        queue = nil
        currentStepID = nil
        lastIntervention = nil
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
    
    /// Sıradaki adımları geçiş geçiş basar. Sıra baskı sırasında değişebilir
    /// (tekrar yazdır, çift kağıt...): her adımda yeniden okunur.
    private func runQueue() async throws {
        var currentPass: Int?
        while !isCancelled, let step = queue?.nextPendingStep {
            if step.pass != currentPass, let pass = queue?.pass(step.pass) {
                // İlk geçiş dışında: kağıtları çevir / yükle
                if currentPass != nil {
                    guard await preparePass(pass) else { continue }
                }
                addLog("▶︎ \(pass.title)")
                currentPass = step.pass
            }
            try await printStep(step.id)
        }
        currentStepID = nil
    }
    
    /// Geçişten önce kullanıcıdan kağıtları çevirmesini / yüklemesini ister.
    /// Kullanıcı yeniden basımı atlarsa false.
    private func preparePass(_ pass: PrintPass) async -> Bool {
        switch pass.kind {
        case .single, .fronts:
            return true
        case .backs, .reprintBacks:
            flipMessage = pass.kind == .backs
                ? "Tek numaralı sayfalar yazdırıldı.\nLütfen kağıtları ters çevirip yazıcıya yükleyiniz."
                : "Yeniden basılan ön yüzler yazdırıldı.\nBu kağıtları ters çevirip yazıcıya yükleyiniz."
            showFlipPagesDialog = true
            addLog("Kağıtları çevirmeniz bekleniyor...")
            // Pencere kapalıyken (arka planda yazdırırken) uyarı görünsün
            Task { @MainActor in AppWindow.showIfHidden() }
            await withCheckedContinuation { continuation in
                self.pendingDuplexContinuation = continuation
            }
            return !isCancelled
        case .reprintSingle, .reprintFronts:
            let sheets = queue?.steps(inPass: pass.id).filter { $0.state == .pending }.count ?? 0
            if await ask(.reprintStart(sheets: sheets, duplex: pass.kind == .reprintFronts)) == .proceed {
                return true
            }
            queue?.skipPending(inPass: pass.id, note: "Yeniden basım atlandı")
            if pass.kind == .reprintFronts {
                queue?.skipPending(inPass: pass.id + 1, note: "Yeniden basım atlandı")
            }
            addLog("Yeniden basım atlandı")
            return false
        }
    }
    
    /// Tek bir adımı basar: yazıcı hazır olunca gönder, sayfa ve temizlik bitene
    /// kadar bekle. Hata ya da "yeniden gönder" seçilirse aynı adım tekrar denenir.
    private func printStep(_ id: UUID) async throws {
        guard let step = queue?.step(id) else { return }
        let pageNumber = step.pageNumber
        
        currentStepID = id
        currentPage = pageNumber
        queue?.setState(.printing, for: id)
        isCleaningPhase = false
        progress = 0
        // Önceki sayfaya yapılan müdahale artık geri alınamaz
        undoSnapshot = nil
        canUndoIntervention = false
        
        pageLoop: while !isCancelled {
            // 0) Yazıcı hata bildiriyorsa gönderme (kuyruk şişmesin); akıllı modda
            //    önceki iş bitip yazıcı "Hazır" olana kadar da bekle
            guard await waitUntilPrinterAccepts(pageNumber: pageNumber) else { break pageLoop }
            
            // 1) Gönder
            var didSend = false
            do {
                didSend = try await sendPage(at: step.pageIndex)
                if didSend {
                    sentStepIDs.insert(id)
                    addLog("✓ Sayfa \(pageNumber) (\(step.side.title.lowercased(with: Locale(identifier: "tr")))) yazıcıya gönderildi")
                }
            } catch {
                addLog("❌ Sayfa \(pageNumber) gönderilemedi: \(error.localizedDescription)")
                switch await ask(.sendFailed(page: pageNumber, error: error)) {
                case .proceed:
                    continue pageLoop
                case .alternate:
                    addLog("Sayfa \(pageNumber) atlandı")
                    queue?.setState(.skipped, for: id, note: "Atlandı")
                case .cancel:
                    if !isCancelled {
                        cancel()
                    }
                }
                break pageLoop
            }
            
            // Sayfa atlandıysa kağıt geçmedi, beklemeye gerek yok
            guard didSend, !isCancelled else {
                if !didSend && !isCancelled {
                    queue?.setState(.skipped, for: id, note: "Atlandı")
                }
                break pageLoop
            }
            
            // 2) Bekle: sayfa basılsın, kayış temizlensin
            if usesSmartTiming {
                switch await waitForPageCycle(pageNumber: pageNumber) {
                case .done, .cancelled:
                    break pageLoop
                case .resend:
                    addLog("Sayfa \(pageNumber) yeniden gönderiliyor")
                    continue pageLoop
                }
            }
            
            // Sabit süre: geçişin son sayfasından sonra beklemeye gerek yok
            // (kağıt çevirme ya da iş sonu)
            if queue?.hasPending(inPass: step.pass) == true {
                addLog("Sayfa \(pageNumber) basılıyor, \(Int(pageWait)) sn bekleniyor...")
                await waitWithProgress(duration: pageWait, phase: .printing)
            }
            break pageLoop
        }
        
        if sentStepIDs.contains(id) {
            queue?.finishPrinting(id)
        }
    }
    
    private enum PageCycleResult {
        case done
        case resend
        case cancelled
    }
    
    /// Gönderilen sayfayı izler: yazıcı işi alır, basar, kayışı temizler ve
    /// yeniden "Hazır" olur. Soğukken uzun, ısınınca kısa sürer; sabit süre yok.
    private func waitForPageCycle(pageNumber: Int) async -> PageCycleResult {
        let start = Date()
        let estimate = cycleEstimate
        var started = false
        var dataDone = false
        var idleSince: Date?
        
        while !isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            progress = min(elapsed / estimate, 0.97)
            timeRemaining = max(estimate - elapsed, 0)
            
            guard let status = await fetchPrinterStatus() else {
                // Durum okunamıyor: sabit süreye geri dön
                addLog("⚠️ Yazıcı durumu okunamadı; sabit süreyle bekleniyor")
                await waitWithProgress(duration: max(pageWait - elapsed, 0), phase: .printing)
                return .done
            }
            
            if status.blocksPrinting {
                await pauseForPrinterError(status)
                guard !isCancelled else { return .cancelled }
                
                // Hata sırasında sayfa yarım kalmış olabilir
                switch await ask(.pageAfterError(page: pageNumber)) {
                case .alternate:
                    _ = await waitUntilPrinterAccepts(pageNumber: pageNumber)
                    return isCancelled ? .cancelled : .resend
                case .proceed:
                    started = true
                    dataDone = true
                    idleSince = nil
                    continue
                case .cancel:
                    if !isCancelled {
                        cancel()
                    }
                    return .cancelled
                }
            }
            
            if !started {
                if status.isWorking {
                    started = true
                } else if elapsed > 120 {
                    // İş kuyrukta takıldıysa waitForEmptyQueue bir sonraki sayfada yakalar
                    addLog("⚠️ Yazıcı sayfa \(pageNumber)'i 2 dakikada almadı; kuyruğu kontrol edin")
                    started = true
                }
            } else {
                if !dataDone && !status.hasJob {
                    // Sayfa verisi bitti; yazıcı sayfayı bitirip kayışı temizliyor
                    dataDone = true
                    isCleaningPhase = true
                }
                if status.isIdle {
                    // Kısa bir "Hazır" anına güvenme: 2 sn kesintisiz hazır olsun
                    idleSince = idleSince ?? Date()
                    if Date().timeIntervalSince(idleSince!) >= 2 {
                        break
                    }
                } else {
                    idleSince = nil
                }
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard !isCancelled else { return .cancelled }
        
        let duration = Date().timeIntervalSince(start)
        cycleDurations.append(duration)
        addLog("Sayfa \(pageNumber) basıldı, kayış temizlendi: \(Int(duration.rounded())) sn")
        progress = 1
        timeRemaining = 0
        return .done
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
        // İptalde gönderilmiş sayfa basılmış sayılır; gönderilmemişler atlanmış
        if let id = currentStepID {
            if sentStepIDs.contains(id) {
                queue?.finishPrinting(id)
            } else if queue?.step(id)?.state == .printing {
                queue?.setState(.skipped, for: id, note: "İptal edildi")
            }
        }
        currentStepID = nil
        canUndoIntervention = false
        undoSnapshot = nil
        
        isPrinting = false
        isPaused = false
        currentPage = nil
        progress = 0
        timeRemaining = 0
        isCleaningPhase = false
        showFlipPagesDialog = false
        pauseReason = nil
        usesSmartTiming = false
        backend = nil
        
        // Temp dosyaları temizle
        await PDFProcessor.shared.cleanupTempFiles()
    }
    
    /// Soruyu ekrana getirir ve cevabı bekler
    private func ask(_ prompt: PrintPrompt) async -> PrintPrompt.Choice {
        Task { @MainActor in AppWindow.showIfHidden() }
        return await withCheckedContinuation { continuation in
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
        
        var colorTables: PrinterColorTables?
        if settings.photoMode {
            colorTables = PrinterColorTables.find()
            if colorTables == nil {
                addLog("⚠️ Fotoğraf modu: renk dosyaları bulunamadı; standart renkle basılıyor")
            }
        }
        
        let photo = colorTables.map { ", fotoğraf modu (\($0.source.title))" } ?? ""
        addLog("Kalite: \(settings.resolution.title), \(isGrayscale ? "siyah-beyaz" : "renkli")\(photo)")
        
        return OwnDriverJob(
            driver: QPDLDriver(tools: QPDLTools(ghostscript: ghostscript, foo2qpdl: foo2qpdl, colorTables: colorTables)),
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
    
    /// Yazıcının USB'den bildirdiği durum; yazıcı bağlı değilse nil
    private nonisolated func fetchPrinterStatus() async -> PrinterStatus? {
        try? PrinterStatusReader.read()
    }
    
    /// Sayfa göndermeden önce: kullanıcı duraklattıysa ya da yazıcı hata bildiriyorsa
    /// bekler; akıllı modda yazıcı "Hazır" olana kadar da bekler. İptalde false.
    private func waitUntilPrinterAccepts(pageNumber: Int) async -> Bool {
        var loggedBusy = false
        while !isCancelled {
            if isPaused {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            // Okunamıyorsa gönderimi engelleme (eski davranış)
            guard let status = await fetchPrinterStatus() else { return true }
            
            if status.blocksPrinting {
                await pauseForPrinterError(status)
                continue
            }
            if !usesSmartTiming || status.isIdle {
                return true
            }
            if !loggedBusy {
                addLog("⏳ Yazıcı meşgul (\(status.title)); sayfa \(pageNumber) için hazır olması bekleniyor...")
                loggedBusy = true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }
    
    /// Yazıcı hatasında duraklatır: hata düzelip kullanıcı "Devam" diyene kadar
    /// sayfa gönderilmez (iptal edilebilir)
    private func pauseForPrinterError(_ status: PrinterStatus) async {
        isPaused = true
        pauseReason = [status.title, status.advice].compactMap { $0 }.joined(separator: ". ")
        addLog("⛔ Yazıcı hatası: \(status.title). Gönderim durduruldu; sorunu giderip Devam'a basın.")
        
        var lastKey = status.key
        var announcedFixed = false
        while !isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            if let current = await fetchPrinterStatus(), current.blocksPrinting {
                if current.key != lastKey {
                    addLog("⛔ Yazıcı hatası: \(current.title)")
                    lastKey = current.key
                    pauseReason = [current.title, current.advice].compactMap { $0 }.joined(separator: ". ")
                }
                // Hata sürerken "Devam" denirse yine bekle
                isPaused = true
                announcedFixed = false
                continue
            }
            
            if isPaused {
                if !announcedFixed {
                    addLog("✓ Yazıcı hatası düzeldi. Devam etmek için Devam'a basın.")
                    pauseReason = "Hata düzeldi. Devam etmek için Devam'a basın."
                    announcedFixed = true
                }
                continue
            }
            break
        }
        pauseReason = nil
    }
    
    private func logPrinterStatus(_ status: PrinterStatus) {
        let icon: String
        switch status.severity {
        case .ok: icon = "✓"
        case .warning: icon = "⚠️"
        case .error: icon = "❗"
        }
        addLog("\(icon) Yazıcı: \(status.title)")
        for toner in status.toners where toner.isLow && toner.percent != nil {
            addLog("⚠️ \(toner.color.name) toner az: %\(toner.percent!)\(toner.partNumber.map { " (\($0))" } ?? "")")
        }
    }
}

#if DEBUG
// MARK: - Screenshot Demo

extension PrintManager {
    /// Ekran görüntüsü için örnek sıra: 6 sayfa çift yön; 3. sayfa bir kez yeniden basılmış,
    /// 5/6 kağıdı bozuk işaretlenmiş, 4. sayfanın arka yüzü basılıyor. Hiçbir şey gönderilmez.
    func showDemoQueue() {
        var demo = PrintQueue(documentPageCount: 6, sheetPageCount: 6, duplex: true)
        func id(_ page: Int, _ side: PrintStep.Side) -> UUID {
            demo.steps.first { $0.pageNumber == page && $0.side == side && $0.state == .pending }!.id
        }
        demo.setState(.printed, for: id(1, .front))
        _ = demo.apply(.reprintNow, to: id(3, .front))
        demo.setState(.printed, for: id(3, .front))
        demo.setState(.printed, for: id(5, .front))
        let six = id(6, .back)
        demo.setState(.printed, for: six)
        let current = id(4, .back)
        demo.setState(.printing, for: current)
        let message = demo.apply(.spoilSheet, to: six)
        
        queue = demo
        currentStepID = current
        currentPage = 4
        totalPages = demo.steps.count
        usesSmartTiming = true
        isPrinting = true
        progress = 0.58
        timeRemaining = 17
        lastIntervention = message
        canUndoIntervention = true
        logs = []
        addLog("Kalite: 1200x600 dpi (önerilen), renkli, fotoğraf modu")
        addLog("✓ Sayfa 6 (arka yüz) yazıcıya gönderildi")
        addLog("Sayfa 6 basıldı, kayış temizlendi: 38 sn")
        addLog("✋ \(message ?? "")")
        addLog("✓ Sayfa 4 (arka yüz) yazıcıya gönderildi")
    }
    
    func endDemo() {
        isPrinting = false
        queue = nil
        currentStepID = nil
        currentPage = nil
        lastIntervention = nil
        canUndoIntervention = false
        progress = 0
        timeRemaining = 0
    }
}
#endif

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
    
    static func printerProblem(_ status: PrinterStatus) -> PrintPrompt {
        PrintPrompt(
            title: "Yazıcı: \(status.title)",
            message: """
            \(status.advice ?? "Yazıcıyı kontrol edin.")
            
            Başlatırsanız yazdırma duraklatılmış olarak bekler; sorun düzelip Devam'a \
            basana kadar sayfa gönderilmez.
            """,
            actions: [
                Action(title: "Başlat ve Bekle", choice: .proceed),
                Action(title: "Vazgeç", choice: .cancel),
            ]
        )
    }
    
    static func reprintStart(sheets: Int, duplex: Bool) -> PrintPrompt {
        PrintPrompt(
            title: "Bozulan \(sheets) \(duplex ? "kağıt" : "sayfa") yeniden basılacak",
            message: duplex
                ? "Tepsiye \(sheets) boş kağıt koyun. Önce ön yüzler basılır, sonra kağıtları çevirmeniz istenir."
                : "Tepside boş kağıt olduğundan emin olun.",
            actions: [
                Action(title: "Başlat", choice: .proceed),
                Action(title: "Yeniden Basmayı Atla", choice: .cancel),
            ]
        )
    }
    
    static func sendFailed(page: Int, error: Error) -> PrintPrompt {
        PrintPrompt(
            title: "Sayfa \(page) gönderilemedi",
            message: "\(error.localizedDescription)\n\nSonraki sayfalar bu sorun çözülmeden gönderilmez.",
            actions: [
                Action(title: "Tekrar Dene", choice: .proceed),
                Action(title: "Sayfayı Atla", choice: .alternate),
                Action(title: "Yazdırmayı İptal Et", choice: .cancel),
            ]
        )
    }
    
    static func pageAfterError(page: Int) -> PrintPrompt {
        PrintPrompt(
            title: "Sayfa \(page) düzgün basıldı mı?",
            message: """
            Yazıcı bu sayfa sırasında hata verdi. Kağıt sıkıştıysa ya da sayfa \
            eksik çıktıysa yeniden gönderin.
            """,
            actions: [
                Action(title: "Sayfayı Yeniden Gönder", choice: .alternate),
                Action(title: "Düzgün, Devam Et", choice: .proceed),
                Action(title: "Yazdırmayı İptal Et", choice: .cancel),
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
