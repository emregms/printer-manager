import Foundation
import AppKit
import PDFKit

/// Yazıcı servisi - macOS native yazdırma API'lerini kullanarak
class PrinterService {
    static let shared = PrinterService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Sistemde mevcut yazıcıları listeler
    func availablePrinters() -> [String] {
        return NSPrinter.printerNames
    }
    
    /// Tek sayfalık PDF'i belirtilen yazıcıya yazdırır
    /// - Parameters:
    ///   - url: PDF dosyasının URL'si
    ///   - printerName: Yazıcı adı
    ///   - grayscale: Siyah beyaz modda yazdırma
    func printPage(at url: URL, to printerName: String, grayscale: Bool = false) async throws {
        // lp komutu ile yazdır - en güvenilir yöntem
        // lp -d "yazıcı_adı" -o ColorModel=Gray dosya.pdf
        
        var arguments = ["-d", printerName]
        
        // Siyah beyaz modu
        if grayscale {
            arguments.append(contentsOf: ["-o", "ColorModel=Gray"])
        }
        
        arguments.append(url.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let status = process.terminationStatus
            
            if status != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Bilinmeyen hata"
                print("[PRINT] lp hatası: \(errorMessage)")
                throw PrinterServiceError.printFailed(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            print("[PRINT] lp başarılı: \(output)")
            
        } catch let error as PrinterServiceError {
            throw error
        } catch {
            print("[PRINT] Process hatası: \(error)")
            throw PrinterServiceError.printFailed(error.localizedDescription)
        }
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
            return "Yazıcı bulunamadı veya bağlı değil"
        case .printFailed(let reason):
            return "Yazdırma hatası: \(reason)"
        }
    }
}
