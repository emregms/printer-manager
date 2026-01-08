import { useState, useEffect, useCallback } from 'react';

export interface PrintSettings {
  printerName: string;
  mode: 'cold' | 'hot';
  printMs: number;
  cleanMs: number;
  duplex: boolean;
}

export interface PrintStatus {
  isPrinting: boolean;
  currentPage: number | null;
  totalPages: number;
  completedPages: number[];
  isCleaningPhase: boolean;
  timeRemaining: number;
  error: string | null;
  logs: string[];
}

export interface PrintManagerProps {
  pdfPath: string | null;
  settings: PrintSettings;
}

export const usePrintManager = ({ pdfPath, settings }: PrintManagerProps) => {
  // Yazdırma durumu
  const [status, setStatus] = useState<PrintStatus>({
    isPrinting: false,
    currentPage: null,
    totalPages: 0,
    completedPages: [],
    isCleaningPhase: false,
    timeRemaining: 0,
    error: null,
    logs: [],
  });

  // Timer referansı
  const timerRef = { current: null as any };

  // Logları ekle
  const addLog = useCallback((message: string) => {
    const timestamp = new Date().toLocaleTimeString();
    setStatus(prev => ({
      ...prev,
      logs: [...prev.logs, `[${timestamp}] ${message}`]
    }));
  }, []);

  // Yazdırma başlat
  const startPrinting = useCallback(async (totalPages: number) => {
    if (!pdfPath || !settings.printerName) {
      addLog('PDF dosyası veya yazıcı seçilmedi');
      return;
    }

    try {
      // Yazdırma durumunu başlat
      setStatus(prev => ({
        ...prev,
        isPrinting: true,
        totalPages,
        currentPage: null,
        completedPages: [],
        logs: [], // Logları sıfırla
        error: null
      }));

      addLog(`Yazdırma başlatılıyor: ${totalPages} sayfa, ${settings.duplex ? 'çift yönlü' : 'tek yönlü'}, ${settings.mode} mod`);

      // Sayfaları hazırla
      let pagesToPrint: number[];
      
      if (settings.duplex) {
        // Çift yönlü yazdırmada önce tek sayılar
        const oddPages = Array.from({ length: totalPages }, (_, i) => i + 1).filter(n => n % 2 === 1);
        pagesToPrint = oddPages;
      } else {
        // Tek yönlü yazdırmada tüm sayfalar
        pagesToPrint = Array.from({ length: totalPages }, (_, i) => i + 1);
      }

      // Sayfa yazdırma işlemi
      for (let i = 0; i < pagesToPrint.length; i++) {
        const pageNumber = pagesToPrint[i];
        
        // Mevcut sayfayı ayarla
        setStatus(prev => ({ ...prev, currentPage: pageNumber }));
        
        addLog(`Sayfa ${pageNumber} yazdırılıyor...`);
        
        // Yazdırma işlemi
        try {
          const result = await window.api.printPdf({
            pdfPath,
            printerName: settings.printerName,
            pageNumbers: [pageNumber],
            silent: true
          });
          
          if (result.ok) {
            addLog(`Sayfa ${pageNumber} yazdırıldı`);
            
            // Tamamlanan sayfaları güncelle
            setStatus(prev => ({ ...prev, completedPages: [...prev.completedPages, pageNumber] }));
            
            // İlk sayfa dışındaki sayfalarda temizlik bekleme süresi ekle
            if (i > 0 || pagesToPrint.length === 1) {
              // Yazdırma süresini bekle
              addLog(`Yazdırma tamamlanıyor: ${settings.printMs / 1000} sn`);
              await new Promise<void>((resolve) => {
                setStatus(prev => ({ ...prev, timeRemaining: settings.printMs, isCleaningPhase: false }));
                
                // Geri sayım
                let remaining = settings.printMs;
                timerRef.current = setInterval(() => {
                  remaining -= 100;
                  setStatus(prev => ({ ...prev, timeRemaining: Math.max(0, remaining) }));
                  
                  if (remaining <= 0) {
                    clearInterval(timerRef.current);
                    resolve();
                  }
                }, 100);
              });
              
              // Belt temizleme süresini bekle
              addLog(`Belt temizleme: ${settings.cleanMs / 1000} sn`);
              await new Promise<void>((resolve) => {
                setStatus(prev => ({ ...prev, timeRemaining: settings.cleanMs, isCleaningPhase: true }));
                
                // Geri sayım
                let remaining = settings.cleanMs;
                timerRef.current = setInterval(() => {
                  remaining -= 100;
                  setStatus(prev => ({ ...prev, timeRemaining: Math.max(0, remaining) }));
                  
                  if (remaining <= 0) {
                    clearInterval(timerRef.current);
                    resolve();
                  }
                }, 100);
              });
            }
          } else {
            addLog(`Sayfa ${pageNumber} yazdırma hatası: ${result.error}`);
          }
        } catch (error) {
          addLog(`Yazdırma hatası: ${(error as Error).message}`);
          setStatus(prev => ({ ...prev, error: (error as Error).message }));
        }
      }
      
      // Çift yönlü yazdırma için arka yüzler
      if (settings.duplex && totalPages > 1) {
        addLog('Ön yüz yazdırma tamamlandı.');
        
        // Kullanıcıya bilgi ver
        window.alert('Ön yüzler tamam. Kağıtları çevirip tepsiyi yükleyin, ardından Tamam tuşuna basın.');
        
        // Çift sayılar (arka yüzler)
        const evenPages = Array.from({ length: totalPages }, (_, i) => i + 1).filter(n => n % 2 === 0);
        
        // Arka yüzleri yazdır
        for (let i = 0; i < evenPages.length; i++) {
          const pageNumber = evenPages[i];
          
          // Mevcut sayfayı ayarla
          setStatus(prev => ({ ...prev, currentPage: pageNumber }));
          
          addLog(`Arka yüz sayfa ${pageNumber} yazdırılıyor...`);
          
          // Yazdırma işlemi
          try {
            const result = await window.api.printPdf({
              pdfPath,
              printerName: settings.printerName,
              pageNumbers: [pageNumber],
              silent: true
            });
            
            if (result.ok) {
              addLog(`Arka yüz sayfa ${pageNumber} yazdırıldı`);
              
              // Tamamlanan sayfaları güncelle
              setStatus(prev => ({ ...prev, completedPages: [...prev.completedPages, pageNumber] }));
              
              // İlk arka sayfa dışındaki sayfalarda temizlik bekleme süresi ekle
              if (i > 0 || evenPages.length === 1) {
                // Yazdırma süresini bekle
                addLog(`Yazdırma tamamlanıyor: ${settings.printMs / 1000} sn`);
                await new Promise<void>((resolve) => {
                  setStatus(prev => ({ ...prev, timeRemaining: settings.printMs, isCleaningPhase: false }));
                  
                  // Geri sayım
                  let remaining = settings.printMs;
                  timerRef.current = setInterval(() => {
                    remaining -= 100;
                    setStatus(prev => ({ ...prev, timeRemaining: Math.max(0, remaining) }));
                    
                    if (remaining <= 0) {
                      clearInterval(timerRef.current);
                      resolve();
                    }
                  }, 100);
                });
                
                // Belt temizleme süresini bekle
                addLog(`Belt temizleme: ${settings.cleanMs / 1000} sn`);
                await new Promise<void>((resolve) => {
                  setStatus(prev => ({ ...prev, timeRemaining: settings.cleanMs, isCleaningPhase: true }));
                  
                  // Geri sayım
                  let remaining = settings.cleanMs;
                  timerRef.current = setInterval(() => {
                    remaining -= 100;
                    setStatus(prev => ({ ...prev, timeRemaining: Math.max(0, remaining) }));
                    
                    if (remaining <= 0) {
                      clearInterval(timerRef.current);
                      resolve();
                    }
                  }, 100);
                });
              }
            } else {
              addLog(`Arka yüz sayfa ${pageNumber} yazdırma hatası: ${result.error}`);
            }
          } catch (error) {
            addLog(`Yazdırma hatası: ${(error as Error).message}`);
            setStatus(prev => ({ ...prev, error: (error as Error).message }));
          }
        }
      }
      
      // Yazdırma işlemi tamamlandı
      addLog('Yazdırma işlemi tamamlandı!');
      
    } catch (error) {
      addLog(`Yazdırma işlemi başarısız: ${(error as Error).message}`);
      setStatus(prev => ({ ...prev, error: (error as Error).message }));
    } finally {
      // Timer'ı temizle
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
      
      // Yazdırma durumunu güncelle
      setStatus(prev => ({ 
        ...prev, 
        isPrinting: false, 
        currentPage: null,
        timeRemaining: 0,
        isCleaningPhase: false
      }));
    }
  }, [pdfPath, settings, addLog]);

  // Yazdırma işlemini iptal et
  const cancelPrinting = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
    }
    
    setStatus(prev => ({ 
      ...prev, 
      isPrinting: false, 
      currentPage: null,
      timeRemaining: 0,
      isCleaningPhase: false
    }));
    
    addLog('Yazdırma işlemi iptal edildi.');
  }, [addLog]);

  // Unmount olduğunda timer'ı temizle
  useEffect(() => {
    return () => {
      if (timerRef.current) {
        clearInterval(timerRef.current);
      }
    };
  }, []);

  return {
    status,
    startPrinting,
    cancelPrinting,
    addLog
  };
};

