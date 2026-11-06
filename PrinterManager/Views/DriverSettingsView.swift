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
                
                if toolStatus?.ghostscriptVersion == nil {
                    GhostscriptInstallView(onFinished: refresh)
                }
            } header: {
                Text("Kendi Sürücü")
            } footer: {
                Text("Boş bırakılan alanlar otomatik bulunur. Ghostscript sırasıyla /opt/homebrew/bin, /usr/local/bin ve /opt/local/bin içinde aranır.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            DriverInstallSection()
            
            OtherAppsSection()
            
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

/// macOS sürücüsü: CLP-300'ü Yazıcılar ve Tarayıcılar'a ekler
struct DriverInstallSection: View {
    @State private var status: DriverInstaller.Status?
    @State private var selectedURI: String?
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false
    
    var body: some View {
        Section {
            if let status = status {
                LabeledContent("Sürücü") {
                    if status.isDriverInstalled {
                        Label(status.queues.isEmpty ? "Kurulu (kuyruk yok)" : "Kurulu: \(status.queues.joined(separator: ", "))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("Kurulu değil")
                            .foregroundColor(.secondary)
                    }
                }
                
                LabeledContent("USB'deki yazıcı") {
                    if status.deviceURIs.isEmpty {
                        Text("Bulunamadı. Yazıcı açık ve USB'ye bağlı mı?")
                            .foregroundColor(.orange)
                    } else if status.deviceURIs.count == 1 {
                        Text(status.deviceURIs[0])
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Picker("", selection: $selectedURI) {
                            ForEach(status.deviceURIs, id: \.self) { uri in
                                Text(uri).tag(uri as String?)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                HStack {
                    Button(status.isDriverInstalled ? "Sürücüyü Güncelle" : "Sürücüyü Kur ve Yazıcıyı Ekle") {
                        install(status)
                    }
                    .disabled(isWorking || status.deviceURIs.isEmpty)
                    
                    if status.isDriverInstalled || !status.queues.isEmpty {
                        Button("Kaldır", role: .destructive) {
                            uninstall(status)
                        }
                        .disabled(isWorking)
                    }
                    
                    Spacer()
                    
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Yenile")
                    .disabled(isWorking)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(messageIsError ? .red : .green)
                    .textSelection(.enabled)
            }
        } header: {
            Text("macOS Sürücüsü")
        } footer: {
            Text("""
            Kurulunca CLP-300, Yazıcılar ve Tarayıcılar'da görünür; Samsung'un eski sürücüsü \
            gerekmez. Safari, Önizleme gibi bir uygulamada bu yazıcıyla "Yazdır" dediğinizde \
            belge basılmaz, PrinterManager'da açılır: buradan sayfa arası bekleme ve elle çift \
            yönle basarsınız. PrinterManager kapalıysa belge kuyrukta bekler, açınca gelir. \
            Kurulum yönetici şifresi ister; var olan yazıcı kuyruklarına dokunulmaz.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .task { await refresh() }
    }
    
    private func refresh() async {
        let current = await Task.detached { DriverInstaller.currentStatus() }.value
        status = current
        if selectedURI == nil || !current.deviceURIs.contains(selectedURI ?? "") {
            selectedURI = current.deviceURIs.first
        }
    }
    
    private func install(_ status: DriverInstaller.Status) {
        guard let uri = selectedURI ?? status.deviceURIs.first else { return }
        let target = DriverInstaller.suggestedQueue(status: status)
        run {
            _ = try DriverInstaller.install(deviceURI: uri, queue: target.name, description: target.description)
            return "✓ \"\(target.description)\" eklendi (kuyruk: \(target.name)). Yazıcılar ve Tarayıcılar'da görünür."
        }
    }
    
    private func uninstall(_ status: DriverInstaller.Status) {
        run {
            _ = try DriverInstaller.uninstall(queues: status.queues)
            return "✓ Sürücü kaldırıldı" + (status.queues.isEmpty ? "" : " (\(status.queues.joined(separator: ", ")))")
        }
    }
    
    /// Yetkili işlemi çalıştırır (şifre penceresi ana iş parçacığında açılır)
    private func run(_ operation: @escaping () throws -> String) {
        isWorking = true
        message = nil
        Task { @MainActor in
            do {
                message = try operation()
                messageIsError = false
            } catch {
                message = error.localizedDescription
                messageIsError = true
            }
            await refresh()
            PrintInbox.shared.refreshQueues()
            isWorking = false
        }
    }
}

/// Başka uygulamalardan PrinterManager'a belge getiren kısayollar
struct OtherAppsSection: View {
    @State private var hasPDFService = PrintInbox.isPDFServiceInstalled
    @State private var opensAtLogin = PrintInbox.opensAtLogin
    @State private var message: String?
    
    var body: some View {
        Section {
            Toggle("Yazdırma penceresinin PDF menüsüne \"PrinterManager ile Yazdır\" ekle", isOn: Binding(
                get: { hasPDFService },
                set: { setPDFService($0) }
            ))
            Toggle("Oturum açılınca PrinterManager'ı başlat", isOn: Binding(
                get: { opensAtLogin },
                set: { setOpensAtLogin($0) }
            ))
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Başka Uygulamalardan Yazdırma")
        } footer: {
            Text("""
            PDF menüsü: herhangi bir uygulamada ⌘P → sol alttaki PDF ▾ → "PrinterManager ile Yazdır"; \
            hangi yazıcı seçili olursa olsun belge PrinterManager'da açılır. \
            Oturum açılınca başlatma: CLP-300 yazıcısına gönderilen belgeler, PrinterManager \
            açık değilse kuyrukta bekler; uygulama hep açık olursa hemen gelir.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    private func setPDFService(_ enabled: Bool) {
        do {
            if enabled {
                try PrintInbox.installPDFService()
            } else {
                try PrintInbox.removePDFService()
            }
            message = nil
        } catch {
            message = "PDF menüsü ayarlanamadı: \(error.localizedDescription)"
        }
        hasPDFService = PrintInbox.isPDFServiceInstalled
    }
    
    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            try PrintInbox.setOpensAtLogin(enabled)
            message = nil
        } catch {
            message = "Oturum açılışı ayarlanamadı: \(error.localizedDescription)"
        }
        opensAtLogin = PrintInbox.opensAtLogin
    }
}

/// Ghostscript yoksa Homebrew ile kurar
struct GhostscriptInstallView: View {
    let onFinished: () -> Void
    
    @State private var isInstalling = false
    @State private var output: String?
    
    private var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let brew = brew {
                HStack {
                    Button("Ghostscript'i Kur (Homebrew)") {
                        install(with: brew)
                    }
                    .disabled(isInstalling)
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                        Text("Kuruluyor, 1–2 dakika sürebilir...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Homebrew kurulu değil. Önce brew.sh adresindeki komutla Homebrew'u, sonra Ghostscript'i kurun.")
                    .font(.caption)
                    .foregroundColor(.orange)
                Link("brew.sh", destination: URL(string: "https://brew.sh")!)
                    .font(.caption)
            }
            
            if let output = output {
                Text(output)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }
    
    private func install(with brew: URL) {
        isInstalling = true
        output = nil
        Task {
            let result = await Task.detached { () -> String in
                let logURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("brew-install-ghostscript.log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                guard let log = try? FileHandle(forWritingTo: logURL) else { return "Günlük dosyası açılamadı" }
                defer { try? log.close() }
                
                let process = Process()
                process.executableURL = brew
                process.arguments = ["install", "ghostscript"]
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "\(brew.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment
                process.standardOutput = log
                process.standardError = log
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    return "brew çalıştırılamadı: \(error.localizedDescription)"
                }
                let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                let tail = text.split(separator: "\n").suffix(3).joined(separator: "\n")
                return process.terminationStatus == 0 ? "✓ Kuruldu\n\(tail)" : "brew hata verdi (kod \(process.terminationStatus)):\n\(tail)"
            }.value
            output = result
            isInstalling = false
            onFinished()
        }
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
