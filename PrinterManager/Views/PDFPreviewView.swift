import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let pdfURL: URL?
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @EnvironmentObject var printManager: PrintManager
    
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
                
                if totalPages > 0 {
                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
            
            // PDF Görünümü
            ZStack {
                if let url = pdfURL {
                    PDFKitRepresentable(
                        url: url,
                        currentPage: $currentPage,
                        totalPages: $totalPages,
                        highlightedPage: printManager.currentPage
                    )
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.horizontal)
                } else {
                    // Boş durum
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
            }
            
            // Sayfa navigasyonu
            if totalPages > 1 {
                HStack(spacing: 20) {
                    Button(action: { navigatePage(-1) }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0)
                    .foregroundColor(currentPage == 0 ? .secondary : .accentColor)
                    
                    // Sayfa göstergesi
                    HStack(spacing: 4) {
                        ForEach(0..<min(totalPages, 10), id: \.self) { page in
                            Circle()
                                .fill(page == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                        if totalPages > 10 {
                            Text("...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: { navigatePage(1) }) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage >= totalPages - 1)
                    .foregroundColor(currentPage >= totalPages - 1 ? .secondary : .accentColor)
                }
                .padding(.vertical, 12)
            }
        }
        .onChange(of: pdfURL) { newURL in
            currentPage = 0
            if let url = newURL {
                totalPages = PDFProcessor.shared.pageCount(of: url) ?? 0
            } else {
                totalPages = 0
            }
        }
    }
    
    private func navigatePage(_ offset: Int) {
        let newPage = currentPage + offset
        if newPage >= 0 && newPage < totalPages {
            currentPage = newPage
        }
    }
}

// MARK: - PDFKit Wrapper
struct PDFKitRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    let highlightedPage: Int?
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = NSColor.clear
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            DispatchQueue.main.async {
                self.totalPages = document.pageCount
            }
        }
        
        // Sayfa değişim bildirimi
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = pdfView.document,
           let page = document.page(at: currentPage) {
            pdfView.go(to: page)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFKitRepresentable
        
        init(_ parent: PDFKitRepresentable) {
            self.parent = parent
        }
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            let pageIndex = document.index(for: currentPage)
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }
    }
}

#Preview {
    PDFPreviewView(pdfURL: nil)
        .environmentObject(PrintManager())
        .frame(width: 600, height: 500)
}
