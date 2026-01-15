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
    
    // MARK: - Private Properties
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let selectedPrinter = "selectedPrinter"
        static let printDelaySeconds = "printDelaySeconds"
        static let cleanDelaySeconds = "cleanDelaySeconds"
        static let duplexEnabled = "duplexEnabled"
        static let grayscaleMode = "grayscaleMode"
    }
    
    // MARK: - Initialization
    
    init() {
        load()
    }
    
    // MARK: - Private Methods
    
    private func load() {
        selectedPrinter = defaults.string(forKey: Keys.selectedPrinter)
        
        let savedPrintDelay = defaults.integer(forKey: Keys.printDelaySeconds)
        printDelaySeconds = savedPrintDelay > 0 ? savedPrintDelay : 30
        
        let savedCleanDelay = defaults.integer(forKey: Keys.cleanDelaySeconds)
        cleanDelaySeconds = savedCleanDelay > 0 ? savedCleanDelay : 8
        
        duplexEnabled = defaults.bool(forKey: Keys.duplexEnabled)
        grayscaleMode = defaults.bool(forKey: Keys.grayscaleMode)
    }
    
    private func save() {
        defaults.set(selectedPrinter, forKey: Keys.selectedPrinter)
        defaults.set(printDelaySeconds, forKey: Keys.printDelaySeconds)
        defaults.set(cleanDelaySeconds, forKey: Keys.cleanDelaySeconds)
        defaults.set(duplexEnabled, forKey: Keys.duplexEnabled)
        defaults.set(grayscaleMode, forKey: Keys.grayscaleMode)
    }
}
