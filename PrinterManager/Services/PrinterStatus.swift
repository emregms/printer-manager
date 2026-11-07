import Foundation
import SwiftUI

/// CLP-300'ün anlık durumu ve toner seviyeleri.
///
/// `Contents/Helpers/clp300-status` USB'den 8 baytlık durum kodunu okur
/// (bkz. Driver/clp300-status.c). Kod, yazıcının kendi durum tablosuyla
/// (SM.xml; maske + kod + açıklama) çözülür; tablo yazıcıdan bir kez indirilip
/// önbelleğe alınır.
struct PrinterStatus: Equatable {
    enum Severity: Int, Comparable {
        case ok, warning, error
        
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    
    let code: [UInt8]
    let severity: Severity
    /// Tablodaki eleman adı (ör. "WasteTankFull"); tanınmayan kodda nil
    let key: String?
    let title: String
    /// Ne yapmalı
    let advice: String?
    /// Yazıcının tablosundaki İngilizce metin
    let printerText: String?
    let toners: [Toner]
    /// Tablo bu durumda toner seviyesinin gösterilmemesini istiyor (ör. kapak açık)
    let showsToners: Bool
    /// IEEE 1284 kimliğindeki STATUS (IDLE, BUSY...)
    let deviceState: String?
    let paperEmpty: Bool
    let firmware: String?
    let date: Date
    
    /// Yazdırmayı fiilen durduran hatalar. Atık toner kabı dolu uyarısında bu
    /// yazıcı basmaya devam ediyor (2026-11-07'de 44 sayfa basıldı).
    var blocksPrinting: Bool {
        guard severity == .error, let key = key else { return false }
        return !["WasteTankFull", "UsbCableOff", "NetworkCableOff"].contains(key)
    }
    
    var codeText: String {
        code.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

struct Toner: Identifiable, Equatable {
    enum Color: String, CaseIterable {
        case cyan = "C", magenta = "M", yellow = "Y", black = "K"
        
        var name: String {
            switch self {
            case .cyan: return "Camgöbeği"
            case .magenta: return "Macenta"
            case .yellow: return "Sarı"
            case .black: return "Siyah"
            }
        }
        
        var swatch: SwiftUI.Color {
            switch self {
            case .cyan: return SwiftUI.Color(red: 0.0, green: 0.68, blue: 0.94)
            case .magenta: return SwiftUI.Color(red: 0.93, green: 0.0, blue: 0.55)
            case .yellow: return SwiftUI.Color(red: 1.0, green: 0.80, blue: 0.0)
            case .black: return SwiftUI.Color(white: 0.2)
            }
        }
    }
    
    let color: Color
    /// 0-100; yazıcı bildirmiyorsa nil
    let percent: Int?
    /// Kartuş numarası (ör. CLP-M300A)
    let partNumber: String?
    
    var id: String { color.rawValue }
    var isLow: Bool { (percent ?? 100) <= 10 }
}

// MARK: - Reader

enum PrinterStatusReader {
    enum ReadError: LocalizedError {
        case helperMissing
        case notConnected
        case failed(String)
        
        var errorDescription: String? {
            switch self {
            case .helperMissing: return "Durum aracı (clp300-status) uygulama paketinde yok"
            case .notConnected: return "CLP-300 USB'de bulunamadı. Yazıcı açık ve bağlı mı?"
            case .failed(let message): return "Durum okunamadı: \(message)"
            }
        }
    }
    
    static var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/clp300-status")
    }
    
    /// Durumu okur (~50 ms; tablo ilk kez indirilirken ~1 sn). Ana iş parçacığında çağırmayın.
    static func read() throws -> PrinterStatus {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw ReadError.helperMissing
        }
        let output = try run(["status"])
        
        var code: [UInt8] = []
        var deviceID: String?
        var port: UInt8?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("code:") {
                code = line.dropFirst(5).split(separator: " ").compactMap { UInt8($0, radix: 16) }
            } else if line.hasPrefix("deviceid:") {
                deviceID = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("port:") {
                port = UInt8(line.dropFirst(5).trimmingCharacters(in: .whitespaces), radix: 16)
            }
        }
        guard code.count == 8 else {
            throw ReadError.failed("beklenmeyen yanıt")
        }
        
        let table = try? StatusTable.load()
        return decode(code: code, deviceID: deviceID, port: port, table: table)
    }
    
    static func decode(code: [UInt8], deviceID: String?, port: UInt8?, table: StatusTable?) -> PrinterStatus {
        let entry = table?.match(code)
        let severity: PrinterStatus.Severity
        switch code[0] {
        case 0x04: severity = .error
        case 0x02: severity = .warning
        default: severity = .ok
        }
        
        let text = entry.flatMap { StatusText.turkish[$0.name] }
        let partNumbers = table?.partNumbers ?? [:]
        
        // Bayt 4-7: siyah, camgöbeği, macenta, sarı (işaretli; ff = bilinmiyor)
        let order: [Toner.Color] = [.black, .cyan, .magenta, .yellow]
        let levels = Dictionary(uniqueKeysWithValues: order.enumerated().map { index, color -> (Toner.Color, Int?) in
            let value = Int(Int8(bitPattern: code[4 + index]))
            return (color, (0...100).contains(value) ? value : nil)
        })
        let toners = Toner.Color.allCases.map { color in
            Toner(color: color, percent: levels[color] ?? nil, partNumber: partNumbers[color])
        }
        
        let deviceState = deviceID?
            .split(separator: ";")
            .first(where: { $0.hasPrefix("STATUS:") })
            .map { String($0.dropFirst(7)) }
        
        return PrinterStatus(
            code: code,
            severity: severity,
            key: entry?.name,
            title: text?.title ?? entry?.text ?? "Bilinmeyen durum",
            advice: text?.advice(partNumbers),
            printerText: entry?.text,
            toners: toners,
            showsToners: entry?.showsTonerLevel ?? true,
            deviceState: deviceState,
            paperEmpty: (port ?? 0) & 0x20 != 0,
            firmware: table?.firmware,
            date: Date()
        )
    }
    
    fileprivate static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errors = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        switch process.terminationStatus {
        case 0:
            return String(data: output, encoding: .utf8) ?? ""
        case 3:
            throw ReadError.notConnected
        default:
            let message = String(data: errors, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ReadError.failed(message.isEmpty ? "kod \(process.terminationStatus)" : message)
        }
    }
}

// MARK: - Status Table (SM.xml)

/// Yazıcının kendi durum tablosu: `<Status>` altında her durum bir eleman,
/// içinde `<Mask>` ve `<Status>` ([04][08][17]... biçiminde 8 bayt).
struct StatusTable {
    struct Entry {
        let name: String
        let text: String
        let mask: [UInt8]
        let status: [UInt8]
        let showsTonerLevel: Bool
    }
    
    let entries: [Entry]
    let partNumbers: [Toner.Color: String]
    let firmware: String?
    
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrinterManager/clp300-status-table.xml")
    }
    
    private static var cached: StatusTable?
    private static let lock = NSLock()
    
    /// Önbellekten; yoksa yazıcıdan indirir
    static func load() throws -> StatusTable {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cached {
            return cached
        }
        
        let url = cacheURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try PrinterStatusReader.run(["xml", url.path])
        }
        let table = try parse(Data(contentsOf: url))
        cached = table
        return table
    }
    
    static func parse(_ data: Data) throws -> StatusTable {
        let document = try XMLDocument(data: data)
        
        func bytes(_ text: String?) -> [UInt8] {
            guard let text = text else { return [] }
            return text.split(separator: "]").compactMap { part in
                part.split(separator: "[").last.flatMap { UInt8($0, radix: 16) }
            }
        }
        
        let statusNodes = (try? document.nodes(forXPath: "/StatusMonitorInfo/Status/*")) ?? []
        let entries = statusNodes.compactMap { node -> Entry? in
            guard let element = node as? XMLElement, let name = element.name else { return nil }
            let status = bytes(element.elements(forName: "Status").first?.stringValue)
            guard status.count == 8 else { return nil }
            return Entry(
                name: name,
                text: element.attribute(forName: "STRING")?.stringValue ?? name,
                mask: bytes(element.elements(forName: "Mask").first?.stringValue),
                status: status,
                showsTonerLevel: element.attribute(forName: "SHOWTONERLEVEL")?.stringValue?.uppercased() != "FALSE"
            )
        }
        
        var partNumbers: [Toner.Color: String] = [:]
        if let order = (try? document.nodes(forXPath: "//TonerOrder"))?.first as? XMLElement {
            for color in Toner.Color.allCases {
                if let part = order.attribute(forName: "Toner\(color.rawValue)")?.stringValue, !part.isEmpty {
                    partNumbers[color] = part
                }
            }
        }
        
        let about = (try? document.nodes(forXPath: "//About"))?.first as? XMLElement
        return StatusTable(
            entries: entries,
            partNumbers: partNumbers,
            firmware: about?.attribute(forName: "OSVERSION")?.stringValue
        )
    }
    
    /// Koda uyan en belirgin giriş: (kod & maske) == (durum & maske); birden çok
    /// uyarsa maskesi en dar olan. Maskesiz girişlerde bayt 1-3 birebir karşılaştırılır.
    func match(_ code: [UInt8]) -> Entry? {
        var best: (entry: Entry, bits: Int)?
        for entry in entries {
            let mask = entry.mask.count == 8 ? entry.mask : [0x00, 0xff, 0xff, 0xff, 0, 0, 0, 0]
            let matches = (0..<8).allSatisfy { (code[$0] & mask[$0]) == (entry.status[$0] & mask[$0]) }
            guard matches else { continue }
            let bits = mask.reduce(0) { $0 + $1.nonzeroBitCount }
            if best == nil || bits > best!.bits {
                best = (entry, bits)
            }
        }
        return best?.entry
    }
}

// MARK: - Turkish Texts

/// Tablodaki durumların Türkçesi ve yapılacaklar. Anahtar: SM.xml eleman adı.
enum StatusText {
    struct Text {
        let title: String
        let advice: ([Toner.Color: String]) -> String?
    }
    
    static let wasteTonerPart = "CLP-W300A"
    static let imagingUnitPart = "CLP-R300A"
    
    static let turkish: [String: Text] = {
        var texts: [String: Text] = [:]
        
        func add(_ key: String, _ title: String, _ advice: String? = nil) {
            texts[key] = Text(title: title, advice: { _ in advice })
        }
        
        add("UsbCableOff", "USB bağlantısı yok", "Yazıcının açık ve USB kablosunun takılı olduğundan emin olun.")
        add("NetworkCableOff", "Ağ bağlantısı yok")
        add("Ready", "Hazır")
        add("PowerSave", "Güç tasarrufu modunda", "İş gelince kendiliğinden uyanır.")
        add("Printing", "Yazdırıyor")
        add("Warmingup", "Isınıyor / toner dağıtılıyor", "Birkaç saniye bekleyin.")
        add("JobReset", "İş sıfırlanıyor")
        add("PaperJam0Tray1", "Kağıt sıkışması: tepsi 1", "Tepsiyi çekip sıkışan kağıdı çıkarın.")
        add("InsideJam", "Kağıt sıkışması: yazıcının içinde", "Kapağı açıp sıkışan kağıdı yavaşça çekerek çıkarın.")
        add("ExitAreaJam", "Kağıt sıkışması: çıkış bölümü", "Kağıdı çıkış bölümünden yavaşça çekerek çıkarın.")
        add("FirstPaperEmpty", "Tepsi 1'de kağıt yok", "Tepsiye A4 kağıt yükleyin.")
        add("ManualEmpty", "Elle besleme yuvasında kağıt yok", "Elle besleme yuvasına kağıt koyun.")
        add("FirstPaperMismatch", "Tepsi 1'deki kağıt uyuşmuyor", "Tepsideki kağıdın A4 olduğundan emin olun.")
        add("ManualMismatch", "Elle beslemedeki kağıt uyuşmuyor", "Yuvadaki kağıdın A4 olduğundan emin olun.")
        add("ManualLoad", "Elle besleme bekleniyor", "Kağıdı yerleştirip yazıcıdaki Durdur düğmesine basın.")
        add("ReplaceTransBelt", "Transfer kayışını değiştirin")
        add("ReplaceTransSoon", "Transfer kayışının ömrü bitmek üzere")
        add("ReplaceFuser", "Isıtıcı ünitesini (fuser) değiştirin")
        add("ReplaceFuserSoon", "Isıtıcı ünitesinin ömrü bitmek üzere")
        add("ReplaceImageUnit", "Görüntüleme ünitesini değiştirin", "Yeni görüntüleme ünitesi: \(imagingUnitPart).")
        add("ReplaceImageSoon", "Görüntüleme ünitesinin ömrü bitmek üzere", "Yedek görüntüleme ünitesi: \(imagingUnitPart).")
        add("ReplaceTransferRoller", "Transfer silindirini değiştirin")
        add("ReplaceTransferRollerSoon", "Transfer silindirinin ömrü bitmek üzere")
        add("FuserHighError", "Isıtıcı aşırı ısındı", "Yazıcıyı kapatıp 30 dakika soğumasını bekleyin; sürerse servis gerekir.")
        add("FuserLowError", "Isıtıcı yeterince ısınmıyor", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        add("LSUError", "Lazer tarama ünitesi (LSU) hatası", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        add("LSUHsyncError", "Lazer tarama ünitesi (LSU) hatası", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        add("LSUMotorError", "Lazer tarama ünitesi (LSU) motor hatası", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        add("CoverOpen", "Kapak açık", "Kapağı tam olarak kapatın.")
        add("HighTemperature", "Yüksek sıcaklık hatası", "Yazıcıyı kapatıp soğumasını bekleyin.")
        add("MotorError", "Ana motor kilitlendi", "Yazıcıyı kapatıp açın; içeride sıkışma olup olmadığına bakın.")
        add("ADCConfirmErr", "Toner yoğunluk sensörü (ADC) hatası", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        add("WasteTankFull", "Atık toner kabı dolu", """
            Atık toner kabını (\(wasteTonerPart)) değiştirin. Kap doluyken kayıştan \
            temizlenen toner atılamaz; baskılardaki lekelerin ve sayfa arası bekleme \
            ihtiyacının nedeni bu olabilir.
            """)
        add("ITBError", "Transfer kayışı hatası", "Kayışın doğru takıldığından emin olun; sürerse servis gerekir.")
        add("OPCEmpty", "Görüntüleme ünitesi takılı değil", "Görüntüleme ünitesini (\(imagingUnitPart)) takın.")
        add("OPCInvalid", "Geçersiz görüntüleme ünitesi", "CLP-300 için olan bir görüntüleme ünitesi takın.")
        add("ReplaceTray1Roller", "Tepsi 1 alma silindirini değiştirin")
        add("IPConflict", "IP adresi çakışması")
        add("DEVError", "Develop ünitesi konum hatası", "Yazıcıyı kapatıp açın; sürerse servis gerekir.")
        
        // Renk başına tekrarlanan durumlar
        let colors: [(name: String, letter: String, color: Toner.Color)] = [
            ("Yellow", "Y", .yellow), ("Magenta", "M", .magenta), ("Cyan", "C", .cyan), ("Black", "K", .black),
        ]
        for (name, letter, color) in colors {
            let colorName = color.name
            func part(_ parts: [Toner.Color: String]) -> String {
                parts[color].map { " (\($0))" } ?? ""
            }
            texts["\(name)TonerLow"] = Text(title: "\(colorName) toner azaldı") { parts in
                "Yedek kartuş\(part(parts)) alın; bir süre daha basabilirsiniz."
            }
            texts["\(name)TonerReplace"] = Text(title: "\(colorName) toner kartuşunu değiştirin") { parts in
                "Yeni kartuş\(part(parts)) takın."
            }
            texts["\(name)TonerEmpty"] = Text(title: "\(colorName) toner bitti") { parts in
                "Yeni kartuş\(part(parts)) takıp yeniden yazdırın."
            }
            texts["\(name)TonerSupplyError"] = Text(title: "\(colorName) toner besleme hatası") { _ in
                "Kartuşu çıkarıp yeniden takın."
            }
            texts["InvalidTonerKit\(letter)"] = Text(title: "Geçersiz \(colorName.lowercased(with: Locale(identifier: "tr"))) toner kartuşu") { parts in
                "CLP-300 için olan bir kartuş\(part(parts)) takın."
            }
            texts["RefilledTonerKit\(letter)"] = Text(title: "\(colorName) kartuş dolum kartuş olarak algılandı") { _ in
                "Toner seviyesi doğru gösterilmeyebilir."
            }
            texts["TonerKitNotInst\(letter)"] = Text(title: "\(colorName) toner kartuşu takılı değil") { parts in
                "Kartuşu\(part(parts)) yerine oturtun."
            }
        }
        return texts
    }()
}

// MARK: - Monitor

/// Durum kartı için: belirli aralıklarla okur
@MainActor
final class PrinterStatusMonitor: ObservableObject {
    static let shared = PrinterStatusMonitor()
    
    @Published private(set) var status: PrinterStatus?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    
    private var timer: Timer?
    
    private init() {}
    
    /// 10 sn'de bir okur (birden çok çağrılabilir)
    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = await Task.detached { () -> Result<PrinterStatus, Error> in
                Result { try PrinterStatusReader.read() }
            }.value
            switch result {
            case .success(let status):
                self.status = status
                errorMessage = nil
            case .failure(let error):
                status = nil
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
