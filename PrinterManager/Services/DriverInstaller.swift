import Foundation

/// CLP-300'ü Yazıcılar ve Tarayıcılar'a "PrinterManager" kuyruğu olarak ekler.
/// Başka uygulamalardan bu yazıcıya gönderilen belgeler basılmadan bekletilir
/// ve PrintInbox tarafından PrinterManager'da açılır (sayfa arası bekleme ve
/// elle çift yön için). PrinterManager'ın kendi ham işleri aynı kuyruktan
/// beklemeden geçer. Samsung'un eski sürücüsüne gerek kalmaz.
///
/// Kurulum `Driver/install-driver.sh` ile root olarak yapılır; yetki macOS'un
/// yönetici şifresi penceresiyle istenir.
enum DriverInstaller {
    static let installDirectory = "/Library/Printers/PrinterManager"
    static let filterPath = installDirectory + "/Filters/pminbox"
    
    /// Bizim PPD'nin NickName'i bunu içerir (printer-make-and-model)
    private static let modelMarker = "PrinterManager"
    
    // MARK: - Status
    
    struct Status {
        /// Filtre dosyaları /Library/Printers altında mı
        let isDriverInstalled: Bool
        /// Kurulu pminbox uygulamanınkiyle aynı mı (değilse "Sürücüyü Güncelle")
        let isDriverUpToDate: Bool
        /// Bizim sürücüyü kullanan kuyruklar
        let queues: [String]
        /// USB'de bulunan CLP-300'ler
        let deviceURIs: [String]
    }
    
    /// Kuyrukları ve USB'yi sorgular (~1 sn); ana iş parçacığında çağırmayın
    static func currentStatus() -> Status {
        Status(
            isDriverInstalled: FileManager.default.isExecutableFile(atPath: filterPath),
            isDriverUpToDate: isFilterUpToDate,
            queues: inboxQueues(),
            deviceURIs: PrinterService.shared.connectedCLP300DeviceURIs()
        )
    }
    
    /// Kurulu filtre, uygulama paketindekiyle aynı mı
    static var isFilterUpToDate: Bool {
        guard let bundled = Bundle.main.url(forResource: "pminbox", withExtension: nil) else { return true }
        return FileManager.default.contentsEqual(atPath: bundled.path, andPath: filterPath)
    }
    
    /// Bizim PPD ile kurulmuş kuyruklar (gelen işleri bekleten); ana iş parçacığında çağırmayın
    static func inboxQueues() -> [String] {
        let service = PrinterService.shared
        return service.allQueues().filter { queue in
            service.queueStatus(queue)?.makeAndModel.contains(modelMarker) == true
        }
    }
    
    /// Yeni kuyruğun adı: varsa bizimkini güncelle; "Samsung_CLP_300" başka bir
    /// sürücüyle (ör. Samsung'un) kuruluysa ona dokunma, yanına ekle
    static func suggestedQueue(status: Status) -> (name: String, description: String) {
        if let existing = status.queues.first {
            let description = existing.hasSuffix("_PM") ? "Samsung CLP-300 (PrinterManager)" : "Samsung CLP-300"
            return (existing, description)
        }
        if PrinterService.shared.allQueues().contains("Samsung_CLP_300") {
            return ("Samsung_CLP_300_PM", "Samsung CLP-300 (PrinterManager)")
        }
        return ("Samsung_CLP_300", "Samsung CLP-300")
    }
    
    // MARK: - Install / Uninstall
    
    static func install(deviceURI: String, queue: String, description: String) throws -> String {
        guard let resources = Bundle.main.resourceURL else {
            throw DriverInstallerError.missingResource("Resources")
        }
        for name in ["install-driver.sh", "pminbox", "Samsung-CLP-300-PrinterManager.ppd"] {
            guard FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path) else {
                throw DriverInstallerError.missingResource(name)
            }
        }
        // Gelen işleri alacak yardımcı yoksa kuyruk işleri sonsuza dek bekletir
        guard FileManager.default.isExecutableFile(atPath: CupsJobs.helper.path) else {
            throw DriverInstallerError.missingResource("cups-jobs")
        }
        
        return try runPrivileged([
            "/bin/sh", resources.appendingPathComponent("install-driver.sh").path,
            "install", resources.path, queue, deviceURI, description,
        ])
    }
    
    /// Kuyruğu yerel ağda paylaşır ya da paylaşımı kapatır (iPhone/iPad AirPrint)
    static func setShared(_ shared: Bool, queue: String) throws -> String {
        guard let script = Bundle.main.url(forResource: "install-driver", withExtension: "sh") else {
            throw DriverInstallerError.missingResource("install-driver.sh")
        }
        return try runPrivileged(["/bin/sh", script.path, "share", queue, shared ? "on" : "off"])
    }
    
    static func uninstall(queues: [String]) throws -> String {
        guard let script = Bundle.main.url(forResource: "install-driver", withExtension: "sh") else {
            throw DriverInstallerError.missingResource("install-driver.sh")
        }
        return try runPrivileged(["/bin/sh", script.path, "uninstall"] + queues)
    }
    
    // MARK: - Private Methods
    
    /// Komutu yönetici yetkisiyle çalıştırır; şifreyi macOS'un kendi penceresi ister
    private static func runPrivileged(_ arguments: [String]) throws -> String {
        let command = arguments.map(shellQuote).joined(separator: " ")
        let source = "do shell script \"\(appleScriptEscape(command))\" with administrator privileges"
        
        guard let script = NSAppleScript(source: source) else {
            throw DriverInstallerError.failed("AppleScript oluşturulamadı")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        
        if let errorInfo = errorInfo {
            // -128: kullanıcı şifre penceresinde Vazgeç dedi
            if errorInfo[NSAppleScript.errorNumber] as? Int == -128 {
                throw DriverInstallerError.cancelled
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Bilinmeyen hata"
            throw DriverInstallerError.failed(message)
        }
        return result.stringValue ?? ""
    }
    
    private static func shellQuote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    
    private static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Errors
enum DriverInstallerError: LocalizedError {
    case missingResource(String)
    case cancelled
    case failed(String)
    
    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Uygulama paketinde \(name) bulunamadı. Uygulamayı yeniden kurun."
        case .cancelled:
            return "Şifre penceresinde vazgeçildi; hiçbir şey değişmedi."
        case .failed(let message):
            return "Kurulum başarısız: \(message)"
        }
    }
}
