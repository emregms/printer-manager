import SwiftUI

@main
struct PrinterManagerApp: App {
    /// PDF menüsünden / Finder'dan gelen "aç" istekleri
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var printManager = PrintManager()
    @StateObject private var settingsStore = SettingsStore()
    /// Ayarlar'daki "Menü çubuğunda simgeyi göster" (BackgroundSection)
    @AppStorage("showMenuBarIcon") private var showsMenuBarIcon = true
    
    init() {
        // Uygulama başlangıcında önceki temp dosyalarını temizle
        Task {
            await PDFProcessor.shared.cleanupTempFiles()
            print("[APP] Başlangıçta temp dosyaları temizlendi")
        }
    }
    
    var body: some Scene {
        // Tek pencere: gelen belge açık pencereye gider, kapalıysa yeniden açılır
        Window("PrinterManager", id: "main") {
            ContentView()
                .environmentObject(printManager)
                .environmentObject(settingsStore)
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
            // ⌘Q pencereyi kapatır, uygulama iPhone ve Mac'ten gelen belgeler için arka planda
            // sürer; tamamen çıkmak ⌥⌘Q. Oturum kapatma ve Dock'tan Çık her zaman çıkar.
            CommandGroup(replacing: .appTermination) {
                Button("Arka Planda Çalıştır") {
                    AppWindow.moveToBackground()
                }
                .keyboardShortcut("q")
                Button("PrinterManager'dan Çık") {
                    AppWindow.quit()
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
            }
        }
        
        // Arka planda çalışırken tek görünen şey; Ayarlar'dan gizlenebilir
        MenuBarExtra(isInserted: $showsMenuBarIcon) {
            MenuBarContent()
                .environmentObject(printManager)
        } label: {
            MenuBarLabel()
        }
        
        Settings {
            DriverSettingsView()
                .environmentObject(settingsStore)
        }
    }
}
