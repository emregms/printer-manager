import SwiftUI

@main
struct PrinterManagerApp: App {
    /// PDF menüsünden / Finder'dan gelen "aç" istekleri
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var printManager = PrintManager()
    @StateObject private var settingsStore = SettingsStore()
    
    init() {
        // Uygulama başlangıcında önceki temp dosyalarını temizle
        Task {
            await PDFProcessor.shared.cleanupTempFiles()
            print("[APP] Başlangıçta temp dosyaları temizlendi")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(printManager)
                .environmentObject(settingsStore)
                // Gelen belge açık pencereye gitsin, her seferinde yeni pencere açılmasın
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Kurulum Yardımcısı…") {
                    NotificationCenter.default.post(name: SetupAssistantView.showNotification, object: nil)
                }
            }
        }
        
        Settings {
            DriverSettingsView()
                .environmentObject(settingsStore)
        }
    }
}
