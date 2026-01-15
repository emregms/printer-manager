import Foundation
import AppKit

/// Yazıcı servisi - macOS native yazdırma API'lerini kullanarak
class PrinterService {
    static let shared = PrinterService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Sistemde mevcut yazıcıları listeler
    func availablePrinters() -> [String] {
        // macOS native yazıcı listesi
        return NSPrinter.printerNames
    }
    
    /// Tek sayfalık PDF'i belirtilen yazıcıya yazdırır
    func printPage(at url: URL, to printerName: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                do {
                    // PDF dokümanını yükle
                    guard let pdfDocument = CGPDFDocument(url as CFURL) else {
                        throw PrinterServiceError.cannotOpenPDF
                    }
                    
                    // NSPrintInfo yapılandır
                    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
                    printInfo.printer = NSPrinter(name: printerName) ?? NSPrinter()
                    printInfo.jobDisposition = .spool
                    printInfo.isHorizontallyCentered = true
                    printInfo.isVerticallyCentered = true
                    printInfo.scalingFactor = 1.0
                    
                    // Sayfa boyutunu ayarla
                    if let page = pdfDocument.page(at: 1) {
                        let mediaBox = page.getBoxRect(.mediaBox)
                        printInfo.paperSize = NSSize(width: mediaBox.width, height: mediaBox.height)
                    }
                    
                    // PrintOperation oluştur
                    let printOperation = PDFPrintOperation(
                        pdfDocument: pdfDocument,
                        printInfo: printInfo
                    )
                    
                    // Sessiz yazdırma (dialog gösterme)
                    printOperation.showsPrintPanel = false
                    printOperation.showsProgressPanel = false
                    
                    // Yazdır
                    printOperation.run()
                    
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - PDF Print Operation
class PDFPrintOperation: NSPrintOperation {
    private let pdfDocument: CGPDFDocument
    
    init(pdfDocument: CGPDFDocument, printInfo: NSPrintInfo) {
        self.pdfDocument = pdfDocument
        super.init()
        self.printInfo = printInfo
    }
    
    override func run() -> Bool {
        // Yazdırma işlemini gerçekleştir
        guard let context = NSGraphicsContext.current?.cgContext else {
            return false
        }
        
        if let page = pdfDocument.page(at: 1) {
            let mediaBox = page.getBoxRect(.mediaBox)
            context.beginPDFPage(nil)
            context.drawPDFPage(page)
            context.endPDFPage()
            context.closePDF()
        }
        
        return true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Errors
enum PrinterServiceError: LocalizedError {
    case cannotOpenPDF
    case printerNotFound
    case printFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:
            return "PDF dosyası açılamadı"
        case .printerNotFound:
            return "Yazıcı bulunamadı"
        case .printFailed(let reason):
            return "Yazdırma hatası: \(reason)"
        }
    }
}

