import AppKit
import SwiftUI

/// README ekran görüntüleri (bkz. Scripts/screenshots.sh). Debug derlemesi şöyle açılır:
///   PrinterManager -PMScreenshots <klasör> [-PMSamplePDF <pdf>] [-PMAppearance light]
/// Uygulama kendi pencerelerini PNG olarak çizer (ekran kaydı izni gerekmez), örnek bir
/// baskı sırası gösterir ve kapanır. Yazıcıya hiçbir şey gönderilmez. Release'te kapalı.
enum ScreenshotMode {
    static var isActive: Bool {
        #if DEBUG
        return directory != nil
        #else
        return false
        #endif
    }
    
    /// Görüntülerde yazıcının seri numarası ve geçici derleme klasörü görünmesin
    static func masked(_ text: String) -> String {
        guard isActive else { return text }
        return text
            .replacingOccurrences(of: #"serial=[^&\s]+"#, with: "serial=…", options: .regularExpression)
            .replacingOccurrences(of: Bundle.main.bundlePath, with: "/Applications/PrinterManager.app")
    }
    
    private static var directory: URL? {
        UserDefaults.standard.string(forKey: "PMScreenshots").map { URL(fileURLWithPath: $0) }
    }
    
    #if DEBUG
    /// Sırayla: ana pencere, baskı sırası, kurulum yardımcısı, Ayarlar
    @MainActor
    static func run(
        printManager: PrintManager,
        settingsStore: SettingsStore,
        open: (URL) -> Void,
        showSetup: (Bool) -> Void
    ) async {
        guard let directory = directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let light = UserDefaults.standard.string(forKey: "PMAppearance") == "light"
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        
        // Önerilen ayarlarla göster; kullanıcının ayarları sonunda geri yazılır
        let saved = (settingsStore.duplexEnabled, settingsStore.photoMode, settingsStore.qpdlResolution, settingsStore.grayscaleMode)
        settingsStore.duplexEnabled = true
        settingsStore.photoMode = true
        settingsStore.qpdlResolution = .dpi1200x600
        settingsStore.grayscaleMode = false
        
        await pause(1)
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        window.setContentSize(NSSize(width: 1180, height: 900))
        window.center()
        // Etkin pencere: düğmeler vurgu renginde çizilsin
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        if let pdf = UserDefaults.standard.string(forKey: "PMSamplePDF") {
            open(URL(fileURLWithPath: pdf))
        }
        await pause(4)
        capture(window, to: directory.appendingPathComponent("main.png"))
        
        printManager.showDemoQueue()
        PrinterStatusMonitor.shared.showDemo(code: [0x09, 0x01, 0x04])
        await pause(2)
        capture(window, to: directory.appendingPathComponent("printing.png"))
        printManager.endDemo()
        PrinterStatusMonitor.shared.endDemo()
        
        showSetup(true)
        await pause(6)  // sürücü durumu (lpinfo) birkaç saniye sürer
        if let sheet = window.attachedSheet {
            capture(sheet, to: directory.appendingPathComponent("setup.png"))
        }
        showSetup(false)
        await pause(1)
        
        // Ayarlar sahnesi macOS 14'ten beri seçiciyle açılmıyor; aynı görünüm ayrı pencerede
        let settings = NSWindow(contentViewController: NSHostingController(
            rootView: DriverSettingsView().environmentObject(settingsStore)
        ))
        settings.title = "PrinterManager Ayarları"
        settings.styleMask = [.titled, .closable]
        settings.setContentSize(NSSize(width: 520, height: 1070))
        settings.makeKeyAndOrderFront(nil)
        await pause(7)  // güç tasarrufu ayarı yazıcıdan okunur
        capture(settings, to: directory.appendingPathComponent("settings.png"))
        settings.close()
        
        (settingsStore.duplexEnabled, settingsStore.photoMode, settingsStore.qpdlResolution, settingsStore.grayscaleMode) = saved
        NSApp.terminate(nil)
    }
    
    /// Pencereyi başlık çubuğuyla birlikte çizer
    private static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
    
    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    #endif
}
