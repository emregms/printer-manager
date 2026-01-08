import React, { useEffect, useState, useCallback } from 'react';
import './pdfViewer.css';

type PreviewResult = Window['api'] extends { generatePreview: () => Promise<infer T> } ? T : never;

interface EnhancedPdfViewerProps {
  pdfPath: string | null;
  onPageCountChange: (count: number) => void;
  currentPrintingPage?: number | null;
}

export const EnhancedPdfViewer: React.FC<EnhancedPdfViewerProps> = ({
  pdfPath,
  onPageCountChange,
  currentPrintingPage
}) => {
  const [previews, setPreviews] = useState<{ [page: number]: string }>({});
  const [isGenerating, setIsGenerating] = useState(false);
  const [pageCount, setPageCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  // PDF sayfa sayısını tahmin et (basit yaklaşım)
  const estimatePageCount = useCallback(async (path: string) => {
    try {
      // PDF dosyasını böl ve sayfa sayısını al
      const result = await window.api.splitPdf(path);
      if (result.success && result.pageCount) {
        return result.pageCount;
      }
      return 1; // Varsayılan
    } catch (err) {
      console.error('Sayfa sayısı tahmin hatası:', err);
      return 1;
    }
  }, []);

  // Önizleme oluştur
  const generatePreview = useCallback(async (pageNumber: number) => {
    if (!pdfPath) return;

    try {
      console.log(`[UI] Sayfa ${pageNumber} önizleme oluşturuluyor...`);
      const result = await window.api.generatePreview({
        pdfPath,
        pageNumber,
        width: 150,
        height: 200
      });

      console.log(`[UI] Önizleme sonucu:`, result);

      if (result.success && result.previewPath) {
        // Windows dosya yolu formatını düzelt
        const previewUrl = `file:///${result.previewPath.replace(/\\/g, '/')}`;
        console.log(`[UI] Önizleme URL: ${previewUrl}`);
        
        setPreviews(prev => ({
          ...prev,
          [pageNumber]: previewUrl
        }));
        
        console.log(`[UI] Sayfa ${pageNumber} önizleme eklendi`);
      } else {
        console.error(`[UI] Önizleme oluşturulamadı: ${result.error}`);
      }
    } catch (err) {
      console.error(`[UI] Sayfa ${pageNumber} önizleme hatası:`, err);
    }
  }, [pdfPath]);

  // PDF değiştiğinde önizlemeleri oluştur
  useEffect(() => {
    if (!pdfPath) {
      setPreviews({});
      setPageCount(0);
      setError(null);
      return;
    }

    const loadPdf = async () => {
      setIsGenerating(true);
      setError(null);

      try {
        // Sayfa sayısını tahmin et
        const estimatedPages = await estimatePageCount(pdfPath);
        setPageCount(estimatedPages);
        onPageCountChange(estimatedPages);

        // Tüm sayfalar için önizleme oluştur
        const previewPromises = [];
        for (let i = 1; i <= estimatedPages; i++) {
          previewPromises.push(generatePreview(i));
        }

        await Promise.all(previewPromises);
      } catch (err) {
        setError('PDF yükleme hatası: ' + (err as Error).message);
      } finally {
        setIsGenerating(false);
      }
    };

    loadPdf();
  }, [pdfPath, estimatePageCount, generatePreview, onPageCountChange]);

  if (!pdfPath) {
    return (
      <div className="pdf-viewer-empty">
        <div className="empty-state">
          <h3>PDF Seçin</h3>
          <p>Yazdırmak istediğiniz PDF dosyasını seçin</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="pdf-viewer-error">
        <div className="error-state">
          <h3>Hata</h3>
          <p>{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="pdf-viewer">
      <div className="pdf-viewer-header">
        <h3>PDF Önizleme ({pageCount} sayfa)</h3>
        {isGenerating && (
          <div className="generating-indicator">
            <span>Önizlemeler oluşturuluyor...</span>
          </div>
        )}
      </div>

      <div className="pdf-preview-grid">
        {Array.from({ length: pageCount }, (_, i) => {
          const pageNumber = i + 1;
          const previewPath = previews[pageNumber];
          const isCurrentPage = currentPrintingPage === pageNumber;

          return (
            <div
              key={pageNumber}
              className={`pdf-page-preview ${isCurrentPage ? 'current-page' : ''}`}
            >
              <div className="page-number">{pageNumber}</div>
              {previewPath ? (
                <img
                  src={`file:///${previewPath.replace(/\\/g, '/')}`}
                  alt={`Sayfa ${pageNumber}`}
                  className="page-thumbnail"
                  onError={(e) => {
                    console.error(`[UI] Görsel yüklenemedi: ${previewPath}`);
                    e.currentTarget.style.display = 'none';
                  }}
                  onLoad={() => {
                    console.log(`[UI] Görsel yüklendi: ${previewPath}`);
                  }}
                />
              ) : (
                <div className="page-placeholder">
                  {isGenerating ? 'Yükleniyor...' : 'Önizleme yok'}
                </div>
              )}
              {isCurrentPage && (
                <div className="current-page-indicator">
                  <span>Yazdırılıyor</span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};