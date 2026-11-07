import SwiftUI

struct PrintProgressView: View {
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    
    /// Tahmini kalan süreyi formatla
    private var estimatedTimeText: String {
        let totalSeconds = Int(printManager.estimatedTimeRemaining)
        if totalSeconds <= 0 { return "0 sn" }
        
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        if minutes > 0 {
            return "\(minutes) dk \(seconds) sn"
        } else {
            return "\(seconds) sn"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                // Durum ikonu ve başlık
                if printManager.isPaused {
                    Image(systemName: printManager.pauseReason == nil ? "pause.circle.fill" : "exclamationmark.octagon.fill")
                        .font(.title2)
                        .foregroundColor(printManager.pauseReason == nil ? .orange : .red)
                    Text(printManager.pauseReason == nil ? "Duraklatıldı" : "Yazıcı Hatası: Duraklatıldı")
                        .font(.headline)
                        .foregroundColor(printManager.pauseReason == nil ? .orange : .red)
                } else {
                    Image(systemName: printManager.isCleaningPhase ? "sparkles" : "printer.fill")
                        .font(.title2)
                        .foregroundColor(printManager.isCleaningPhase ? .orange : .accentColor)
                    Text(printManager.isCleaningPhase ? "Belt Temizleme" : "Sayfa Yazdırma")
                        .font(.headline)
                }
                
                Spacer()
                
                // Durdur/Devam Et butonu
                Button(action: {
                    printManager.togglePause()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: printManager.isPaused ? "play.fill" : "pause.fill")
                        Text(printManager.isPaused ? "Devam" : "Duraklat")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(printManager.isPaused ? .green : .orange)
                
                // Biten adım / toplam adım (yeniden basımlar dahil)
                if let queue = printManager.queue {
                    Text("\(min(queue.finishedCount + 1, queue.steps.count)) / \(queue.steps.count)")
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
                                    colors: printManager.isPaused
                                        ? [.gray, .gray.opacity(0.7)]
                                        : (printManager.isCleaningPhase
                                            ? [.orange, .yellow]
                                            : [.blue, .cyan]),
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
                    if printManager.isPaused {
                        Text("⏸ Bekleniyor...")
                    } else if printManager.usesSmartTiming {
                        Text(printManager.isCleaningPhase ? "Yazıcı sayfayı bitirip kayışı temizliyor..." : "Yazıcı sayfayı basıyor...")
                    } else {
                        Text(printManager.isCleaningPhase ? "Temizlik bekleniyor..." : "Yazdırılıyor...")
                    }
                    Spacer()
                    // Akıllı modda süre önceki sayfalardan tahmin
                    Text("Kalan: \(printManager.usesSmartTiming ? "≈" : "")\(Int(printManager.timeRemaining)) sn")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if printManager.isPaused, let reason = printManager.pauseReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Genel ilerleme ve tahmini süre
            let overallProgress = Double(printManager.queue?.finishedCount ?? 0) / Double(max(1, printManager.queue?.steps.count ?? 1))
            
            HStack(spacing: 12) {
                Text("Genel İlerleme")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ProgressView(value: overallProgress)
                    .progressViewStyle(.linear)
                    .tint(.green)
                
                Text("\(Int(overallProgress * 100))%")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(.green)
                    .frame(width: 36)
                
                Divider()
                    .frame(height: 16)
                
                // Tahmini kalan süre
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("≈ \(estimatedTimeText)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
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
