import SwiftUI

struct PrintProgressView: View {
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: printManager.isCleaningPhase ? "sparkles" : "printer.fill")
                    .font(.title2)
                    .foregroundColor(printManager.isCleaningPhase ? .orange : .accentColor)
                
                Text(printManager.isCleaningPhase ? "Belt Temizleme" : "Sayfa Yazdırma")
                    .font(.headline)
                
                Spacer()
                
                if let current = printManager.currentPage {
                    Text("\(current) / \(printManager.totalPages)")
                        .font(.title3.bold())
                        .foregroundColor(.accentColor)
                }
            }
            
            // İlerleme çubuğu
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Arka plan
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.2))
                        
                        // İlerleme
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: printManager.isCleaningPhase 
                                        ? [.orange, .yellow] 
                                        : [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * printManager.progress))
                            .animation(.linear(duration: 0.1), value: printManager.progress)
                    }
                }
                .frame(height: 12)
                
                HStack {
                    Text(printManager.isCleaningPhase ? "Temizlik bekleniyor..." : "Yazdırılıyor...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Kalan: \(Int(printManager.timeRemaining)) sn")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            
            // Genel ilerleme
            let overallProgress = Double(printManager.currentPage ?? 0) / Double(max(1, printManager.totalPages))
            
            HStack {
                Text("Genel İlerleme")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ProgressView(value: overallProgress)
                    .progressViewStyle(.linear)
                    .tint(.green)
                
                Text("\(Int(overallProgress * 100))%")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(.green)
                    .frame(width: 40)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .padding()
    }
}

#Preview {
    let manager = PrintManager()
    manager.isPrinting = true
    manager.currentPage = 3
    manager.totalPages = 10
    manager.progress = 0.65
    manager.timeRemaining = 15
    manager.isCleaningPhase = false
    
    return PrintProgressView()
        .environmentObject(manager)
        .environmentObject(SettingsStore())
        .frame(width: 500, height: 200)
}
