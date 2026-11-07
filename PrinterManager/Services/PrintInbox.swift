import Foundation
import AppKit
import ServiceManagement
import notify

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
    /// Yedek kontrol: bildirim kaçarsa ya da kurulu pminbox eskiyse
    private var timer: Timer?
    private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    private var isChecking = false
    /// PDF olmadığı için alınmayan işler (her kontrolde yeniden denenmesin)
    private var skippedJobs: Set<Int> = []
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// pminbox her yeni işte (ve beklerken 5 sn'de bir) bu Darwin bildirimini gönderir
    nonisolated static let notificationName = "com.samsungclp300.printermanager.incoming"
    /// Alınan işin numarası buraya yazılır; pminbox görünce başarıyla biter
    nonisolated private static let takenName = "com.samsungclp300.printermanager.taken"
    /// Durum değeri yalnızca kayıt açıkken saklanır: uygulama boyunca açık tutulur
    nonisolated private static let takenToken: Int32 = {
        var token: Int32 = NOTIFY_TOKEN_INVALID
        notify_register_check(takenName, &token)
        return token
    }()
    
    /// Kuyruk izlemeyi başlatır (birden çok çağrılabilir). Yoklama yerine pminbox'un
    /// bildirimiyle uyanır: boşta işlemci ve enerji harcamaz, App Nap'e de engel olmaz.
    /// Ekran görüntüsü modunda başlamaz: o örnek, kullanıcının gerçek işlerini almasın.
    func start() {
        guard timer == nil, !ScreenshotMode.isActive else { return }
        Self.removeOldInboxFiles()
        refreshQueues()
        
        notify_register_dispatch(Self.notificationName, &notifyToken, .main) { [weak self] _ in
            Task { @MainActor in self?.checkQueues() }
        }
        // Yedek: bildirim gelmezse (eski pminbox) iş yine en geç ~30 sn'de alınır;
        // pminbox süre dolunca işi "durduruldu" bırakır, o da alınır
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkQueues() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    
    /// İzlenecek kuyrukları (PrinterManager sürücüsüyle kurulanlar) yeniden bulur
    func refreshQueues() {
        Task {
            queues = await Task.detached { DriverInstaller.inboxQueues() }.value
            // Uygulama kapalıyken gelip bekleyen (durdurulmuş) işler hemen alınsın
            checkQueues()
        }
    }
    
    /// PDF menüsü / Birlikte Aç ile gelen dosyalar
    func open(urls: [URL], source: String = "Yazdırma penceresi / Finder") {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let copy = Self.inboxFile(title: url.deletingPathExtension().lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: copy)
                receive(IncomingDocument(url: copy, title: url.deletingPathExtension().lastPathComponent,
                                         source: source))
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
        // Arka plandaysa pencere açılır; belgeyi pencere $pending'den alır
        AppWindow.show()
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
    
    /// Gelen ilk işi alır: belgeyi indirir, işi iptal eder. iPhone'dan (AirPrint) gelen
    /// işlerin sahibi başka bir kullanıcıdır; yönetici hesabı onları da alabilir.
    nonisolated private static func takeIncomingJob(queues: [String], skipping: Set<Int>) -> TakeResult {
        for queue in queues {
            guard let jobs = CupsJobs.activeJobs(queue: queue) else { continue }
            for job in jobs where incomingStates.contains(job.state) && !skipping.contains(job.id) {
                // PrinterManager'ın kendi ham işleri (sayfalar) yazıcıya gidiyor; dokunma
                if job.format == "application/vnd.cups-raw" { continue }
                
                let file = inboxFile(title: job.title)
                guard let format = CupsJobs.fetch(id: job.id, to: file) else {
                    // Belge henüz gelmemiş olabilir: iPhone önce işi açar, belgeyi sonra
                    // gönderir. Kalıcı sayma; pminbox'un sonraki bildiriminde yeniden dene.
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    continue
                }
                guard format.contains("pdf") || isPDF(file) else {
                    try? FileManager.default.removeItem(at: file)
                    return .skipped(job.id, "PDF değil (\(format)); kuyrukta bırakıldı")
                }
                finish(job: job, queue: queue)
                let source = job.user == NSUserName() ? queue : "\(queue), \(job.user)"
                return .document(IncomingDocument(url: file, title: job.title, source: source))
            }
        }
        return .none
    }
    
    /// Belge alındı: bekleyen pminbox'a haber ver, iş "tamamlandı" olarak bitsin (iPhone'da
    /// iptal görünmesin). Filtre çalışmıyorsa (bekletilmiş/durdurulmuş iş, eski pminbox) sil.
    nonisolated private static func finish(job: CupsJobs.Job, queue: String) {
        if job.state == "processing" {
            notify_set_state(takenToken, UInt64(job.id))
            notify_post(takenName)
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.3)
                if CupsJobs.activeJobs(queue: queue)?.contains(where: { $0.id == job.id }) == false {
                    return
                }
            }
        }
        _ = CupsJobs.cancel(id: job.id)
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Oturum açılışında arka planda başla: pencere yok, Dock simgesi yok
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == kAEOpenApplication,
           event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            Task { @MainActor in AppWindow.startsHidden = true }
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            PrintInbox.shared.start()
            if !ScreenshotMode.isActive {
                AirPrintAdvertiser.shared.update()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in AppWindow.windowWillClose(window) }
        }
    }
    
    /// Pencere kapansa da uygulama menü çubuğunda sürer
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    /// Finder'dan ya da Dock'tan yeniden açılınca pencere gelsin
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in AppWindow.show() }
        }
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            PrintInbox.shared.open(urls: urls)
        }
    }
}
