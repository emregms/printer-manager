import SwiftUI

/// Kurulum yardımcısı: yeni bir Mac'te gerekenler tek pencerede, sırayla.
/// Kurulum eksikse ilk açılışta kendiliğinden, sonra PrinterManager menüsünden açılır.
struct SetupAssistantView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var toolStatus: QPDLToolStatus?
    @State private var colorTables = PrinterColorTables.find()
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Form {
                Section {
                    DriverToolStatusView(status: toolStatus)
                } header: {
                    Text("1. Yazdırma Araçları")
                } footer: {
                    Text("Sayfaları yazıcının noktalarına çeviren açık kaynak programlar (Ghostscript ve foo2qpdl) uygulamanın içinde gelir; ayrıca bir şey kurmanız gerekmez.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                DriverInstallSection(title: "2. Yazıcı ve Sürücü")
                
                OtherAppsSection(title: "3. Başka Uygulamalardan Yazdırma (isteğe bağlı)")
                
                NetworkSharingSection(title: "4. iPhone ve iPad'den Yazdırma (isteğe bağlı)")
                
                Section {
                    LabeledContent("Renk verisi") {
                        if let tables = colorTables {
                            Label(tables.source.title, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .help(tables.directory.path)
                        } else {
                            Text("Bulunamadı")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("5. Fotoğraf Modu")
                } footer: {
                    Text("""
                    Fotoğraf modu uygulamanın içinde gelen kendi CLP-300 renk tablosu ve yarım ton \
                    desenleriyle basar; ayrıca bir şey kurmak gerekmez. Samsung'un eski Mac sürücüsünün \
                    renk dosyaları varsa önce onlar kullanılır. Arama sırası: \
                    \(PrinterColorTables.searchDirectories.dropLast().map { $0.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", ")), \
                    sonra uygulamanın içi.
                    """)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Text("Bu pencere PrinterManager menüsündeki Kurulum Yardımcısı'ndan yeniden açılır.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Tamam") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580, height: 860)
        .onAppear(perform: refresh)
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "printer.fill")
                .font(.system(size: 34))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("PrinterManager Kurulumu")
                    .font(.title2.bold())
                Text("Samsung CLP-300'ü bu Mac'te kullanmak için aşağıdaki adımlar bir kez yapılır. Yeşil tikli adımlar tamam; Samsung'un eski sürücüsü gerekmez.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 8)
    }
    
    private func refresh() {
        toolStatus = QPDLToolStatus.check(
            ghostscriptPath: settingsStore.ghostscriptPath,
            foo2qpdlPath: settingsStore.foo2qpdlPath
        )
        colorTables = PrinterColorTables.find()
    }
}

extension SetupAssistantView {
    /// PrinterManager menüsündeki komut bu bildirimle pencereyi açar
    static let showNotification = Notification.Name("PrinterManagerShowSetupAssistant")
    
    /// Ghostscript ya da macOS sürücüsü eksik ya da sürücü eskiyse; ana iş parçacığında çağırmayın
    nonisolated static func isSetupIncomplete(settings: DriverSettings) -> Bool {
        let tools = QPDLToolStatus.check(ghostscriptPath: settings.ghostscriptPath, foo2qpdlPath: settings.foo2qpdlPath)
        return tools.ghostscriptVersion == nil || DriverInstaller.inboxQueues().isEmpty
            || !DriverInstaller.isFilterUpToDate
    }
}

#Preview {
    SetupAssistantView()
        .environmentObject(SettingsStore())
}
