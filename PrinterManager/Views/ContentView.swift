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
            Text("Tek numaralı sayfalar yazdırıldı.\nLütfen kağıtları ters çevirip yazıcıya yükleyiniz.")
        }
        .onReceive(printManager.$showFlipPagesDialog) { show in
            showFlipPagesAlert = show
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
                printDelay: TimeInterval(settingsStore.printDelaySeconds),
                cleanDelay: TimeInterval(settingsStore.cleanDelaySeconds),
                duplex: settingsStore.duplexEnabled
            )
        }
    }
    
    private func resetAll() {
        selectedPDF?.stopAccessingSecurityScopedResource()
        selectedPDF = nil
        printManager.clearLogs()
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
