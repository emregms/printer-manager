import { useState, useEffect, useRef } from 'react';

// PDF sayfa sayısını varsayılan olarak al veya kullanıcı girdisini kullan
export const useNativePdf = (pdfPath: string | null, manualPageCount?: number) => {
  // Varsayılan değer veya kullanıcı girdisi - varsayılan olarak 1 sayfa
  const defaultCount = manualPageCount && manualPageCount > 0 ? manualPageCount : 1;
  
  // State'ler
  const [pageCount, setPageCount] = useState<number>(defaultCount);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  
  // İşlenmiş PDF yolu - sonsuz döngü sorununu çözmek için
  const processedPaths = useRef<Set<string>>(new Set());
  
  // PDF dosyası değiştiğinde SADECE BİR KEZ sayfa sayısını al
  useEffect(() => {
    // Async fonksiyon içinde işlem yapalım
    const getPdfPageCount = async () => {
      // PDF yoksa sıfırla
      if (!pdfPath) {
        setPageCount(0);
        setError(null);
        return;
      }
      
      // Bu dosya daha önce işlendiyse tekrar işleme
      if (processedPaths.current.has(pdfPath)) {
        return;
      }
      
      // İşleniyor olarak işaretle
      processedPaths.current.add(pdfPath);
      
      setLoading(true);
      setError(null);
      
      // Sayfa sayısı için manuel değeri kullan
      if (manualPageCount && manualPageCount > 0) {
        console.log(`Manuel sayfa sayısı kullanılıyor: ${manualPageCount}`);
        setPageCount(manualPageCount);
        setLoading(false);
        return;
      }
      
      // Ana işlemciden PDF bilgisini ve sayfa sayısını al
      try {
        // PDF bilgilerini al
        const pdfInfo = await window.api.getPdfInfo(pdfPath);
        
        // PDF'i böl ve sayfa sayısını al
        const splitResult = await window.api.splitPdf(pdfPath);
        
        if (splitResult.success && splitResult.pageCount) {
          console.log(`PDF sayfa sayısı tespit edildi: ${splitResult.pageCount}`);
          setPageCount(splitResult.pageCount);
        } else {
          console.log(`PDF sayfa sayısı tespit edilemedi, varsayılan kullanılıyor: ${defaultCount}`);
          setPageCount(defaultCount);
        }
      } catch (error) {
        console.error('PDF bilgisi alma hatası:', error);
        setPageCount(defaultCount);
        setError(`PDF işleme hatası: ${(error as Error).message}`);
      } finally {
        setLoading(false);
      }
    };
    
    // Async fonksiyonu çağır
    getPdfPageCount();
    
  }, [pdfPath, manualPageCount, defaultCount]);
  
  return { pageCount, loading, error };
};