import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var printManager: PrintManager
    @Binding var selectedPDF: URL?
    @Binding var showFilePicker: Bool
    
    @State private var availablePrinters: [String] = []
    @State private var toolStatus: QPDLToolStatus?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Başlık
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("Yazıcı Ayarları")
                        .font(.title2.bold())
                }
                .padding(.bottom, 8)
            
                // Yazıcı Seçimi
                VStack(alignment: .leading, spacing: 6) {
                    Label("Yazıcı", systemImage: "printer")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                
                    Picker("", selection: $settingsStore.selectedPrinter) {
                        Text("Seçiniz...").tag(nil as String?)
                        ForEach(availablePrinters, id: \.self) { printer in
                            Text(printer).tag(printer as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            
                Divider()
            
                // Yazdırma Süresi
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Yazdırma Süresi", systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(settingsStore.printDelaySeconds) sn")
                            .font(.subheadline.bold())
                            .foregroundColor(.accentColor)
                    }
                
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.printDelaySeconds) },
                            set: { settingsStore.printDelaySeconds = Int($0) }
                        ),
                        in: 10...60,
                        step: 1
                    )
                    .tint(.accentColor)
                }
            
                // Temizlik Süresi
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Temizlik Süresi", systemImage: "sparkles")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(settingsStore.cleanDelaySeconds) sn")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.cleanDelaySeconds) },
                            set: { settingsStore.cleanDelaySeconds = Int($0) }
                        ),
                        in: 2...15,
                        step: 1
                    )
                    .tint(.orange)
                }
            
                Divider()
            
                // Çift Yönlü Yazdırma
                Toggle(isOn: $settingsStore.duplexEnabled) {
                    Label("Çift Yönlü Yazdırma", systemImage: "rectangle.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .tint(.green)
            
                if settingsStore.duplexEnabled {
                    Text("Önce tek sayfalar (1, 3, 5...) yazdırılır, sonra kağıtları çevirmeniz istenir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            
                // Siyah Beyaz Yazdırma
                Toggle(isOn: $settingsStore.grayscaleMode) {
                    Label("Siyah Beyaz Yazdırma", systemImage: "circle.lefthalf.filled")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .tint(.gray)
            
                if settingsStore.grayscaleMode {
                    Text("Daha hızlı yazdırma için renkli yerine siyah beyaz modu kullanılır.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                Divider()
                
                // Sürücü
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Sürücü", systemImage: "cpu")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        settingsButton
                    }
                    
                    Picker("", selection: $settingsStore.driverMode) {
                        ForEach(DriverMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(printManager.isPrinting)
                    
                    if settingsStore.driverMode == .own {
                        Picker("", selection: $settingsStore.qpdlResolution) {
                            ForEach(QPDLResolution.allCases) { resolution in
                                Text(resolution.title).tag(resolution)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(printManager.isPrinting)
                        
                        DriverToolStatusView(status: toolStatus)
                            .padding(.leading, 4)
                    } else {
                        Text("macOS'taki Samsung sürücüsü. Yoğun ve renkli sayfalarda çökebilir; yalnızca yedek olarak kullanın.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
                
                Divider()
            
                // PDF Seçimi
                VStack(alignment: .leading, spacing: 8) {
                    Label("PDF Dosyası", systemImage: "doc.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                
                    Button(action: { showFilePicker = true }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("PDF Seç")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(printManager.isPrinting)
                
                    if let pdf = selectedPDF {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(pdf.lastPathComponent)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let pageCount = PDFProcessor.shared.pageCount(of: pdf) {
                                    Text("\(pageCount) sayfa")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            
                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadPrinters()
            refreshToolStatus()
        }
        .onChange(of: settingsStore.ghostscriptPath) { _ in refreshToolStatus() }
        .onChange(of: settingsStore.foo2qpdlPath) { _ in refreshToolStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Ghostscript Terminal'den kurulduysa uygulamaya dönünce görünsün
            refreshToolStatus()
        }
    }
    
    /// Ayarlar penceresini (⌘,) açar
    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Sürücü ayarları (⌘,)")
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Sürücü ayarları (⌘,)")
        }
    }
    
    private func loadPrinters() {
        availablePrinters = PrinterService.shared.availablePrinters()
        printManager.addLog("\(availablePrinters.count) yazıcı bulundu")
    }
    
    private func refreshToolStatus() {
        toolStatus = QPDLToolStatus.check(
            ghostscriptPath: settingsStore.ghostscriptPath,
            foo2qpdlPath: settingsStore.foo2qpdlPath
        )
    }
}

#Preview {
    SettingsView(
        selectedPDF: .constant(nil),
        showFilePicker: .constant(false)
    )
    .environmentObject(SettingsStore())
    .environmentObject(PrintManager())
    .frame(width: 340, height: 600)
}
