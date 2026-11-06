import Foundation
import SwiftUI

/// Kullanıcı ayarlarını yöneten store
class SettingsStore: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedPrinter: String? {
        didSet { save() }
    }
    
    @Published var printDelaySeconds: Int = 30 {
        didSet { save() }
    }
    
    @Published var cleanDelaySeconds: Int = 8 {
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
        
        let savedPrintDelay = defaults.integer(forKey: Keys.printDelaySeconds)
        printDelaySeconds = savedPrintDelay > 0 ? savedPrintDelay : 30
        
        let savedCleanDelay = defaults.integer(forKey: Keys.cleanDelaySeconds)
        cleanDelaySeconds = savedCleanDelay > 0 ? savedCleanDelay : 8
        
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
        defaults.set(printDelaySeconds, forKey: Keys.printDelaySeconds)
        defaults.set(cleanDelaySeconds, forKey: Keys.cleanDelaySeconds)
        defaults.set(duplexEnabled, forKey: Keys.duplexEnabled)
        defaults.set(grayscaleMode, forKey: Keys.grayscaleMode)
        defaults.set(driverMode.rawValue, forKey: Keys.driverMode)
        defaults.set(qpdlResolution.rawValue, forKey: Keys.qpdlResolution)
        defaults.set(ghostscriptPath, forKey: Keys.ghostscriptPath)
        defaults.set(foo2qpdlPath, forKey: Keys.foo2qpdlPath)
        defaults.set(rawQueueName, forKey: Keys.rawQueueName)
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
