import React, { useEffect, useState, useRef } from 'react';

interface SimplePdfViewerProps {
  pdfPath: string | null;
  onPageCountChange?: (count: number) => void;
  currentPrintingPage?: number | null;
  previewPageSize?: number;
  totalPages?: number;
}

export const SimplePdfViewer: React.FC<SimplePdfViewerProps> = ({
  pdfPath,
  onPageCountChange,
  currentPrintingPage = null,
  previewPageSize = 200,
  totalPages: propTotalPages
}) => {
  const [totalPages, setTotalPages] = useState<number>(propTotalPages || 0);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const pdfContainerRef = useRef<HTMLDivElement>(null);

  // PDF sayfa sayısını güncelle
  useEffect(() => {
    if (propTotalPages) {
      setTotalPages(propTotalPages);
    }
  }, [propTotalPages]);
  
  // PDF yolu değiştiğinde basit gösterimi güncelle
  useEffect(() => {
    if (!pdfPath) {
      setTotalPages(0);
      setError(null);
      return;
    }

    // Kısa bir yükleme gösterdikten sonra hazır durumuna geç
    setLoading(true);
    setError(null);
    
    setTimeout(() => {
      setLoading(false);
      // Sayfa sayısını güncelleme
      if (propTotalPages && propTotalPages > 0) {
        setTotalPages(propTotalPages);
      }
      
      // Kullanıcının girdiği sayfa sayısını kullan
      if (onPageCountChange && totalPages > 0) {
        onPageCountChange(totalPages);
      }
    }, 300);
  }, [pdfPath, onPageCountChange, propTotalPages, totalPages]);

  return (
    <div>
      {!pdfPath ? (
        <div style={{ padding: '20px', textAlign: 'center', backgroundColor: '#f8f8f8', borderRadius: '8px' }}>
          Henüz PDF seçilmedi
        </div>
      ) : loading ? (
        <div style={{ padding: '20px', textAlign: 'center', backgroundColor: '#f8f8f8', borderRadius: '8px' }}>
          PDF yükleniyor...
        </div>
      ) : error ? (
        <div style={{ padding: '20px', textAlign: 'center', backgroundColor: '#fff0f0', borderRadius: '8px', color: '#d32f2f' }}>
          {error}
        </div>
      ) : (
        <div>
          {/* PDF bilgisi */}
          <div style={{ 
            padding: '20px', 
            textAlign: 'center', 
            backgroundColor: '#f5f5f5', 
            borderRadius: '8px', 
            marginBottom: '16px',
            border: '1px solid #ddd'
          }}>
            <h3>PDF Bilgisi</h3>
            <p style={{ fontSize: '16px' }}>
              <strong>Dosya:</strong> {pdfPath.split('\\').pop()}
            </p>
            <p style={{ fontSize: '16px' }}>
              <strong>Toplam Sayfa Sayısı:</strong> {totalPages}
            </p>
            <div style={{ marginTop: '20px', fontSize: '14px', color: '#666' }}>
              PDF dosyası yüklendi ve yazdırmaya hazır.
            </div>
          </div>
          
          {/* Sayfa önizlemeler */}
          <div style={{ 
            marginTop: '16px', 
            display: 'flex', 
            flexWrap: 'wrap', 
            gap: '16px', 
            justifyContent: 'center',
            backgroundColor: '#fff',
            padding: '16px',
            borderRadius: '8px',
            border: '1px solid #eee'
          }}>
            {totalPages > 0 && [...Array(totalPages)].map((_, index) => {
              const pageNumber = index + 1;
              const isCurrentPage = currentPrintingPage === pageNumber;
              
              return (
                <div
                  key={pageNumber}
                  style={{
                    position: 'relative',
                    border: isCurrentPage ? '3px solid #4CAF50' : '1px solid #ddd',
                    borderRadius: '4px',
                    backgroundColor: isCurrentPage ? '#f0fff0' : '#fff',
                    padding: '8px',
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'center',
                    alignItems: 'center',
                    width: '120px',
                    height: '150px',
                    boxShadow: isCurrentPage ? '0 0 8px rgba(76, 175, 80, 0.7)' : '0 2px 4px rgba(0,0,0,0.1)',
                    transition: 'all 0.3s ease'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 'bold', marginBottom: '10px' }}>
                    Sayfa {pageNumber}
                  </div>
                  
                  <div style={{
                    width: '100px',
                    height: '120px',
                    display: 'flex',
                    justifyContent: 'center',
                    alignItems: 'center',
                    backgroundColor: '#f9f9f9',
                    border: '1px solid #eee',
                  }}>
                    <span style={{ fontSize: '30px', fontWeight: 'bold', color: '#aaa' }}>
                      {pageNumber}
                    </span>
                  </div>
                  
                  {isCurrentPage && (
                    <div style={{ 
                      position: 'absolute',
                      bottom: '-8px',
                      left: '50%',
                      transform: 'translateX(-50%)',
                      background: '#4CAF50',
                      color: 'white',
                      padding: '2px 8px',
                      borderRadius: '10px',
                      fontSize: '12px',
                      whiteSpace: 'nowrap',
                      fontWeight: 'bold',
                      boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
                    }}>
                      Yazdırılıyor
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
