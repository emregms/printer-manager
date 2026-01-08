import React, { useEffect, useState, useRef } from 'react';
// PDF.js import işlemleri
import * as pdfjsLib from 'pdfjs-dist';
import { PDFDocumentProxy, PDFPageProxy } from 'pdfjs-dist/types/display/api';

// Worker tanımlama
if (typeof window !== 'undefined' && 'pdfjsLib' in window === false) {
  pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`;
}

interface PdfViewerProps {
  pdfPath: string | null;
  onPageCountChange?: (count: number) => void;
  currentPrintingPage?: number | null;
  previewPageSize?: number; // Önizleme boyutu (px)
}

export const PdfViewer: React.FC<PdfViewerProps> = ({
  pdfPath,
  onPageCountChange,
  currentPrintingPage = null,
  previewPageSize = 200
}) => {
  const [pdfDocument, setPdfDocument] = useState<PDFDocumentProxy | null>(null);
  const [pdfPages, setPdfPages] = useState<Array<{ pageNumber: number; canvas: HTMLCanvasElement | null }>>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const canvasRefs = useRef<Map<number, HTMLCanvasElement>>(new Map());

  // PDF dosyasını yükleme
  useEffect(() => {
    if (!pdfPath) {
      setPdfDocument(null);
      setPdfPages([]);
      return;
    }

    const loadPdf = async () => {
      try {
        setLoading(true);
        // PDF dosyasını URL protokolü ile yükleme
        const pdf = await pdfjsLib.getDocument(`file://${pdfPath}`).promise;
        setPdfDocument(pdf);
        
        // Sayfa sayısını üst bileşene bildir
        if (onPageCountChange) {
          onPageCountChange(pdf.numPages);
        }
        
        // Sayfa bilgilerini oluştur
        const pages = Array.from({ length: pdf.numPages }, (_, i) => ({
          pageNumber: i + 1,
          canvas: null
        }));
        setPdfPages(pages);
        setLoading(false);
      } catch (error) {
        console.error('PDF yüklenirken hata:', error);
        setLoading(false);
      }
    };

    loadPdf();
  }, [pdfPath, onPageCountChange]);

  // Görünür sayfaları render etme
  useEffect(() => {
    if (!pdfDocument) return;

    const renderVisiblePages = async () => {
      // Görünür sayfaları render et (en fazla 8 sayfa)
      const pagesToRender = pdfPages.slice(0, 8);
      
      for (const page of pagesToRender) {
        const canvas = canvasRefs.current.get(page.pageNumber);
        if (!canvas) continue;
        
        try {
          const pdfPage = await pdfDocument.getPage(page.pageNumber);
          const viewport = pdfPage.getViewport({ scale: 1 });
          
          // Canvas boyutunu hesapla
          const scale = previewPageSize / Math.max(viewport.width, viewport.height);
          const scaledViewport = pdfPage.getViewport({ scale });
          
          canvas.width = scaledViewport.width;
          canvas.height = scaledViewport.height;
          
          const renderContext = {
            canvasContext: canvas.getContext('2d')!,
            viewport: scaledViewport,
          };
          
          await pdfPage.render(renderContext).promise;
        } catch (error) {
          console.error(`Sayfa ${page.pageNumber} render edilirken hata:`, error);
        }
      }
    };

    renderVisiblePages();
  }, [pdfDocument, pdfPages, previewPageSize]);

  // Canvas referansını kaydetme
  const setCanvasRef = (pageNumber: number, canvas: HTMLCanvasElement | null) => {
    if (canvas) {
      canvasRefs.current.set(pageNumber, canvas);
    }
  };

  if (!pdfPath) {
    return <div style={{ padding: '20px', textAlign: 'center' }}>Henüz PDF seçilmedi</div>;
  }

  if (loading) {
    return <div style={{ padding: '20px', textAlign: 'center' }}>PDF yükleniyor...</div>;
  }

  return (
    <div style={{ overflow: 'auto', maxHeight: '500px' }}>
      <div style={{ 
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
        gap: '16px',
        padding: '8px'
      }}>
        {pdfPages.map((page) => (
          <div
            key={page.pageNumber}
            style={{
              position: 'relative',
              border: currentPrintingPage === page.pageNumber 
                ? '3px solid #4CAF50' 
                : '1px solid #ddd',
              borderRadius: '4px',
              backgroundColor: '#f9f9f9',
              padding: '8px',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              boxShadow: currentPrintingPage === page.pageNumber 
                ? '0 0 8px rgba(76, 175, 80, 0.7)'
                : 'none',
              transition: 'all 0.3s ease'
            }}
          >
            <div style={{ fontSize: '12px', fontWeight: 'bold', marginBottom: '4px' }}>
              Sayfa {page.pageNumber}
            </div>
            <div style={{
              width: `${previewPageSize}px`,
              height: `${previewPageSize}px`,
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              backgroundColor: '#fff',
            }}>
              <canvas
                ref={(canvas) => setCanvasRef(page.pageNumber, canvas)}
                style={{ 
                  maxWidth: '100%', 
                  maxHeight: '100%', 
                  objectFit: 'contain'
                }}
              />
            </div>
            {currentPrintingPage === page.pageNumber && (
              <div style={{ 
                position: 'absolute', 
                bottom: '4px', 
                right: '4px', 
                background: '#4CAF50', 
                color: 'white', 
                padding: '2px 6px', 
                borderRadius: '10px', 
                fontSize: '10px'
              }}>
                Yazdırılıyor
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};
