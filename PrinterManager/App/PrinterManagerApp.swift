import SwiftUI

@main
struct PrinterManagerApp: App {
    @StateObject private var printManager = PrintManager()
    @StateObject private var settingsStore = SettingsStore()
    
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
