import SwiftUI

@main
struct PrinterManagerApp: App {
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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
