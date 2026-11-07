import Foundation
import AppKit
import ServiceManagement

/// Başka uygulamalardan gelen belgeleri PrinterManager'da açar.
///
/// CLP-300'ün transfer kayışı temizleyicisi sayfalar arasında beklemeden
/// düzgün basamıyor; bu yüzden Safari gibi uygulamalardan doğrudan basılmaz:
/// - "Samsung CLP-300 (PrinterManager)" kuyruğuna gelen işte `pminbox` filtresi
///   yazıcıya veri göndermeden bekler; burası işin belgesini alır, işi iptal
///   eder ve belgeyi pencerede açar. (Kuyruğun bekletme ayarı tek başına
///   yetmiyor: macOS'un yazdırma penceresi işi kendisi serbest bırakıyor.)
///   Uygulama kapalıysa iş "durduruldu" olarak kalır ve açılınca alınır.
/// - Yazdırma penceresindeki PDF menüsü ("PrinterManager ile Yazdır") ve
///   Finder'daki "Birlikte Aç" da belgeyi buraya getirir.
/// Kullanıcı ayarları kontrol edip "Yazdır" der; baskı beklemeli ve
/// gerekiyorsa elle çift yönlü yapılır.
@MainActor
final class PrintInbox: ObservableObject {
    static let shared = PrintInbox()
    
    /// Pencerenin henüz açmadığı belge
    @Published private(set) var pending: IncomingDocument?
    
    /// Günlük buraya yazılır. Yazdırma sürerken gelen iş yine hemen alınır
    /// (pminbox USB'yi meşgul etmesin); pencere belgeyi baskı bitince açar.
    weak var printManager: PrintManager?
    
    private var queues: [String] = []
    private var timer: Timer?
    /// App Nap arka plandaki zamanlayıcıyı dakikalarca geciktirebilir
    private var activity: NSObjectProtocol?
    private var isChecking = false
    /// PDF olmadığı için alınmayan işler (her kontrolde yeniden denenmesin)
    private var skippedJobs: Set<Int> = []
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Kuyruk izlemeyi başlatır (birden çok çağrılabilir)
    func start() {
        guard timer == nil else { return }
        Self.removeOldInboxFiles()
        refreshQueues()
        // pminbox bu sırada USB'yi meşgul ediyor; çabuk alınsın. Belge genellikle
        // uygulama arkadayken (Safari'den yazdırırken) gelir.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "CLP-300 kuyruğuna gelen belgeleri izleme")
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkQueues() }
        }
        // .common: menü ya da pencere sürüklenirken de çalışsın
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    /// İzlenecek kuyrukları (PrinterManager sürücüsüyle kurulanlar) yeniden bulur
    func refreshQueues() {
        Task {
            queues = await Task.detached { DriverInstaller.inboxQueues() }.value
        }
    }
    
    /// PDF menüsü / Birlikte Aç ile gelen dosyalar
    func open(urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let copy = Self.inboxFile(title: url.deletingPathExtension().lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                receive(IncomingDocument(url: copy, title: url.deletingPathExtension().lastPathComponent,
                                         source: "Yazdırma penceresi / Finder"))
            } catch {
                printManager?.addLog("⚠️ Gelen PDF kopyalanamadı: \(error.localizedDescription)")
            }
        }
    }
    
    /// Pencere belgeyi açtı. Yalnızca aynı belgeyse temizler: arada yenisi gelmiş olabilir.
    /// $pending'i dinleyen yerden doğrudan çağırmayın: @Published değeri atamadan önce
    /// yayınlar, iç içe yapılan `nil` ataması dıştaki atamanın altında kalır.
    func markTaken(_ document: IncomingDocument) {
        if pending == document {
            pending = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func receive(_ document: IncomingDocument) {
        pending = document
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            // Pencere kapalıysa Dock simgesi zıplasın; tıklayınca açılır
            NSApp.requestUserAttention(.criticalRequest)
        }
    }
    
    private func checkQueues() {
        guard !isChecking, !queues.isEmpty, pending == nil else { return }
        
        isChecking = true
        let queues = self.queues
        let skipped = self.skippedJobs
        
        Task {
            let result = await Task.detached { Self.takeIncomingJob(queues: queues, skipping: skipped) }.value
            switch result {
            case .document(let document):
                printManager?.addLog("📥 \(document.source) kuyruğuna gelen belge alındı: \(document.title)")
                receive(document)
            case .skipped(let job, let reason):
                skippedJobs.insert(job)
                printManager?.addLog("⚠️ Kuyruktaki iş \(job) alınmadı: \(reason)")
            case .none:
                break
            }
            isChecking = false
        }
    }
    
    private enum TakeResult {
        case document(IncomingDocument)
        case skipped(Int, String)
        case none
    }
    
    /// Başka uygulamadan gelen iş durumları: pminbox bekliyor (processing),
    /// uygulama kapalıyken zaman aşımı (stopped) ya da `lp` ile bekletilmiş (held)
    nonisolated private static let incomingStates: Set<String> = ["processing", "stopped", "held"]
    
    /// Kullanıcının gelen ilk işini alır: belgeyi indirir, işi iptal eder
    nonisolated private static func takeIncomingJob(queues: [String], skipping: Set<Int>) -> TakeResult {
        let user = NSUserName()
        for queue in queues {
            guard let jobs = CupsJobs.activeJobs(queue: queue) else { continue }
            for job in jobs where incomingStates.contains(job.state) && job.user == user && !skipping.contains(job.id) {
                // PrinterManager'ın kendi ham işleri (sayfalar) yazıcıya gidiyor; dokunma
                if job.format == "application/vnd.cups-raw" { continue }
                
                let file = inboxFile(title: job.title)
                guard let format = CupsJobs.fetch(id: job.id, to: file) else {
                    return .skipped(job.id, "belge alınamadı")
                }
                guard format.contains("pdf") || isPDF(file) else {
                    try? FileManager.default.removeItem(at: file)
                    return .skipped(job.id, "PDF değil (\(format)); kuyrukta bırakıldı")
                }
                _ = CupsJobs.cancel(id: job.id)
                return .document(IncomingDocument(url: file, title: job.title, source: queue))
            }
        }
        return .none
    }
    
    nonisolated private static func isPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 5) == Data("%PDF-".utf8)
    }
    
    // MARK: - Inbox Files
    
    nonisolated private static var inboxDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PrinterManager-Inbox")
    }
    
    /// Başlıktan güvenli bir dosya adı (aynı başlıklar çakışmasın)
    nonisolated private static func inboxFile(title: String) -> URL {
        let safeTitle = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\\0"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (safeTitle.isEmpty ? "Belge" : String(safeTitle.prefix(80)))
        let directory = inboxDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name).appendingPathExtension("pdf")
    }
    
    /// 2 günden eski gelen belgeleri siler
    private static func removeOldInboxFiles() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: inboxDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-2 * 24 * 3600)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified = modified, modified < limit {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}

// MARK: - System Integration

extension PrintInbox {
    /// Her yazdırma penceresinin PDF menüsünde görünen kısayol
    static var pdfServiceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/PDF Services/PrinterManager ile Yazdır")
    }
    
    static var isPDFServiceInstalled: Bool {
        FileManager.default.fileExists(atPath: pdfServiceURL.path)
    }
    
    /// PDF menüsüne uygulamanın takma adını (alias) koyar; yönetici şifresi gerekmez
    static func installPDFService() throws {
        let directory = pdfServiceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: pdfServiceURL)
        let alias = try Bundle.main.bundleURL.bookmarkData(
            options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(alias, to: pdfServiceURL)
    }
    
    static func removePDFService() throws {
        try FileManager.default.removeItem(at: pdfServiceURL)
    }
    
    /// Oturum açılınca başlat: uygulama açık değilse kuyruğa gelen belge beklemede kalır
    static var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    static func setOpensAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Types

struct IncomingDocument: Equatable {
    /// Gelen kutusundaki kopya
    let url: URL
    let title: String
    /// Kuyruk adı ya da "Yazdırma penceresi / Finder"
    let source: String
}

/// `Contents/Helpers/cups-jobs` sarmalayıcısı (bkz. Driver/cups-jobs.c)
enum CupsJobs {
    struct Job {
        let id: Int
        /// pending, held, processing, stopped
        let state: String
        let user: String
        let format: String
        let title: String
    }
    
    static var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cups-jobs")
    }
    
    /// Kuyruktaki etkin işler; yardımcı yoksa ya da çalışmazsa nil
    static func activeJobs(queue: String) -> [Job]? {
        guard let output = run(["list", queue]) else { return nil }
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let id = Int(fields[0]) else { return nil }
            return Job(id: id, state: fields[1], user: fields[2], format: fields[3],
                       title: fields[4...].joined(separator: " "))
        }
    }
    
    /// Belgeyi dosyaya indirir; biçimini (ör. application/pdf) döndürür
    static func fetch(id: Int, to file: URL) -> String? {
        run(["fetch", String(id), file.path])?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func cancel(id: Int) -> Bool {
        run(["cancel", String(id)]) != nil
    }
    
    private static func run(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return nil }
        
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// PDF menüsü ve Finder'dan gelen "aç" isteklerini gelen kutusuna iletir
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            PrintInbox.shared.open(urls: urls)
        }
    }
}
