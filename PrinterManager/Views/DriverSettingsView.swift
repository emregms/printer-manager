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
            
            NetworkSharingSection()
            
            BackgroundSection()
            
            PowerSaveSection()
            
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
    var title = "macOS Sürücüsü"
    
    @State private var status: DriverInstaller.Status?
    @State private var selectedURI: String?
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false
    
    var body: some View {
        Section {
            if let status = status {
                LabeledContent("Sürücü") {
                    if status.isDriverInstalled && !status.isDriverUpToDate {
                        Label("Güncelleme var: Sürücüyü Güncelle'ye basın", systemImage: "arrow.down.circle.fill")
                            .foregroundColor(.orange)
                    } else if status.isDriverInstalled {
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
                        Text(ScreenshotMode.masked(status.deviceURIs[0]))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        Picker("", selection: $selectedURI) {
                            ForEach(status.deviceURIs, id: \.self) { uri in
                                Text(ScreenshotMode.masked(uri)).tag(uri as String?)
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
            Text(title)
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
            AirPrintAdvertiser.shared.update()
            isWorking = false
        }
    }
}

/// Başka uygulamalardan PrinterManager'a belge getiren kısayollar
struct OtherAppsSection: View {
    var title = "Başka Uygulamalardan Yazdırma"
    
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
            Text(title)
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

/// Pencere kapalıyken uygulama menü çubuğunda bekler; simge istenirse gizlenir
struct BackgroundSection: View {
    @AppStorage("showMenuBarIcon") private var showsMenuBarIcon = true
    
    var body: some View {
        Section {
            Toggle("Menü çubuğunda simgeyi göster", isOn: $showsMenuBarIcon)
        } header: {
            Text("Arka Planda Çalışma")
        } footer: {
            Text("""
            Pencere kapanınca PrinterManager arka planda sürer; belge gelince pencere kendiliğinden açılır. \
            Simge gizliyken pencereyi açmak için PrinterManager'ı Uygulamalar'dan ya da Spotlight'tan \
            yeniden açın. Tamamen çıkmak: pencere açıkken ⌥⌘Q.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

/// iPhone ve iPad'den yazdırma: kuyruk yerel ağda paylaşılır (AirPrint). Telefondan gelen
/// belge bu Mac'te PrinterManager'da açılır; baskı her zamanki gibi buradan yapılır.
struct NetworkSharingSection: View {
    var title = "iPhone ve iPad'den Yazdırma"
    
    @State private var queue: String?
    @State private var printerName = "Samsung CLP-300"
    @State private var computerName = "bu Mac"
    @State private var isShared = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false
    
    var body: some View {
        Section {
            Toggle("Yazıcıyı yerel ağda paylaş (AirPrint)", isOn: Binding(
                get: { isShared },
                set: { setShared($0) }
            ))
            .disabled(queue == nil || isWorking)
            
            if queue == nil {
                Text("Önce yazıcıyı ve sürücüyü kurun.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isShared && !PrintInbox.opensAtLogin {
                Text("Öneri: \"Oturum açılınca PrinterManager'ı başlat\"ı açın; PrinterManager kapalıyken gelen belgeler kuyrukta bekler.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(messageIsError ? .red : .green)
                    .textSelection(.enabled)
            }
        } header: {
            Text(title)
        } footer: {
            Text("""
            iPhone ya da iPad'de Paylaş → Yazdır → "\(printerName) @ \(computerName)". Belge bu \
            Mac'te PrinterManager'da açılır; ayarları yapıp buradan basarsınız. Mac açık ve aynı \
            ağda olmalı; PrinterManager pencere kapalıyken menü çubuğunda, işlemci harcamadan \
            bekler. Paylaşmak yönetici şifresi ister.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .task { await refresh() }
    }
    
    private func refresh() async {
        let result = await Task.detached { () -> (String?, String?, Bool, String?) in
            // Ağda görünen ad: "<yazıcı adı> @ <Mac adı>"; ad sorgusu yavaş olabilir
            let computer = Host.current().localizedName
            guard let queue = DriverInstaller.inboxQueues().first,
                  let status = PrinterService.shared.queueStatus(queue) else { return (nil, nil, false, computer) }
            return (queue, status.info, status.isShared && PrinterService.shared.isPrinterSharingEnabled, computer)
        }.value
        queue = result.0
        printerName = result.1 ?? printerName
        isShared = result.2
        computerName = result.3 ?? computerName
    }
    
    /// Yetkili işlem: şifre penceresi ana iş parçacığında açılır
    private func setShared(_ shared: Bool) {
        guard let queue = queue else {
            message = "PrinterManager kuyruğu bulunamadı; önce sürücüyü kurun."
            messageIsError = true
            return
        }
        AppWindow.log.info("Ağ paylaşımı: \(shared ? "açılıyor" : "kapatılıyor", privacy: .public) (\(queue, privacy: .public))")
        isWorking = true
        message = nil
        Task { @MainActor in
            do {
                _ = try DriverInstaller.setShared(shared, queue: queue)
                AirPrintAdvertiser.shared.update()
                message = shared
                    ? "✓ Paylaşıldı. iPhone'da yazdırırken \"\(printerName)\" görünür."
                    : "✓ Paylaşım kapatıldı"
                messageIsError = false
            } catch {
                AppWindow.log.error("Ağ paylaşımı başarısız: \(error.localizedDescription, privacy: .public)")
                message = error.localizedDescription
                messageIsError = true
            }
            await refresh()
            isWorking = false
        }
    }
}

/// Yazıcının boşta sıcak bekleme süresi; yazıcının kendi ayarıdır, PJL ile okunur ve yazılır
struct PowerSaveSection: View {
    @ObservedObject private var monitor = PrinterStatusMonitor.shared
    @State private var settings: PrinterPowerSave.Settings?
    @State private var minutes = PrinterPowerSave.choices[0]
    @State private var isWorking = false
    @State private var message: String?
    
    var body: some View {
        Section {
            Picker("Boşta kalınca uyku", selection: $minutes) {
                ForEach(PrinterPowerSave.choices, id: \.self) { value in
                    Text("\(value) dk sonra").tag(value)
                }
            }
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let settings = settings {
                        Text(currentText(settings))
                        if let stored = settings.stored, stored != settings.current {
                            Text("Yazıcıya kaydedilen: \(stored) dk. Yazıcıyı kapatıp açınca geçerli olur.")
                                .foregroundColor(.orange)
                        }
                    } else {
                        Text(isWorking ? "Yazıcıdan okunuyor..." : "Yazıcıdan okunmadı")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                
                Spacer()
                
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Yenile", action: load)
                    .disabled(isWorking)
                Button("Yazıcıya Uygula", action: apply)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || (settings?.isEnabled == true && minutes == settings?.stored))
            }
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Yazıcı Güç Tasarrufu")
        } footer: {
            Text("""
            CLP-300 baskıdan sonra fırınını sıcak tutar ve bu süre dolunca uykuya geçer; \
            en kısa süre 5 dakikadır. Ayar yazıcının belleğine yazılır ve yazıcı kapatılıp \
            açılınca geçerli olur. Uyuyan yazıcıda ilk sayfa ısınma yüzünden biraz geç başlar.
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .onAppear(perform: load)
    }
    
    private func currentText(_ settings: PrinterPowerSave.Settings) -> String {
        guard settings.isEnabled else { return "Güç tasarrufu kapalı: yazıcı hep sıcak bekliyor" }
        return settings.current.map { "Şu an: boşta \($0) dk kalınca uyuyor" } ?? "Şu anki süre okunamadı"
    }
    
    private func load() {
        run { try PrinterPowerSave.read() }
    }
    
    private func apply() {
        let minutes = minutes
        run { try PrinterPowerSave.apply(minutes: minutes) }
    }
    
    /// Yazıcıyla konuşma birkaç saniye sürebilir; ana iş parçacığını tutmaz
    private func run(_ work: @escaping () throws -> PrinterPowerSave.Settings) {
        isWorking = true
        message = nil
        Task {
            let result = await Task.detached { Result { try work() } }.value
            await MainActor.run {
                switch result {
                case .success(let settings):
                    self.settings = settings
                    minutes = settings.stored ?? settings.current ?? minutes
                    monitor.powerSaveMinutes = settings.isEnabled ? settings.current : nil
                case .failure(let error):
                    message = error.localizedDescription
                }
                isWorking = false
            }
        }
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
                HStack {
                    Button("Terminal'de Kur (Homebrew + Ghostscript)") {
                        openInstallerInTerminal()
                    }
                    Button("Tekrar Kontrol Et", action: onFinished)
                }
                Text("""
                Homebrew bu Mac'te yok. Düğme Terminal'de resmi Homebrew kurulumunu ve ardından \
                Ghostscript'i başlatır: Mac şifrenizi sorar, Enter ister ve 5–10 dakika sürer. \
                "Bitti" yazınca buraya dönüp Tekrar Kontrol Et'e basın.
                """)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Link("Homebrew hakkında: brew.sh", destination: URL(string: "https://brew.sh")!)
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
    
    /// Homebrew yoksa: resmi kurulum betiğini ve Ghostscript'i çalıştıran bir .command
    /// dosyası yazıp Terminal'de açar (şifre ve onay kullanıcıdan istenir)
    private func openInstallerInTerminal() {
        let script = """
        #!/bin/bash
        echo "PrinterManager: Homebrew ve Ghostscript kuruluyor."
        echo "Homebrew kurulumu Mac şifrenizi ve Enter tuşunu isteyebilir."
        echo
        if [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
        fi
        BREW=/opt/homebrew/bin/brew
        [ -x "$BREW" ] || BREW=/usr/local/bin/brew
        "$BREW" install ghostscript || exit 1
        echo
        echo "Bitti. PrinterManager'a dönüp Tekrar Kontrol Et'e basın; bu pencereyi kapatabilirsiniz."
        """
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrinterManager")
        let url = directory.appendingPathComponent("Ghostscript Kur.command")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            output = "Kurulum betiği yazılamadı: \(error.localizedDescription)"
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
                    Text(ScreenshotMode.masked(path.path))
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
