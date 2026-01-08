/**
 * PDF dosyasının sayfa sayısını hesaplamak için basit bir yardımcı fonksiyon
 * Bu fonksiyon browser tarafında çalışır ve PDF sayfa sayısını saymak için
 * browser'ın kendi PDF görüntüleme özelliklerini kullanır
 */
export async function countPdfPages(pdfPath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    try {
      // PDF dosyasını yüklemek için bir iframe oluştur
      const iframe = document.createElement('iframe');
      iframe.style.display = 'none'; // Görünmez yap
      
      // PDF yükleme olayını dinle
      iframe.onload = () => {
        try {
          // iframe içindeki pencereye erişim
          const iframeWindow = iframe.contentWindow;
          
          if (!iframeWindow) {
            reject(new Error('iframe pencere nesnesine erişilemedi'));
            document.body.removeChild(iframe);
            return;
          }
          
          // PDF yüklendikten sonra sayfa sayısını almaya çalış
          // Bu 300ms beklemeli, çünkü PDF'in tamamen yüklenmesi gerekiyor
          setTimeout(() => {
            try {
              // Farklı tarayıcılar farklı PDF görüntüleyici API'leri kullanır
              // Bu bilgi doğrudan PDF izleyicisinden erişilebilir
              const pdfViewer = iframeWindow.document.querySelector('embed[type="application/pdf"]');
              
              if (pdfViewer && 'pagesCount' in pdfViewer) {
                // Chrome/Edge yöntemi
                resolve((pdfViewer as any).pagesCount || 1);
              } else {
                // Diğer tarayıcılar için 1 varsayalım
                resolve(1);
              }
              
              // iframe'i kaldır
              document.body.removeChild(iframe);
            } catch (err) {
              console.error('PDF sayfa sayısı tespiti hatası:', err);
              resolve(1); // Hata durumunda 1 sayfa varsay
              
              // iframe'i kaldır
              document.body.removeChild(iframe);
            }
          }, 300);
        } catch (err) {
          console.error('iframe içerik erişim hatası:', err);
          reject(err);
          
          // iframe'i kaldır
          document.body.removeChild(iframe);
        }
      };
      
      // Yükleme hatası
      iframe.onerror = (err) => {
        console.error('PDF yükleme hatası:', err);
        reject(new Error('PDF yüklenemedi'));
        
        // iframe'i kaldır
        document.body.removeChild(iframe);
      };
      
      // PDF yolunu ayarla ve iframe'i belgeye ekle
      iframe.src = `file://${pdfPath}`;
      document.body.appendChild(iframe);
    } catch (err) {
      console.error('PDF sayfa sayma hatası:', err);
      reject(err);
    }
  });
}

