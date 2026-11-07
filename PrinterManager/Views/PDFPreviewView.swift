import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let pdfURL: URL?
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var isLoading: Bool = false
    @State private var originalPageCount: Int = 0
    /// Baskı başlayınca sıra görünümü, istenirse sayfa ızgarası
    @State private var mode: Mode = .queue
    
    private enum Mode: String, CaseIterable, Identifiable {
        case queue = "Baskı Sırası"
        case pages = "Sayfalar"
        var id: String { rawValue }
    }
    
    /// Çift yönlü mod açık ve sayfa sayısı tek ise boş sayfa gerekli
    private var needsBlankPage: Bool {
        settingsStore.duplexEnabled && originalPageCount > 0 && originalPageCount % 2 != 0
    }
    
    /// Gösterilecek toplam sayfa (boş sayfa dahil)
    private var displayPageCount: Int {
        needsBlankPage ? originalPageCount + 1 : originalPageCount
    }
    
    private var showsQueue: Bool {
        printManager.queue != nil && mode == .queue
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Image(systemName: showsQueue ? "list.number" : "doc.text.image")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(showsQueue ? "Baskı Sırası" : "PDF Önizleme")
                    .font(.headline)
                Spacer()
                
                if printManager.queue != nil {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } else if displayPageCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(displayPageCount) sayfa")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if needsBlankPage {
                            Text("(+1 boş)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            
            if pdfURL != nil {
                if isLoading {
                    ProgressView("Sayfa önizlemeleri yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if showsQueue {
                    PrintQueueView(thumbnails: thumbnails)
                } else if displayPageCount > 0 {
                    pageGrid
                } else {
                    emptyStateView
                }
            } else {
                emptyStateView
            }
        }
        .onChange(of: pdfURL) { newURL in
            loadThumbnails(from: newURL)
        }
        .onChange(of: printManager.isPrinting) { isPrinting in
            if isPrinting {
                mode = .queue
            }
        }
        .onAppear {
            loadThumbnails(from: pdfURL)
        }
    }
    
    private var pageGrid: some View {
        let order = printManager.queue?.printOrder ?? [:]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...displayPageCount, id: \.self) { pageNumber in
                    PageThumbnailView(
                        pageNumber: pageNumber,
                        thumbnail: thumbnails[pageNumber],
                        status: pageStatus(for: pageNumber, order: order),
                        isBlankPage: pageNumber > originalPageCount
                    )
                }
            }
            .padding()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("PDF dosyası seçilmedi")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("PDF dosyasını buraya sürükleyin ya da sol panelden seçin")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    /// Sayfanın durumu baskı sırasından: çift yönde sıra 1, 3, 5... sonra ...6, 4, 2
    private func pageStatus(for pageNumber: Int, order: [UUID: Int]) -> PageStatus {
        guard let queue = printManager.queue else { return .pending(order: nil) }
        let steps = queue.steps.filter { $0.pageNumber == pageNumber }
        guard !steps.isEmpty else { return .pending(order: nil) }
        
        if steps.contains(where: { $0.state == .printing }) {
            return .printing
        }
        if let next = steps.first(where: { $0.state == .pending }) {
            // Bozulup yeniden basılacak
            if steps.contains(where: { $0.state == .spoiled || $0.state == .skipped }) {
                return .reprint(order: order[next.id])
            }
            return .pending(order: order[next.id])
        }
        if steps.contains(where: { $0.state == .printed }) {
            return .printed
        }
        if steps.contains(where: { $0.state == .spoiled }) {
            return .spoiled
        }
        return .skipped
    }
    
    private func loadThumbnails(from url: URL?) {
        guard let url = url else {
            thumbnails = [:]
            originalPageCount = 0
            return
        }
        
        isLoading = true
        thumbnails = [:]
        
        Task {
            guard let document = PDFDocument(url: url) else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            let pageCount = document.pageCount
            await MainActor.run {
                originalPageCount = pageCount
            }
            
            // Her sayfanın thumbnail'ını oluştur
            for pageIndex in 0..<pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                
                let thumbnail = page.thumbnail(of: CGSize(width: 150, height: 200), for: .mediaBox)
                
                await MainActor.run {
                    thumbnails[pageIndex + 1] = thumbnail
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Page Status
enum PageStatus: Equatable {
    /// Sırada; baskı sırasındaki numarası
    case pending(order: Int?)
    case printing
    case printed
    /// Bozuldu, yeniden basılacak
    case reprint(order: Int?)
    /// Bozuldu (yeniden basılmadı)
    case spoiled
    case skipped
}

// MARK: - Page Thumbnail View
struct PageThumbnailView: View {
    let pageNumber: Int
    let thumbnail: NSImage?
    let status: PageStatus
    var isBlankPage: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    // Thumbnail
                    if isBlankPage {
                        // Boş sayfa gösterimi
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 100, height: 130)
                            .cornerRadius(4)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.orange.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            )
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "doc")
                                        .font(.title2)
                                        .foregroundColor(.orange.opacity(0.6))
                                    Text("Boş Sayfa")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            )
                    } else if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 130)
                            .background(Color.white)
                            .cornerRadius(4)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 100, height: 130)
                            .cornerRadius(4)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                            )
                    }
                    
                    // Status overlay
                    statusOverlay
                }
                
                // Baskı sırasındaki numarası
                if let order = orderBadge {
                    Text("\(order)")
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badgeColor))
                        .offset(x: -4, y: -4)
                        .help("Baskı sırasında \(order). sırada")
                }
            }
            
            // Sayfa numarası
            Text("\(pageNumber)")
                .font(.caption.bold())
                .foregroundColor(status == .printing ? .accentColor : .secondary)
        }
        .animation(.easeInOut(duration: 0.3), value: status)
    }
    
    private var orderBadge: Int? {
        switch status {
        case .pending(let order), .reprint(let order): return order
        default: return nil
        }
    }
    
    private var badgeColor: Color {
        if case .reprint = status {
            return .orange
        }
        return .secondary
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        switch status {
        case .printing:
            // Şu an yazdırılıyor
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 100, height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 3)
                )
                .overlay(
                    VStack {
                        Image(systemName: "printer.fill")
                            .font(.title)
                            .foregroundColor(.white)
                        Text("Basılıyor")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                )
        
        case .printed:
            // Yazdırıldı
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 100, height: 130)
                .overlay(
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                )
        
        case .reprint, .spoiled:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange.opacity(0.35))
                .frame(width: 100, height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange, lineWidth: 2)
                )
                .overlay(
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.title)
                        Text(status == .spoiled ? "Bozuk" : "Yeniden\nbasılacak")
                            .font(.caption2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                )
        
        case .skipped:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.35))
                .frame(width: 100, height: 130)
                .overlay(
                    Image(systemName: "minus.circle")
                        .font(.title)
                        .foregroundColor(.white)
                )
        
        case .pending:
            // Beklemede - overlay yok
            EmptyView()
        }
    }
}

#Preview {
    PDFPreviewView(pdfURL: nil)
        .environmentObject(PrintManager())
        .environmentObject(SettingsStore())
        .frame(width: 600, height: 500)
}
