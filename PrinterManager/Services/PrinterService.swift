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
    
    /// NSPrinter adını CUPS kuyruk adına dönüştürür
    /// NSPrinter: "Samsung CLP-300" → CUPS: "Samsung_CLP_300"
    func cupsQueueName(for displayName: String) -> String {
        // Boşlukları ve tireleri alt tire yap
        let guess = displayName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        
        let queues = run("/usr/bin/lpstat", ["-e"])?
            .split(separator: "\n").map(String.init) ?? []
        if queues.isEmpty || queues.contains(guess) {
            return guess
        }
        
        // Kuyruk farklı adla eklenmişse açıklamasından (printer-info) bul
        for queue in queues where queueAttributes(queue)["printer-info"] == displayName {
            return queue
        }
        return guess
    }
    
    /// Tüm CUPS kuyruk adları
    func allQueues() -> [String] {
        run("/usr/bin/lpstat", ["-e"])?
            .split(separator: "\n").map(String.init) ?? []
    }
    
    /// USB'ye bağlı CLP-300'lerin aygıt adresleri (usb://Samsung/CLP-300?serial=...)
    func connectedCLP300DeviceURIs() -> [String] {
        let output = run("/usr/sbin/lpinfo", ["--include-schemes", "usb", "-v"]) ?? ""
        return output
            .split(separator: "\n")
            .compactMap { line in line.split(separator: " ").last.map(String.init) }
            .filter { $0.range(of: "CLP-?300", options: [.regularExpression, .caseInsensitive]) != nil }
    }
    
    /// Kuyruğun durumunu okur. `lpstat` çıktısı sistem diline göre çevrildiği için
    /// dilden bağımsız `lpoptions` alanları kullanılır.
    func queueStatus(_ queue: String) -> PrinterQueueStatus? {
        let attributes = queueAttributes(queue)
        guard !attributes.isEmpty else { return nil }
        
        // Bekletilen (held) ve durdurulan (stopped) işler sırayı tutmaz: CUPS
        // onları atlar. PrinterManager kuyruğunda bunlar başka uygulamalardan
        // gelen, uygulamada açılacak belgeler
        let pendingJobs: [String]
        if let jobs = CupsJobs.activeJobs(queue: queue) {
            pendingJobs = jobs
                .filter { $0.state != "held" && $0.state != "stopped" }
                .map { "\(queue)-\($0.id)" }
        } else {
            // lpstat -o satırları: "<kuyruk>-<iş no> <kullanıcı> <boyut> <tarih>"
            pendingJobs = run("/usr/bin/lpstat", ["-o", queue])?
                .split(separator: "\n")
                .compactMap { $0.split(separator: " ").first.map(String.init) } ?? []
        }
        
        return PrinterQueueStatus(
            queue: queue,
            isStopped: attributes["printer-state"] == "5",
            isAcceptingJobs: attributes["printer-is-accepting-jobs"] != "false",
            stateReasons: attributes["printer-state-reasons"] ?? "none",
            makeAndModel: attributes["printer-make-and-model"] ?? "",
            deviceURI: attributes["device-uri"] ?? "",
            pendingJobs: pendingJobs,
            isShared: attributes["printer-is-shared"] == "true",
            info: attributes["printer-info"] ?? queue
        )
    }
    
    /// Kuyruğun kalıcı kimliği (AirPrint duyurusu için); ana iş parçacığında çağırmayın
    func printerUUID(_ queue: String) -> String? {
        let output = run("/usr/bin/ipptool", ["-tv", "ipp://localhost/printers/\(queue)", "get-printer-attributes.test"])
        return output?
            .split(separator: "\n")
            .first { $0.contains("printer-uuid (uri)") }
            .flatMap { $0.components(separatedBy: "urn:uuid:").last }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    /// Sistemin Yazıcı Paylaşımı açık mı (Paylaşma ayarları); ana iş parçacığında çağırmayın
    var isPrinterSharingEnabled: Bool {
        run("/usr/sbin/cupsctl", [])?.contains("_share_printers=1") == true
    }
    
    /// Yazıcının bağlı ve erişilebilir olup olmadığını kontrol eder
    /// - Parameter printerName: Kontrol edilecek yazıcı adı (görüntülenen ad)
    /// - Returns: Yazıcı erişilebilirse true, değilse false
    func isPrinterAvailable(_ printerName: String) -> Bool {
        let cupsName = cupsQueueName(for: printerName)
        
        guard let status = queueStatus(cupsName) else {
            print("[PRINTER] Yazıcı bulunamadı: \(printerName) (CUPS: \(cupsName))")
            return false
        }
        
        if status.isStopped || !status.isAcceptingJobs {
            print("[PRINTER] Yazıcı devre dışı: \(printerName)")
            return false
        }
        
        print("[PRINTER] ✓ Yazıcı erişilebilir: \(printerName)")
        return true
    }
    
    /// Hazır yazıcı verisini (QPDL) filtresiz, ham olarak gönderir.
    /// `-o raw` sistem sürücüsünün filtre zincirini tamamen atlar.
    /// `-H immediate`: PrinterManager kuyruğu gelen işleri varsayılan olarak
    /// bekletir; uygulamanın kendi işleri beklemeden basılsın.
    /// - Parameters:
    ///   - url: Ham dosya (.zc / .zm)
    ///   - queue: CUPS kuyruk adı
    ///   - title: Kuyrukta görünecek iş adı
    func printRaw(at url: URL, queue: String, title: String) async throws {
        try submit(["-d", queue, "-o", "raw", "-H", "immediate", "-t", title, url.path])
    }
    
    /// Tek sayfalık PDF'i belirtilen yazıcıya yazdırır
    /// - Parameters:
    ///   - url: PDF dosyasının URL'si
    ///   - printerName: Yazıcı adı (görüntülenen ad)
    ///   - grayscale: Siyah beyaz modda yazdırma
    func printPage(at url: URL, to printerName: String, grayscale: Bool = false) async throws {
        // CUPS formatına dönüştür
        let cupsName = cupsQueueName(for: printerName)
        
        // lp komutu ile yazdır (-H immediate: PrinterManager kuyruğu işleri bekletir)
        var arguments = ["-d", cupsName, "-H", "immediate"]
        
        // Siyah beyaz modu
        if grayscale {
            arguments.append(contentsOf: ["-o", "ColorModel=Gray"])
        }
        
        arguments.append(url.path)
        
        try submit(arguments)
    }
    
    // MARK: - Private Methods
    
    /// `lp` ile iş gönderir
    private func submit(_ arguments: [String]) throws {
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
    
    /// `lpoptions -p <kuyruk>` alanları (printer-state=3 printer-info='...' ...)
    /// Salt okunur: -o verilmeden ayar dosyasına yazmaz.
    private func queueAttributes(_ queue: String) -> [String: String] {
        guard let output = run("/usr/bin/lpoptions", ["-p", queue]) else { return [:] }
        
        var attributes: [String: String] = [:]
        var key = ""
        var value = ""
        var inValue = false
        var quote: Character?
        var escaped = false
        
        func flush() {
            if !key.isEmpty { attributes[key] = value }
            key = ""
            value = ""
            inValue = false
        }
        
        for character in output {
            if escaped {
                if inValue { value.append(character) } else { key.append(character) }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil } else { value.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == " " || character == "\n" {
                flush()
            } else if character == "=" && !inValue {
                inValue = true
            } else if inValue {
                value.append(character)
            } else {
                key.append(character)
            }
        }
        flush()
        
        return attributes
    }
    
    /// Komutu çalıştırır; başarılıysa stdout'u döndürür
    private func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            print("[PRINTER] \(path) çalıştırılamadı: \(error)")
            return nil
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Queue Status
struct PrinterQueueStatus {
    let queue: String
    let isStopped: Bool
    let isAcceptingJobs: Bool
    let stateReasons: String
    let makeAndModel: String
    let deviceURI: String
    /// Kuyrukta bitmemiş işler (ör. "Samsung_CLP_300-114")
    let pendingJobs: [String]
    /// Yerel ağda paylaşılıyor (iPhone/iPad AirPrint, diğer Mac'ler)
    let isShared: Bool
    /// Yazıcılar ve Tarayıcılar'daki adı; ağda "<ad> @ <Mac adı>" görünür
    let info: String
    
    /// USB yazıcı kapalı ya da kablo çıkmışsa CUPS "offline-report" bildirir
    var isOffline: Bool {
        stateReasons.contains("offline")
    }
    
    /// Kendi sürücümüzün ürettiği veri yalnızca CLP-300 (QPDL, -z0) içindir
    var isCLP300: Bool {
        "\(makeAndModel) \(deviceURI)".range(of: "CLP-?300", options: [.regularExpression, .caseInsensitive]) != nil
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
