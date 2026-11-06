import SwiftUI

/// Ayarlar penceresi (⌘,): kendi sürücünün araç yolları ve ham kuyruk
struct DriverSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    
    @State private var toolStatus: QPDLToolStatus?
    
    var body: some View {
        Form {
            Section {
                TextField("Ghostscript (gs)", text: $settingsStore.ghostscriptPath,
                          prompt: Text("Otomatik: /opt/homebrew/bin/gs"))
                TextField("foo2qpdl", text: $settingsStore.foo2qpdlPath,
                          prompt: Text("Otomatik: uygulama paketindeki"))
                TextField("Ham kuyruk", text: $settingsStore.rawQueueName,
                          prompt: Text("Otomatik: seçili yazıcının kuyruğu"))
                
                DriverToolStatusView(status: toolStatus, showPaths: true)
            } header: {
                Text("Kendi Sürücü")
            } footer: {
                Text("Boş bırakılan alanlar otomatik bulunur. Ghostscript sırasıyla /opt/homebrew/bin, /usr/local/bin ve /opt/local/bin içinde aranır.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Lisans") {
                Text("foo2qpdl, foo2zjs projesinden (Rick Richardson) alınmıştır ve GPL-2.0 lisanslıdır. Uygulama onu ayrı bir program olarak çalıştırır; kaynak kodu ve lisans metni repodaki ThirdParty/foo2qpdl klasöründedir.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear(perform: refresh)
        .onChange(of: settingsStore.ghostscriptPath) { _ in refresh() }
        .onChange(of: settingsStore.foo2qpdlPath) { _ in refresh() }
    }
    
    private func refresh() {
        toolStatus = QPDLToolStatus.check(
            ghostscriptPath: settingsStore.ghostscriptPath,
            foo2qpdlPath: settingsStore.foo2qpdlPath
        )
    }
}

/// Ghostscript / foo2qpdl hazır mı
struct DriverToolStatusView: View {
    let status: QPDLToolStatus?
    var showPaths: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(
                isReady: status?.ghostscriptVersion != nil,
                text: status?.ghostscriptVersion.map { "Ghostscript \($0)" } ?? "Ghostscript bulunamadı",
                path: status?.ghostscript
            )
            row(
                isReady: status?.foo2qpdlVersion != nil,
                text: status?.foo2qpdlShortVersion.map { "foo2qpdl \($0)" } ?? "foo2qpdl bulunamadı",
                path: status?.foo2qpdl
            )
            
            if let status = status, status.ghostscriptVersion == nil {
                Text("Kurmak için Terminal'de: brew install ghostscript")
                    .font(.caption.monospaced())
                    .foregroundColor(.orange)
                    .textSelection(.enabled)
            }
        }
    }
    
    private func row(isReady: Bool, text: String, path: URL?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isReady ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.caption.weight(.medium))
                if showPaths, let path = path {
                    Text(path.path)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview {
    DriverSettingsView()
        .environmentObject(SettingsStore())
}
