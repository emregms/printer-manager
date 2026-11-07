import SwiftUI

/// Yazıcının anlık durumu ve toner seviyeleri (USB'den, 10 sn'de bir)
struct PrinterStatusView: View {
    @ObservedObject private var monitor = PrinterStatusMonitor.shared
    @State private var showDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            if let status = monitor.status {
                if status.showsToners {
                    HStack(spacing: 14) {
                        ForEach(status.toners) { toner in
                            TonerGauge(toner: toner)
                        }
                    }
                }
                
                if showDetails {
                    details(status)
                        .transition(.opacity)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top)
        .onAppear { monitor.start() }
        .animation(.easeInOut(duration: 0.2), value: showDetails)
    }
    
    // MARK: - Parts
    
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(accent)
                .frame(width: 26)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.status?.title ?? (monitor.errorMessage == nil ? "Yazıcı durumu okunuyor..." : "Yazıcı durumu alınamadı"))
                    .font(.headline)
                if let advice = monitor.status?.advice ?? monitor.errorMessage {
                    Text(advice)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 8)
            
            if let date = monitor.status?.date {
                Text(date, style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            Button {
                monitor.refresh()
            } label: {
                if monitor.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Durumu yenile")
            .frame(width: 18)
            
            if monitor.status != nil {
                Button {
                    showDetails.toggle()
                } label: {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Ayrıntılar")
            }
        }
    }
    
    private func details(_ status: PrinterStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            detailRow("Durum kodu", status.codeText, monospaced: true)
            if let text = status.printerText {
                detailRow("Yazıcının mesajı", text)
            }
            if let state = status.deviceState {
                detailRow("USB durumu", state)
            }
            if status.paperEmpty {
                detailRow("Kağıt", "Yok")
            }
            if let firmware = status.firmware {
                detailRow("Ürün yazılımı", firmware)
            }
            detailRow("Atık toner kabı", StatusText.wasteTonerPart)
            detailRow("Görüntüleme ünitesi", StatusText.imagingUnitPart)
        }
        .font(.caption)
    }
    
    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
    
    private var icon: String {
        guard let status = monitor.status else {
            return monitor.errorMessage == nil ? "printer" : "printer.fill"
        }
        switch status.severity {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    
    private var accent: Color {
        guard let status = monitor.status else { return .secondary }
        switch status.severity {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

/// Tek bir toner için renkli seviye çubuğu
struct TonerGauge: View {
    let toner: Toner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(toner.color.swatch)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .frame(width: 9, height: 9)
                Text(toner.color.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(percentText)
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(toner.isLow ? .orange : .primary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(toner.color.swatch)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
            
            HStack(spacing: 4) {
                Text(toner.partNumber ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if toner.isLow, toner.percent != nil {
                    Text(toner.percent == 0 ? "Bitti" : "Az")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(toner.percent == 0 ? Color.red : Color.orange))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(toner.color.name) toner: \(percentText)")
    }
    
    private var fraction: CGFloat {
        CGFloat(min(max(toner.percent ?? 0, 0), 100)) / 100
    }
    
    private var percentText: String {
        toner.percent.map { "%\($0)" } ?? "—"
    }
}

#Preview {
    PrinterStatusView()
        .frame(width: 700)
}
