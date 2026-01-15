import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let pdfURL: URL?
    @EnvironmentObject var printManager: PrintManager
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var totalPages: Int = 0
    @State private var isLoading: Bool = false
    @State private var originalPageCount: Int = 0
    
    /// Çift yönlü mod açık ve sayfa sayısı tek ise boş sayfa gerekli
    private var needsBlankPage: Bool {
        settingsStore.duplexEnabled && originalPageCount > 0 && originalPageCount % 2 != 0
    }
    
    /// Gösterilecek toplam sayfa (boş sayfa dahil)
    private var displayPageCount: Int {
        needsBlankPage ? originalPageCount + 1 : originalPageCount
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Image(systemName: "doc.text.image")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("PDF Önizleme")
                    .font(.headline)
                Spacer()
                
                if displayPageCount > 0 {
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
            
            // Thumbnail Grid
            if pdfURL != nil {
                if isLoading {
                    ProgressView("Sayfa önizlemeleri yükleniyor...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if displayPageCount > 0 {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(1...displayPageCount, id: \.self) { pageNumber in
                                if pageNumber <= originalPageCount {
                                    // Normal sayfa
                                    PageThumbnailView(
                                        pageNumber: pageNumber,
                                        thumbnail: thumbnails[pageNumber],
                                        status: pageStatus(for: pageNumber),
                                        isBlankPage: false
                                    )
                                } else {
                                    // Boş sayfa (çift yönlü için eklenen)
                                    PageThumbnailView(
                                        pageNumber: pageNumber,
                                        thumbnail: nil,
                                        status: pageStatus(for: pageNumber),
                                        isBlankPage: true
                                    )
                                }
                            }
                        }
                        .padding()
                    }
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
        .onChange(of: settingsStore.duplexEnabled) { _ in
            // Duplex değiştiğinde sayfa sayısını güncelle
            totalPages = displayPageCount
        }
        .onAppear {
            loadThumbnails(from: pdfURL)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("PDF dosyası seçilmedi")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Sol panelden bir PDF dosyası seçin")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func pageStatus(for pageNumber: Int) -> PageStatus {
        guard printManager.isPrinting else { return .pending }
        
        guard let currentPage = printManager.currentPage else { return .pending }
        
        if pageNumber == currentPage {
            return .printing
        } else if pageNumber < currentPage {
            return .printed
        } else {
            return .pending
        }
    }
    
    private func loadThumbnails(from url: URL?) {
        guard let url = url else {
            thumbnails = [:]
            totalPages = 0
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
                totalPages = displayPageCount
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
enum PageStatus {
    case pending
    case printing
    case printed
}

// MARK: - Page Thumbnail View
struct PageThumbnailView: View {
    let pageNumber: Int
    let thumbnail: NSImage?
    let status: PageStatus
    var isBlankPage: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
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
            
            // Sayfa numarası
            Text("\(pageNumber)")
                .font(.caption.bold())
                .foregroundColor(status == .printing ? .green : .secondary)
        }
        .animation(.easeInOut(duration: 0.3), value: status)
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        switch status {
        case .printing:
            // Yeşil şeffaf overlay - şu an yazdırılıyor
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(0.35))
                .frame(width: 100, height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green, lineWidth: 3)
                )
                .overlay(
                    VStack {
                        Image(systemName: "printer.fill")
                            .font(.title)
                            .foregroundColor(.white)
                        Text("Yazdırılıyor")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                )
            
        case .printed:
            // Gri şeffaf overlay - yazdırıldı
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 100, height: 130)
                .overlay(
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                )
            
        case .pending:
            // Beklemede - overlay yok
            EmptyView()
        }
    }
}

#Preview {
    let manager = PrintManager()
    manager.isPrinting = true
    manager.currentPage = 3
    
    return PDFPreviewView(pdfURL: nil)
        .environmentObject(manager)
        .frame(width: 600, height: 500)
}
