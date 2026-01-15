import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var printManager: PrintManager
    @Binding var selectedPDF: URL?
    @Binding var showFilePicker: Bool
    
    @State private var availablePrinters: [String] = []
    
    var body: some View {
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
        .onAppear {
            loadPrinters()
        }
    }
    
    private func loadPrinters() {
        availablePrinters = PrinterService.shared.availablePrinters()
        printManager.addLog("\(availablePrinters.count) yazıcı bulundu")
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
