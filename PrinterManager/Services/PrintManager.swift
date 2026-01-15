import Foundation
import Combine

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
    
    /// Tahmini kalan toplam süre (saniye)
    var estimatedTimeRemaining: TimeInterval {
        guard isPrinting, let current = currentPage, totalPages > 0 else { return 0 }
        let remainingPages = totalPages - current
        let perPageTime = printDelay + cleanDelay
        return TimeInterval(remainingPages) * perPageTime + timeRemaining
    }
    
    // MARK: - Private Properties
    private var printTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    private var pendingDuplexContinuation: CheckedContinuation<Void, Never>?
    private var pdfURL: URL?
    private var printerName: String = ""
    private var printDelay: TimeInterval = 30
    private var cleanDelay: TimeInterval = 8
    private var isDuplex: Bool = false
    private var isGrayscale: Bool = false
    
    // MARK: - Public Methods
    
    /// Yazdırma işlemini başlatır
    func startPrinting(
        pdf: URL,
        printer: String,
        printDelay: TimeInterval,
        cleanDelay: TimeInterval,
        duplex: Bool,
        grayscale: Bool = false
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
            // PDF'i böl
            addLog("PDF sayfalara bölünüyor...")
            var pageURLs = try await PDFProcessor.shared.splitPDF(at: pdf)
            
            // Çift yönlü ve sayfa sayısı tek ise boş sayfa ekle
            if duplex && pageURLs.count % 2 != 0 {
                addLog("Tek sayıda sayfa (\(pageURLs.count)) - çift yön için boş sayfa ekleniyor...")
                let blankPage = try await PDFProcessor.shared.createBlankPage()
                pageURLs.append(blankPage)
            }
            
            totalPages = pageURLs.count
            addLog("\(pageURLs.count) sayfa hazırlandı")
            
            // Sayfa sırasını belirle
            let pagesToPrint: [Int]
            if duplex {
                // İlk geçiş: tek sayfalar (1, 3, 5...)
                pagesToPrint = Array(stride(from: 0, to: pageURLs.count, by: 2))
                addLog("Çift yönlü yazdırma - İlk geçiş: \(pagesToPrint.count) sayfa (tek sayfalar)")
            } else {
                // Tüm sayfalar
                pagesToPrint = Array(0..<pageURLs.count)
            }
            
            // Sayfaları yazdır
            try await printPages(pageURLs: pageURLs, pageIndices: pagesToPrint, isSecondPass: false)
            
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
                    let evenPages = Array(stride(from: 1, to: pageURLs.count, by: 2))
                    let reversedEvenPages = evenPages.reversed().map { $0 } // Ters çevir
                    addLog("Çift yönlü yazdırma - İkinci geçiş: \(reversedEvenPages.count) sayfa (çift sayfalar, ters sırada)")
                    try await printPages(pageURLs: pageURLs, pageIndices: reversedEvenPages, isSecondPass: true)
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
    
    private func printPages(pageURLs: [URL], pageIndices: [Int], isSecondPass: Bool) async throws {
        for (index, pageIndex) in pageIndices.enumerated() {
            guard !isCancelled else { break }
            
            let pageURL = pageURLs[pageIndex]
            currentPage = pageIndex + 1
            isCleaningPhase = false
            
            // 1) ÖNCE YAZDIR - hemen başla
            addLog("Sayfa \(pageIndex + 1) yazıcıya gönderiliyor...")
            do {
                try await PrinterService.shared.printPage(at: pageURL, to: printerName, grayscale: isGrayscale)
                addLog("✓ Sayfa \(pageIndex + 1) yazıcıya gönderildi")
            } catch {
                addLog("⚠️ Sayfa \(pageIndex + 1) yazdırma hatası: \(error.localizedDescription)")
            }
            
            guard !isCancelled else { break }
            
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
        
        // Temp dosyaları temizle
        await PDFProcessor.shared.cleanupTempFiles()
    }
}
