import Foundation
import Combine

/// Ana yazdırma yöneticisi - reaktif state yönetimi
@MainActor
class PrintManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isPrinting: Bool = false
    @Published var currentPage: Int?
    @Published var totalPages: Int = 0
    @Published var progress: Double = 0.0
    @Published var timeRemaining: TimeInterval = 0
    @Published var isCleaningPhase: Bool = false
    @Published var logs: [String] = []
    @Published var showFlipPagesDialog: Bool = false
    
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
        
        do {
            // PDF'i böl
            addLog("PDF sayfalara bölünüyor...")
            let pageURLs = try await PDFProcessor.shared.splitPDF(at: pdf)
            totalPages = pageURLs.count
            addLog("\(pageURLs.count) sayfa hazırlandı")
            
            // Sayfa sırasını belirle
            let pagesToPrint: [Int]
            if duplex {
                // İlk geçiş: tek sayfalar (1, 3, 5...)
                pagesToPrint = Array(stride(from: 0, to: pageURLs.count, by: 2))
                addLog("Çift yönlü yazdırma - İlk geçiş: \(pagesToPrint.count) sayfa")
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
                    // İkinci geçiş: çift sayfalar (2, 4, 6...)
                    let evenPages = Array(stride(from: 1, to: pageURLs.count, by: 2))
                    addLog("Çift yönlü yazdırma - İkinci geçiş: \(evenPages.count) sayfa")
                    try await printPages(pageURLs: pageURLs, pageIndices: evenPages, isSecondPass: true)
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
        pendingDuplexContinuation?.resume()
        pendingDuplexContinuation = nil
        addLog("⚠️ Yazdırma iptal edildi")
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
            
            addLog("Sayfa \(pageIndex + 1) yazdırılıyor...")
            
            // Yazdırma beklemesi
            await waitWithProgress(duration: printDelay, phase: .printing)
            
            guard !isCancelled else { break }
            
            // Yazdır
            do {
                try await PrinterService.shared.printPage(at: pageURL, to: printerName, grayscale: isGrayscale)
                addLog("Sayfa \(pageIndex + 1) yazıcıya gönderildi")
            } catch {
                addLog("⚠️ Sayfa \(pageIndex + 1) yazdırma hatası: \(error.localizedDescription)")
            }
            
            // Son sayfa değilse temizlik beklemesi
            if index < pageIndices.count - 1 && !isCancelled {
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
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(duration)
        
        while Date() < endTime && !isCancelled {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, duration - elapsed)
            
            self.timeRemaining = remaining
            self.progress = elapsed / duration
            
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        self.progress = 1.0
        self.timeRemaining = 0
    }
    
    private func cleanup() async {
        isPrinting = false
        currentPage = nil
        progress = 0
        timeRemaining = 0
        isCleaningPhase = false
        showFlipPagesDialog = false
        
        // Temp dosyaları temizle
        await PDFProcessor.shared.cleanupTempFiles()
    }
}
