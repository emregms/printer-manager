import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var printManager: PrintManager
    @Binding var selectedPDF: URL?
    @Binding var showFilePicker: Bool
    
    @State private var availablePrinters: [String] = []
    @State private var toolStatus: QPDLToolStatus?
    /// Samsung sürücüsünün renk dosyaları (fotoğraf modu) yerinde mi
    @State private var hasColorTables = PrinterColorTables.find() != nil
    
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
                    
                    // Yeni bir Mac'te yazıcı henüz eklenmemişse
                    if !availablePrinters.contains(where: { $0.range(of: "CLP-?300", options: [.regularExpression, .caseInsensitive]) != nil }) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("CLP-300 ekli değil. Ayarlar'daki \"macOS Sürücüsü\" bölümünden ekleyebilirsiniz.")
                                .font(.caption)
                                .foregroundColor(.orange)
                            settingsButton
                        }
                    }
                }
                
                Divider()
                
                // Sayfa geçişi: yazıcının durumuna göre ya da sabit süre
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sayfa Geçişi", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settingsStore.pageTimingMode) {
                        ForEach(PageTimingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(printManager.isPrinting)
                    
                    Text(settingsStore.pageTimingMode == .smart
                         ? "Her sayfa, yazıcı önceki sayfayı basıp kayışı temizledikten ve \"Hazır\" dedikten sonra gönderilir. Soğukken uzun, ısınınca kısa sürer."
                         : "Her sayfadan sonra aşağıdaki süre kadar beklenir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Sabit modda tek bekleme süresi (akıllı modda durum okunamazsa yedek)
                if settingsStore.pageTimingMode == .fixed {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Bekleme Süresi", systemImage: "clock")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(settingsStore.pageWaitSeconds) sn")
                                .font(.subheadline.bold())
                                .foregroundColor(.accentColor)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(settingsStore.pageWaitSeconds) },
                                set: { settingsStore.pageWaitSeconds = Int($0) }
                            ),
                            in: 15...90,
                            step: 1
                        )
                        .tint(.accentColor)
                        .disabled(printManager.isPrinting)
                    }
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
                
                // Fotoğraf Modu: Samsung'un renk tablosu (yalnızca kendi sürücüde)
                Toggle(isOn: $settingsStore.photoMode) {
                    Label("Fotoğraf Modu", systemImage: "photo")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(.switch)
                .tint(.orange)
                .disabled(settingsStore.driverMode != .own || !hasColorTables || printManager.isPrinting)
                
                if settingsStore.driverMode == .own && !hasColorTables {
                    Text("Samsung sürücüsünün renk dosyaları bulunamadı (\(PrinterColorTables.directory.path)). Fotoğraf modu için Samsung'un CLP-300 sürücüsü kurulu olmalı.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.leading, 4)
                } else if settingsStore.photoMode && settingsStore.driverMode == .own {
                    Text("Renkler Samsung'un CLP-300 için ayarladığı renk tablosu ve yarım ton desenleriyle çevrilir: gölgeler açılır, renkler doğal çıkar. Fotoğraflar için; 1200x600 dpi önerilir.")
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Ghostscript Terminal'den ya da yazıcı Ayarlar penceresinden eklendiyse
            // bu pencereye dönünce görünsün
            availablePrinters = PrinterService.shared.availablePrinters()
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
