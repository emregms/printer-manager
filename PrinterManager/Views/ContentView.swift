import SwiftUI

struct ContentView: View {
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var selectedPDF: URL?
    @State private var showFilePicker = false
    @State private var showFlipPagesAlert = false
    
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
        // Başka uygulamalardan (CLP-300 kuyruğu, PDF menüsü, Finder) gelen belgeler
        .onAppear {
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
