import SwiftUI

struct ContentView: View {
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedPDF: URL?
    @State private var showFilePicker = false
    @State private var showFlipPagesAlert = false
    @State private var isDropTargeted = false
    @State private var showSetupAssistant = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Sol Panel - Ayarlar
            VStack(spacing: 0) {
                SettingsView(
                    selectedPDF: $selectedPDF,
                    showFilePicker: $showFilePicker
                )
                
                Spacer()
                
                // Yazdırma Günlüğü
                LogView()
            }
            // Gizli başlık çubuğu: pencere düğmeleri (kırmızı/sarı/yeşil) içeriğin üstüne binmesin
            .padding(.top, 28)
            .frame(width: 340)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Sağ Panel - PDF Önizleme ve Durum
            VStack(spacing: 0) {
                // Yazıcının kendi bildirdiği durum ve toner seviyeleri
                PrinterStatusView()
                
                if printManager.isPrinting {
                    PrintProgressView()
                        .transition(.opacity)
                }
                
                PDFPreviewView(pdfURL: selectedPDF)
                
                // Alt butonlar
                HStack {
                    Button(action: resetAll) {
                        Label("Sıfırla", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(printManager.isPrinting)
                    
                    Spacer()
                    
                    Button(action: {
                        if printManager.isPrinting {
                            printManager.cancel()
                        } else {
                            startPrinting()
                        }
                    }) {
                        Label(
                            printManager.isPrinting ? "İptal" : "Yazdır",
                            systemImage: printManager.isPrinting ? "stop.fill" : "printer.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(printManager.isPrinting ? .red : .blue)
                    .disabled(selectedPDF == nil || settingsStore.selectedPrinter == nil)
                }
                .padding()
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay {
                if isDropTargeted {
                    DropHighlight(isPrinting: printManager.isPrinting)
                }
            }
            // Ön kontrol / büyük sayfa soruları (kağıt çevirme uyarısından ayrı görünümde)
            .alert(
                printManager.prompt?.title ?? "",
                isPresented: Binding(
                    get: { printManager.prompt != nil },
                    // Kapatma yalnızca butonlardan: cevap answerPrompt ile verilir
                    set: { _ in }
                ),
                presenting: printManager.prompt
            ) { prompt in
                ForEach(prompt.actions) { action in
                    Button(action.title, role: action.choice == .cancel ? .cancel : nil) {
                        printManager.answerPrompt(action.choice)
                    }
                }
            } message: { prompt in
                Text(prompt.message)
            }
        }
        // Finder'dan sürüklenen PDF
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: openDropped)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Güvenlik kapsamlı erişim
                    if url.startAccessingSecurityScopedResource() {
                        selectedPDF = url
                        printManager.clearQueue()
                        printManager.addLog("PDF yüklendi: \(url.lastPathComponent)")
                        
                        // Sayfa sayısını al
                        if let pageCount = PDFProcessor.shared.pageCount(of: url) {
                            printManager.addLog("Sayfa sayısı: \(pageCount)")
                        }
                    }
                }
            case .failure(let error):
                printManager.addLog("Hata: \(error.localizedDescription)")
            }
        }
        .alert("Kağıtları Çeviriniz", isPresented: $showFlipPagesAlert) {
            Button("Çevirdim, Devam Et") {
                printManager.continueWithEvenPages()
            }
            Button("İptal", role: .cancel) {
                printManager.cancel()
            }
        } message: {
            Text(printManager.flipMessage)
        }
        .onReceive(printManager.$showFlipPagesDialog) { show in
            showFlipPagesAlert = show
        }
        // Yeni bir Mac: Ghostscript ya da sürücü eksikse kurulum yardımcısı açılır
        .sheet(isPresented: $showSetupAssistant) {
            SetupAssistantView()
                .environmentObject(settingsStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: SetupAssistantView.showNotification)) { _ in
            showSetupAssistant = true
        }
        .task {
            #if DEBUG
            if ScreenshotMode.isActive {
                await ScreenshotMode.run(
                    printManager: printManager,
                    settingsStore: settingsStore,
                    open: { PrintInbox.shared.open(urls: [$0], source: "örnek") },
                    showSetup: { showSetupAssistant = $0 }
                )
                return
            }
            #endif
            let settings = settingsStore.driverSettings
            let incomplete = await Task.detached { SetupAssistantView.isSetupIncomplete(settings: settings) }.value
            if incomplete && !ScreenshotMode.isActive {
                showSetupAssistant = true
            }
        }
        // Başka uygulamalardan (CLP-300 kuyruğu, PDF menüsü, Finder) gelen belgeler
        .onDisappear {
            AppWindow.mainWindowDisappeared()
        }
        .onAppear {
            // Menü çubuğu simgesi gizliyse pencereyi yeniden açma eylemi yalnızca buradan gelir
            AppWindow.openMain = { openWindow(id: "main") }
            AppWindow.mainWindowAppeared()
            PrintInbox.shared.printManager = printManager
            PrintInbox.shared.start()
        }
        .onReceive(PrintInbox.shared.$pending) { document in
            // @Published değeri atamadan önce yayınlar; markTaken bir sonraki
            // döngüde çalışsın ki atamanın altında kalmasın
            if let document = document {
                DispatchQueue.main.async {
                    openIncoming(document)
                }
            }
        }
        .onChange(of: printManager.isPrinting) { isPrinting in
            // Yazdırma sürerken gelen belge bitince açılsın
            if !isPrinting, let document = PrintInbox.shared.pending {
                openIncoming(document)
            }
        }
        .animation(.easeInOut, value: printManager.isPrinting)
    }
    
    private func startPrinting() {
        guard let pdfURL = selectedPDF,
              let printer = settingsStore.selectedPrinter else { return }
        
        Task {
            await printManager.startPrinting(
                pdf: pdfURL,
                printer: printer,
                pageWait: TimeInterval(settingsStore.pageWaitSeconds),
                duplex: settingsStore.duplexEnabled,
                grayscale: settingsStore.grayscaleMode,
                timing: settingsStore.pageTimingMode,
                driver: settingsStore.driverSettings
            )
        }
    }
    
    private func openIncoming(_ document: IncomingDocument) {
        // Yazdırma sürerken belgeyi değiştirme; bitince onChange açar
        guard !printManager.isPrinting else { return }
        
        selectedPDF?.stopAccessingSecurityScopedResource()
        selectedPDF = document.url
        printManager.clearQueue()
        PrintInbox.shared.markTaken(document)
        
        printManager.addLog("PDF yüklendi: \(document.title) (\(document.source))")
        if let pageCount = PDFProcessor.shared.pageCount(of: document.url) {
            printManager.addLog("Sayfa sayısı: \(pageCount)")
        }
    }
    
    /// Bırakılan ilk PDF gelen kutusu yoluyla açılır; yazdırma sürüyorsa bitince açılır
    private func openDropped(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !providers.isEmpty else { return false }
        
        let group = DispatchGroup()
        let lock = NSLock()
        var urls = [URL?](repeating: nil, count: providers.count)
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                lock.lock()
                urls[index] = url
                lock.unlock()
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let pdfs = urls.compactMap { $0 }.filter { $0.pathExtension.lowercased() == "pdf" }
            guard let pdf = pdfs.first else {
                printManager.addLog("⚠️ Yalnızca PDF dosyası bırakılabilir")
                return
            }
            if pdfs.count > 1 {
                printManager.addLog("Birden çok PDF bırakıldı; yalnızca \(pdf.lastPathComponent) açılıyor")
            }
            if printManager.isPrinting {
                printManager.addLog("\(pdf.lastPathComponent) yazdırma bitince açılacak")
            }
            PrintInbox.shared.open(urls: [pdf], source: "sürükle-bırak")
        }
        return true
    }
    
    private func resetAll() {
        selectedPDF?.stopAccessingSecurityScopedResource()
        selectedPDF = nil
        printManager.clearLogs()
        printManager.clearQueue()
        
        // Temp dosyalarını temizle
        Task {
            await PDFProcessor.shared.cleanupTempFiles()
            await MainActor.run {
                printManager.addLog("Cache temizlendi")
            }
        }
    }
}

// MARK: - Drop Highlight
/// PDF pencerenin üstüne sürüklenirken gösterilir
struct DropHighlight: View {
    let isPrinting: Bool
    
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.accentColor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            )
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 44))
                    Text("PDF'yi bırakın")
                        .font(.title2.bold())
                    if isPrinting {
                        Text("Yazdırma bitince açılır")
                            .font(.subheadline)
                    }
                }
                .foregroundColor(.accentColor)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            )
            .padding(10)
            .allowsHitTesting(false)
    }
}

// MARK: - Log View
struct LogView: View {
    @EnvironmentObject var printManager: PrintManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.secondary)
                Text("Yazdırma Günlüğü")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(printManager.logs.enumerated()), id: \.offset) { index, log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: printManager.logs.count) { _ in
                    if let lastIndex = printManager.logs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 150)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(PrintManager())
        .environmentObject(SettingsStore())
}
