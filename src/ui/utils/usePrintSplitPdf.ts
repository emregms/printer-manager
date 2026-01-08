import { useState, useCallback, useRef } from 'react';

export interface PrintSettings {
  printerName: string;
  printMs: number;
  cleanMs: number;
  duplex: boolean;
}

export interface PrintStatus {
  isPrinting: boolean;
  currentPage: number | null;
  timeRemaining: number;
  isCleaningPhase: boolean;
  logs: string[];
  error: string | null;
}

export const usePrintSplitPdf = (config: {
  pdfPath: string | null;
  settings: PrintSettings;
  totalPages: number;
}) => {
  const [status, setStatus] = useState<PrintStatus>({
    isPrinting: false,
    currentPage: null,
    timeRemaining: 0,
    isCleaningPhase: false,
    logs: [],
    error: null
  });

  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const isCancelledRef = useRef(false);

  const addLog = useCallback((message: string) => {
    setStatus(prev => ({
      ...prev,
      logs: [...prev.logs, `${new Date().toLocaleTimeString()}: ${message}`]
    }));
  }, []);

  const startPrinting = useCallback(async (pageCount: number, isSecondPass = false) => {
    if (!config.pdfPath || !config.settings.printerName) {
      addLog('PDF veya yazıcı seçilmemiş');
      return;
    }

    isCancelledRef.current = false;
    setStatus(prev => ({
      ...prev,
      isPrinting: true,
      currentPage: null,
      timeRemaining: 0,
      isCleaningPhase: false,
      error: null
    }));

    try {
      // PDF'i böl
      addLog('PDF sayfalara bölünüyor...');
      const splitResult = await window.api.splitPdf(config.pdfPath);
      
      if (!splitResult.success) {
        throw new Error(splitResult.error || 'PDF bölme hatası');
      }

      const pages = splitResult.pages || [];
      addLog(`${pages.length} sayfa hazırlandı`);

      // Sayfa sırasını belirle
      let pagesToPrint: number[];
      if (config.settings.duplex && !isSecondPass) {
        // İlk geçiş: tek sayfalar
        pagesToPrint = Array.from({ length: pageCount }, (_, i) => i + 1).filter(n => n % 2 === 1);
        addLog(`Çift yönlü yazdırma - İlk geçiş: ${pagesToPrint.length} sayfa`);
      } else if (config.settings.duplex && isSecondPass) {
        // İkinci geçiş: çift sayfalar
        pagesToPrint = Array.from({ length: pageCount }, (_, i) => i + 1).filter(n => n % 2 === 0);
        addLog(`Çift yönlü yazdırma - İkinci geçiş: ${pagesToPrint.length} sayfa`);
      } else {
        // Tek yönlü: tüm sayfalar
        pagesToPrint = Array.from({ length: pageCount }, (_, i) => i + 1);
        addLog(`Tek yönlü yazdırma: ${pagesToPrint.length} sayfa`);
      }

      // Her sayfayı yazdır
      for (let i = 0; i < pagesToPrint.length; i++) {
        if (isCancelledRef.current) {
          addLog('Yazdırma iptal edildi');
          break;
        }

        const pageNumber = pagesToPrint[i];
        const pdfPath = pages[pageNumber - 1];

        if (!pdfPath) {
          addLog(`Sayfa ${pageNumber} PDF dosyası bulunamadı`);
          continue;
        }

        setStatus(prev => ({
          ...prev,
          currentPage: pageNumber,
          timeRemaining: config.settings.printMs,
          isCleaningPhase: false
        }));

        addLog(`Sayfa ${pageNumber} yazdırılıyor...`);

        // Yazdırma süresini bekle
        await new Promise(resolve => {
          const startTime = Date.now();
          intervalRef.current = setInterval(() => {
            const elapsed = Date.now() - startTime;
            const remaining = Math.max(0, config.settings.printMs - elapsed);
            
            setStatus(prev => ({
              ...prev,
              timeRemaining: remaining
            }));

            if (remaining === 0 || isCancelledRef.current) {
              clearInterval(intervalRef.current!);
              resolve(void 0);
            }
          }, 100);
        });

        if (isCancelledRef.current) break;

        // PDF'i yazdır
        const printResult = await window.api.printPdf({
          pdfPath,
          printerName: config.settings.printerName,
          pageNumber,
          isFirstPage: i === 0
        });

        if (!printResult.ok) {
          throw new Error(printResult.error || 'Yazdırma hatası');
        }

        addLog(`Sayfa ${pageNumber} yazdırma tamamlandı`);

        // Temizlik süresini bekle
        if (i < pagesToPrint.length - 1) { // Son sayfa değilse
          setStatus(prev => ({
            ...prev,
            timeRemaining: config.settings.cleanMs,
            isCleaningPhase: true
          }));

          addLog(`Belt temizleme bekleniyor... (${config.settings.cleanMs / 1000}s)`);

          await new Promise(resolve => {
            const startTime = Date.now();
            intervalRef.current = setInterval(() => {
              const elapsed = Date.now() - startTime;
              const remaining = Math.max(0, config.settings.cleanMs - elapsed);
              
              setStatus(prev => ({
                ...prev,
                timeRemaining: remaining
              }));

              if (remaining === 0 || isCancelledRef.current) {
                clearInterval(intervalRef.current!);
                resolve(void 0);
              }
            }, 100);
          });

          if (isCancelledRef.current) break;
        }
      }

      // Çift yönlü yazdırma için ikinci geçiş kontrolü
      if (config.settings.duplex && !isSecondPass && !isCancelledRef.current) {
        setStatus(prev => ({
          ...prev,
          error: 'FLIP_PAGES_DIALOG'
        }));
        return;
      }

      if (!isCancelledRef.current) {
        addLog('Tüm sayfalar yazdırıldı');
      }

    } catch (error) {
      addLog(`Hata: ${(error as Error).message}`);
      setStatus(prev => ({
        ...prev,
        error: (error as Error).message
      }));
    } finally {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
      setStatus(prev => ({
        ...prev,
        isPrinting: false,
        currentPage: null,
        timeRemaining: 0,
        isCleaningPhase: false
      }));
    }
  }, [config.pdfPath, config.settings, addLog]);

  const cancelPrinting = useCallback(() => {
    isCancelledRef.current = true;
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }
    addLog('Yazdırma iptal ediliyor...');
  }, [addLog]);

  return {
    status,
    startPrinting,
    cancelPrinting,
    addLog
  };
};