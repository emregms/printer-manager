import Foundation
import AppKit
import PDFKit

/// Yazıcı servisi - macOS native yazdırma API'lerini kullanarak
class PrinterService {
    static let shared = PrinterService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Sistemde mevcut yazıcıları listeler (UI için orijinal isimler)
    func availablePrinters() -> [String] {
        return NSPrinter.printerNames
    }
    
    /// NSPrinter adını CUPS formatına dönüştürür
    /// NSPrinter: "Samsung CLP-300" → CUPS: "Samsung_CLP_300"
    private func cupsPrinterName(from displayName: String) -> String {
        // Boşlukları ve tireleri alt tire yap
        return displayName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
    
    /// Yazıcının bağlı ve erişilebilir olup olmadığını kontrol eder
    /// - Parameter printerName: Kontrol edilecek yazıcı adı (görüntülenen ad)
    /// - Returns: Yazıcı erişilebilirse true, değilse false
    func isPrinterAvailable(_ printerName: String) -> Bool {
        // CUPS formatına dönüştür
        let cupsName = cupsPrinterName(from: printerName)
        
        // lpstat -p yazıcı_adı komutu ile yazıcı durumunu kontrol et
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lpstat")
        process.arguments = ["-p", cupsName]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let status = process.terminationStatus
            
            if status != 0 {
                print("[PRINTER] Yazıcı bulunamadı: \(printerName) (CUPS: \(cupsName))")
                return false
            }
            
            // Çıktıyı kontrol et - "disabled" veya "not accepting" varsa yazıcı hazır değil
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            if output.contains("disabled") || output.contains("not accepting") {
                print("[PRINTER] Yazıcı devre dışı: \(printerName)")
                return false
            }
            
            print("[PRINTER] ✓ Yazıcı erişilebilir: \(printerName)")
            return true
            
        } catch {
            print("[PRINTER] lpstat hatası: \(error)")
            return false
        }
    }
    
    /// Tek sayfalık PDF'i belirtilen yazıcıya yazdırır
    /// - Parameters:
    ///   - url: PDF dosyasının URL'si
    ///   - printerName: Yazıcı adı (görüntülenen ad)
    ///   - grayscale: Siyah beyaz modda yazdırma
    func printPage(at url: URL, to printerName: String, grayscale: Bool = false) async throws {
        // CUPS formatına dönüştür
        let cupsName = cupsPrinterName(from: printerName)
        
        // lp komutu ile yazdır
        var arguments = ["-d", cupsName]
        
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
            print("[PRINT] ✓ Yazdırma başarılı: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            
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
    case printerNotAvailable(String)
    case printFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF:
            return "PDF dosyası açılamadı"
        case .printerNotFound:
            return "Yazıcı bulunamadı"
        case .printerNotAvailable(let name):
            return "'\(name)' yazıcısı bağlı değil veya erişilemiyor"
        case .printFailed(let reason):
            return "Yazdırma hatası: \(reason)"
        }
    }
}
