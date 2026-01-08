import React, { useState, useEffect, useRef, useMemo } from 'react';
import { PrintProgress } from './PrintProgress';

interface PrintManagerProps {
  isPrinting: boolean;
  totalPages: number;
  currentPage: number | null;
  isDuplex: boolean;
  mode: 'cold' | 'hot';
  printMs: number;
  cleanMs: number;
  onComplete?: () => void;
}

export const PrintManager: React.FC<PrintManagerProps> = ({
  isPrinting,
  totalPages,
  currentPage,
  isDuplex,
  mode,
  printMs,
  cleanMs,
  onComplete
}) => {
  const [timeRemaining, setTimeRemaining] = useState<number>(0);
  const [isCleaningPhase, setIsCleaningPhase] = useState<boolean>(false);
  const [completedPages, setCompletedPages] = useState<number[]>([]);
  const timerRef = useRef<NodeJS.Timeout | null>(null);
  
  // Toplam işlem süresini hesapla
  const totalTime = printMs + cleanMs;
  
  // Hangi sayfada olduğumuzu hesaplayalım (çift yönlü yazdırmada)
  const currentPhase = currentPage && isDuplex && currentPage > Math.ceil(totalPages / 2) ? 'back' : 'front';
  
  // Yazdırılan sayfaları takip et
  useEffect(() => {
    // Bileşenin mount durumunu takip etmek için flag kullan
    let isMounted = true;
    
    if (!isPrinting && currentPage === null) {
      // Yazdırma durduysa sayfaları sıfırla
      if (isMounted) setCompletedPages([]);
    } else if (currentPage !== null && !completedPages.includes(currentPage) && timeRemaining === 0) {
      // Sayfa yazdırma işlemi bitti, tamamlananlar listesine ekle
      if (isMounted) setCompletedPages(prev => [...prev, currentPage]);
    }
    
    // Cleanup fonksiyonu
    return () => {
      isMounted = false;
    };
  }, [isPrinting, currentPage, timeRemaining, completedPages]);

  // Yazdırma durumunu takip et ve geri sayımı yönet
  useEffect(() => {
    // Bileşenin mount durumunu takip etmek için flag kullan
    let isMounted = true;
    
    if (!isPrinting || !currentPage) {
      // Yazdırma durmuşsa timer'ı temizle
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      if (isMounted) {
        setTimeRemaining(0);
        setIsCleaningPhase(false);
      }
      return;
    }
    
    // Yazdırma başladığında
    if (isMounted) {
      setTimeRemaining(totalTime);
      setIsCleaningPhase(false);
    }
    
    // Timer başlat
    timerRef.current = setInterval(() => {
      if (isMounted) {
        setTimeRemaining(prev => {
          const newTime = prev - 100;
          
          // Temizlik aşamasını kontrol et
          if (newTime <= cleanMs && !isCleaningPhase && isMounted) {
            setIsCleaningPhase(true);
          }
          
          // Geri sayım tamamlandı
          if (newTime <= 0) {
            if (timerRef.current) clearInterval(timerRef.current);
            return 0;
          }
          
          return newTime;
        });
      }
    }, 100);
    
    // Cleanup fonksiyonu
    return () => {
      isMounted = false;
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [isPrinting, currentPage, printMs, cleanMs, totalTime, isCleaningPhase]);

  // İlerleme çubuğu yüzdesini hesapla
  const progressPercentage = timeRemaining > 0 ? Math.max(0, Math.min(100, ((totalTime - timeRemaining) / totalTime) * 100)) : 0;
  
  // Kalan süreyi formatlama
  const formatTime = (ms: number) => {
    const seconds = Math.ceil(ms / 1000);
    return `${seconds} sn`;
  };
  
  // Toplam tahmini süre
  const estimatedTotalTime = useMemo(() => {
    if (!isPrinting) return 0;
    
    const remainingPages = totalPages - (currentPage || 0) - completedPages.length;
    if (remainingPages <= 0) return 0;
    
    return remainingPages * totalTime;
  }, [isPrinting, totalPages, currentPage, totalTime, completedPages.length]);
  
  // Toplam tahmini süreyi formatla
  const formatEstimatedTime = (ms: number) => {
    if (ms === 0) return '-';
    const minutes = Math.floor(ms / (1000 * 60));
    const seconds = Math.floor((ms % (1000 * 60)) / 1000);
    return minutes > 0 ? `${minutes} dk ${seconds} sn` : `${seconds} sn`;
  };

  return (
    <div className="print-manager">
      <div className="card-header">
        <h3 className="card-title">Yazdırma Durumu</h3>
      </div>
      
      {isPrinting ? (
        <>
          <div style={{ marginBottom: '12px' }}>
            <div className="print-status">
              <span>
                {isCleaningPhase ? 'Belt temizleme' : 'Sayfa yazdırılıyor'}
                {isDuplex && ` (${currentPhase === 'front' ? 'Ön yüzler' : 'Arka yüzler'})`}
              </span>
              <span>{currentPage}/{isDuplex ? Math.ceil(totalPages / 2) * 2 : totalPages}</span>
            </div>
            <div className="progress-bar">
              <div className={`progress-bar-fill ${isCleaningPhase ? 'progress-bar-fill-cleaning' : ''}`} style={{ width: `${progressPercentage}%` }}></div>
            </div>
          </div>
          
          <div className="print-info">
            <div>
              <strong>Mod:</strong> {mode === 'cold' ? 'Soğuk' : 'Sıcak'}
            </div>
            <div>
              <strong>Kalan süre:</strong> {formatTime(timeRemaining)}
            </div>
            <div>
              <strong>Tahmini bitiş:</strong> {formatEstimatedTime(estimatedTotalTime)}
            </div>
          </div>
          
          <div style={{ marginTop: '20px' }}>
            <PrintProgress
              isPrinting={isPrinting}
              totalPages={totalPages}
              currentPage={currentPage}
              isDuplex={isDuplex}
              printMs={printMs}
              cleanMs={cleanMs}
              completedPages={completedPages}
            />
          </div>
        </>
      ) : (
        <>
          <div style={{ textAlign: 'center', padding: '12px 0' }}>
            {totalPages > 0 ? 'Yazdırmaya hazır' : 'PDF seçilmedi'}
          </div>
          {totalPages > 0 && (
            <div style={{ marginTop: '20px' }}>
              <PrintProgress
                isPrinting={false}
                totalPages={totalPages}
                currentPage={null}
                isDuplex={isDuplex}
                printMs={printMs}
                cleanMs={cleanMs}
                completedPages={[]}
              />
            </div>
          )}
        </>
      )}
    </div>
  );
};
