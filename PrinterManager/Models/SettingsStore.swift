import Foundation
import SwiftUI

/// Kullanıcı ayarlarını yöneten store
class SettingsStore: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedPrinter: String? {
        didSet { save() }
    }
    
    /// Sayfalar arası: yazıcının durumuna göre (akıllı) ya da sabit süre
    @Published var pageTimingMode: PageTimingMode = .smart {
        didSet { save() }
    }
    
    /// Sabit modda sayfalar arası bekleme (baskı + kayış temizliği). Akıllı modda
    /// yazıcı durumu okunamazsa yedek olarak kullanılır.
    @Published var pageWaitSeconds: Int = 38 {
        didSet { save() }
    }
    
    @Published var duplexEnabled: Bool = false {
        didSet { save() }
    }
    
    @Published var grayscaleMode: Bool = false {
        didSet { save() }
    }
    
    @Published var driverMode: DriverMode = .own {
        didSet { save() }
    }
    
    @Published var qpdlResolution: QPDLResolution = .dpi1200x600 {
        didSet { save() }
    }
    
    /// Boşsa otomatik bulunur (Homebrew / MacPorts)
    @Published var ghostscriptPath: String = "" {
        didSet { save() }
    }
    
    /// Boşsa uygulama paketindeki kullanılır
    @Published var foo2qpdlPath: String = "" {
        didSet { save() }
    }
    
    /// Ham gönderim kuyruğu; boşsa seçili yazıcının kuyruğu
    @Published var rawQueueName: String = "" {
        didSet { save() }
    }
    
    /// Yazdırma başlarken PrintManager'a verilen sürücü ayarları
    var driverSettings: DriverSettings {
        DriverSettings(
            mode: driverMode,
            resolution: qpdlResolution,
            ghostscriptPath: ghostscriptPath,
            foo2qpdlPath: foo2qpdlPath,
            rawQueueName: rawQueueName
        )
    }
    
    // MARK: - Private Properties
    private let defaults = UserDefaults.standard
    
    /// load() sırasında didSet → save() henüz okunmamış ayarların üzerine
    /// varsayılanları yazmasın
    private var isLoading = false
    
    private enum Keys {
        static let selectedPrinter = "selectedPrinter"
        static let printDelaySeconds = "printDelaySeconds"
        static let cleanDelaySeconds = "cleanDelaySeconds"
        static let pageTimingMode = "pageTimingMode"
        static let pageWaitSeconds = "pageWaitSeconds"
        static let duplexEnabled = "duplexEnabled"
        static let grayscaleMode = "grayscaleMode"
        static let driverMode = "driverMode"
        static let qpdlResolution = "qpdlResolution"
        static let ghostscriptPath = "ghostscriptPath"
        static let foo2qpdlPath = "foo2qpdlPath"
        static let rawQueueName = "rawQueueName"
    }
    
    // MARK: - Initialization
    
    init() {
        load()
    }
    
    // MARK: - Private Methods
    
    private func load() {
        isLoading = true
        defer { isLoading = false }
        
        selectedPrinter = defaults.string(forKey: Keys.selectedPrinter)
        
        pageTimingMode = defaults.string(forKey: Keys.pageTimingMode).flatMap(PageTimingMode.init(rawValue:)) ?? .smart
        
        // Eski iki ayardan (yazdırma + temizlik süresi) tek bekleme süresine geçiş
        if let saved = defaults.object(forKey: Keys.pageWaitSeconds) as? Int, saved > 0 {
            pageWaitSeconds = saved
        } else {
            let print = defaults.integer(forKey: Keys.printDelaySeconds)
            let clean = defaults.integer(forKey: Keys.cleanDelaySeconds)
            pageWaitSeconds = print + clean > 0 ? print + clean : 38
        }
        
        duplexEnabled = defaults.bool(forKey: Keys.duplexEnabled)
        grayscaleMode = defaults.bool(forKey: Keys.grayscaleMode)
        
        driverMode = defaults.string(forKey: Keys.driverMode).flatMap(DriverMode.init(rawValue:)) ?? .own
        qpdlResolution = defaults.string(forKey: Keys.qpdlResolution).flatMap(QPDLResolution.init(rawValue:)) ?? .dpi1200x600
        ghostscriptPath = defaults.string(forKey: Keys.ghostscriptPath) ?? ""
        foo2qpdlPath = defaults.string(forKey: Keys.foo2qpdlPath) ?? ""
        rawQueueName = defaults.string(forKey: Keys.rawQueueName) ?? ""
    }
    
    private func save() {
        guard !isLoading else { return }
        
        defaults.set(selectedPrinter, forKey: Keys.selectedPrinter)
        defaults.set(pageTimingMode.rawValue, forKey: Keys.pageTimingMode)
        defaults.set(pageWaitSeconds, forKey: Keys.pageWaitSeconds)
        defaults.set(duplexEnabled, forKey: Keys.duplexEnabled)
        defaults.set(grayscaleMode, forKey: Keys.grayscaleMode)
        defaults.set(driverMode.rawValue, forKey: Keys.driverMode)
        defaults.set(qpdlResolution.rawValue, forKey: Keys.qpdlResolution)
        defaults.set(ghostscriptPath, forKey: Keys.ghostscriptPath)
        defaults.set(foo2qpdlPath, forKey: Keys.foo2qpdlPath)
        defaults.set(rawQueueName, forKey: Keys.rawQueueName)
    }
}

// MARK: - Page Timing

/// Sayfalar arasında ne kadar beklenir
enum PageTimingMode: String, CaseIterable, Identifiable {
    /// Yazıcı sayfayı basıp kayışı temizledikten sonra "Hazır" olunca
    case smart
    /// Kullanıcının verdiği sabit yazdırma + temizlik süresi (yedek)
    case fixed
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .smart: return "Akıllı"
        case .fixed: return "Sabit süre"
        }
    }
}

// MARK: - Driver Settings

/// Sayfaların yazıcıya hangi yoldan gideceği
enum DriverMode: String, CaseIterable, Identifiable {
    /// Ghostscript + foo2qpdl, ham gönderim
    case own
    /// macOS'taki CUPS sürücüsü (eski yol, yedek)
    case system
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .own: return "Kendi sürücü (önerilen)"
        case .system: return "Sistem sürücüsü"
        }
    }
}

struct DriverSettings {
    let mode: DriverMode
    let resolution: QPDLResolution
    let ghostscriptPath: String
    let foo2qpdlPath: String
    let rawQueueName: String
}
