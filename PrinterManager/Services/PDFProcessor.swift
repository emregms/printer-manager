import Foundation
import PDFKit

/// PDF işleme servisi - native PDFKit kullanarak
actor PDFProcessor {
    static let shared = PDFProcessor()
    
    private var tempDirectory: URL?
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// PDF'i tek sayfalık dosyalara böler
    func splitPDF(at url: URL) async throws -> [URL] {
        guard let document = PDFDocument(url: url) else {
            throw PDFProcessorError.cannotOpenPDF
        }
        
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw PDFProcessorError.noPagesFound
        }
        
        // Temp dizini oluştur
        let tempDir = try createTempDirectory()
        self.tempDirectory = tempDir
        
        var pageURLs: [URL] = []
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Yeni tek sayfalık PDF oluştur
            let newDocument = PDFDocument()
            newDocument.insert(page, at: 0)
            
            let pageURL = tempDir.appendingPathComponent("page_\(pageIndex + 1).pdf")
            
            if newDocument.write(to: pageURL) {
                pageURLs.append(pageURL)
            } else {
                throw PDFProcessorError.cannotWritePage(pageIndex + 1)
            }
        }
        
        return pageURLs
    }
    
    /// PDF sayfa sayısını döndürür (non-isolated for sync access)
    nonisolated func pageCount(of url: URL) -> Int? {
        guard let document = PDFDocument(url: url) else { return nil }
        return document.pageCount
    }
    
    /// Temp dosyalarını temizler
    func cleanupTempFiles() async {
        guard let tempDir = tempDirectory else { return }
        
        do {
            try FileManager.default.removeItem(at: tempDir)
            self.tempDirectory = nil
        } catch {
            print("Temp dosya temizleme hatası: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrinterManager")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        return tempDir
    }
}

// MARK: - Errors
enum PDFProcessorError: LocalizedError {
    case cannotOpenPDF
    case noPagesFound
    case cannotWritePage(Int)
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:
            return "PDF dosyası açılamadı"
        case .noPagesFound:
            return "PDF'de sayfa bulunamadı"
        case .cannotWritePage(let page):
            return "Sayfa \(page) yazılamadı"
        }
    }
}
