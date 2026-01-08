import React, { useState, useEffect, useMemo } from 'react';
import { PrintPage } from './PrintPage';

interface PrintProgressProps {
  isPrinting: boolean;
  totalPages: number;
  currentPage: number | null;
  isDuplex: boolean;
  printMs: number;
  cleanMs: number;
  completedPages: number[];
}

export const PrintProgress: React.FC<PrintProgressProps> = ({
  isPrinting,
  totalPages,
  currentPage,
  isDuplex,
  printMs,
  cleanMs,
  completedPages = [],
}) => {
  const [timeRemaining, setTimeRemaining] = useState<number>(0);
  const [isCleaningPhase, setIsCleaningPhase] = useState<boolean>(false);
  
  // Toplam işlem süresi
  const totalTime = useMemo(() => printMs + cleanMs, [printMs, cleanMs]);
  
  // Tüm sayfaların durumunu hesapla
  const pages = useMemo(() => {
    const result = [];
    const pagesToProcess = isDuplex
      ? Math.ceil(totalPages / 2) // Çift yönlü baskıda işlenmesi gereken sayfa sayısı
      : totalPages;
    
    for (let i = 0; i < pagesToProcess; i++) {
      const pageNumber = i + 1;
      const isCurrent = currentPage === pageNumber;
      let status: 'pending' | 'printing' | 'cleaning' | 'completed' = 'pending';
      
      if (completedPages.includes(pageNumber)) {
        status = 'completed';
      } else if (isCurrent) {
        status = isCleaningPhase ? 'cleaning' : 'printing';
      } else if (pageNumber > (currentPage || 0)) {
        status = 'pending';
      }
      
      result.push({ pageNumber, isCurrent, status });
    }
    
    // Çift yönlü baskıda arka sayfalar
    if (isDuplex) {
      const frontPageCount = Math.ceil(totalPages / 2);
      for (let i = 0; i < Math.floor(totalPages / 2); i++) {
        const pageNumber = frontPageCount + i + 1;
        const actualPageNumber = (i + 1) * 2; // Çift sayılı sayfalar (2, 4, 6...)
        const isCurrent = currentPage === actualPageNumber;
        let status: 'pending' | 'printing' | 'cleaning' | 'completed' = 'pending';
        
        if (completedPages.includes(actualPageNumber)) {
          status = 'completed';
        } else if (isCurrent) {
          status = isCleaningPhase ? 'cleaning' : 'printing';
        } else if (actualPageNumber > (currentPage || 0)) {
          status = 'pending';
        }
        
        result.push({ pageNumber, isCurrent, status, isBackPage: true });
      }
    }
    
    return result;
  }, [totalPages, currentPage, isDuplex, completedPages, isCleaningPhase]);
  
  // Yazdırma sırasında geri sayım
  useEffect(() => {
    // Bileşenin mount durumunu takip etmek için flag kullan
    let isMounted = true;
    
    if (!isPrinting || !currentPage) {
      if (isMounted) {
        if (timeRemaining !== 0) setTimeRemaining(0);
        if (isCleaningPhase) setIsCleaningPhase(false);
      }
      return;
    }
    
    // Yeni yazdırma işlemi başladığında
    if (isMounted) {
      setTimeRemaining(totalTime);
      setIsCleaningPhase(false);
    }
    
    const interval = setInterval(() => {
      if (isMounted) {
        setTimeRemaining(prev => {
          const newTime = prev - 100;
          
          // Temizlik aşamasını kontrol et
          if (newTime <= cleanMs && !isCleaningPhase && isMounted) {
            setIsCleaningPhase(true);
          }
          
          return Math.max(0, newTime);
        });
      }
    }, 100);
    
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, [isPrinting, currentPage, printMs, cleanMs, totalTime, isCleaningPhase]);
  
  return (
    <div>
      <div style={{
        display: 'flex',
        flexWrap: 'wrap',
        gap: '16px',
        justifyContent: 'center',
        padding: '12px 0'
      }}>
        {pages.map(page => (
          <PrintPage
            key={page.pageNumber}
            pageNumber={page.pageNumber}
            isActive={page.isCurrent || completedPages.includes(page.pageNumber)}
            status={page.status}
            timeRemaining={page.isCurrent ? timeRemaining : 0}
            totalTime={totalTime}
          />
        ))}
      </div>
      
      {isDuplex && (
        <div style={{ 
          margin: '8px 0',
          padding: '8px', 
          backgroundColor: '#fffde7', 
          border: '1px solid #fff9c4', 
          borderRadius: '4px',
          fontSize: '14px'
        }}>
          <strong>Çift yönlü baskı modu:</strong> Önce tek sayfalar, sonra çift sayfalar yazdırılacak.
        </div>
      )}
    </div>
  );
};
