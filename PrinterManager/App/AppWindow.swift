import AppKit
import OSLog
import SwiftUI

/// Pencere kapanınca uygulama arka planda sürer: Dock simgesi gizlenir, menü çubuğunda
/// küçük bir simge kalır. Belge gelince, yazdırma bir şey sorunca ya da kullanıcı isteyince
/// pencere yeniden açılır. Arka planda yoklama yapılmaz: gelen işleri pminbox'un
/// bildirimi uyandırır (bkz. PrintInbox), yazıcı durumu yalnızca pencere açıkken okunur.
@MainActor
enum AppWindow {
    /// `log show --predicate 'subsystem == "com.samsungclp300.printermanager"'`
    static let log = Logger(subsystem: "com.samsungclp300.printermanager", category: "window")
    
    /// SwiftUI'nin pencere açma eylemi; pencere ya da menü çubuğu simgesi çizilince alınır
    static var openMain: (() -> Void)?
    /// Oturum açılışında başlatıldı: pencere gösterilmeden arka planda bekle
    static var startsHidden = false
    
    private static var mainWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
    }
    
    /// Pencereyi öne getirir; kapalıysa açar
    static func show() {
        log.info("Pencere açılıyor (arka plandan)")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else if let openMain = openMain {
            openMain()
        } else {
            log.error("Pencere açılamadı: menü çubuğu simgesi henüz hazır değil")
        }
    }
    
    /// Yalnızca pencere kapalıysa açar (yazdırma bir şey soracaksa)
    static func showIfHidden() {
        if !mainWindows.contains(where: { $0.isVisible }) {
            show()
        }
    }
    
    /// Pencereleri kapatır; uygulama menü çubuğunda sürer
    static func moveToBackground() {
        for window in NSApp.windows where window.isVisible && window.canBecomeMain {
            window.close()
        }
        enterBackground()
    }
    
    static func quit() {
        NSApp.terminate(nil)
    }
    
    /// Ana pencere göründü: oturum açılışındaysa hemen kapat, değilse Dock simgesini göster
    static func mainWindowAppeared() {
        if startsHidden {
            startsHidden = false
            DispatchQueue.main.async {
                mainWindows.forEach { $0.close() }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    /// Görünür pencere kalmadıysa Dock simgesini gizle
    static func windowWillClose(_ closing: NSWindow) {
        guard closing.canBecomeMain else { return }
        let others = NSApp.windows.filter { $0 !== closing && $0.isVisible && $0.canBecomeMain }
        if others.isEmpty {
            enterBackground()
        }
    }
    
    /// Ana pencerenin içeriği kayboldu. SwiftUI tek pencereyi kapatırken her zaman
    /// willClose göndermiyor; kapanma bitince yeniden bak.
    static func mainWindowDisappeared() {
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                enterBackground()
            }
        }
    }
    
    private static func enterBackground() {
        guard NSApp.activationPolicy() != .accessory else { return }
        log.info("Arka plana geçildi: Dock simgesi gizlendi")
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Menü çubuğundaki simge; çizilince pencere açma eylemini AppWindow'a verir
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Image(systemName: "printer.fill")
            .onAppear {
                AppWindow.openMain = { openWindow(id: "main") }
            }
    }
}

/// Menü çubuğu simgesinin menüsü: son bilinen durum ve pencereyi açma
struct MenuBarContent: View {
    @EnvironmentObject var printManager: PrintManager
    @ObservedObject private var monitor = PrinterStatusMonitor.shared
    
    var body: some View {
        if printManager.isPrinting, let queue = printManager.queue {
            Text("Yazdırılıyor: \(queue.finishedCount) / \(queue.steps.count)")
        }
        if let status = monitor.status {
            Text("CLP-300: \(status.title)" + (status.heat.map { " · \($0.title)" } ?? ""))
        }
        Text("iPhone ve Mac'ten gelen belgeler bekleniyor")
        
        Divider()
        
        Button("PrinterManager'ı Aç") {
            AppWindow.show()
        }
        Button("Kurulum Yardımcısı…") {
            AppWindow.show()
            // Pencere yeni açılıyorsa önce görünsün
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: SetupAssistantView.showNotification, object: nil)
            }
        }
        
        Divider()
        
        Button("PrinterManager'dan Çık") {
            AppWindow.quit()
        }
    }
}
