# Samsung CLP300 Yazıcı Yöneticisi

Samsung CLP300 model lazer yazıcılar için özel geliştirilmiş bir yazdırma yönetim uygulaması. Bu uygulama, yazıcının belt ünitesinin her sayfadan sonra temizlenmesini sağlayarak, art arda yapılan baskılarda lekeli çıktı sorununu çözer.

## Özellikler

- **Sayfa Sayfa Yazdırma**: Her sayfayı ayrı bir yazdırma işi olarak gönderir
- **Özelleştirilebilir Bekleme Süreleri**: Yazdırma ve temizleme süreleri ayarlanabilir
- **Çift Yönlü Yazdırma Desteği**: Önce tek sayfalar, sonra çift sayfalar yazdırılır
- **PDF Görüntüleyici**: PDF dosyalarını önizleme ve sayfa sayısını otomatik tespit etme
- **Yazıcı Seçimi**: Windows'ta yüklü olan yazıcılar arasından seçim yapabilme

## Kurulum

1. Releases sayfasından en son sürümü indirin
2. İndirilen kurulum dosyasını çalıştırın
3. Kurulum tamamlandıktan sonra uygulamayı başlatın

## Kullanım

1. Yazıcı ayarlarından Samsung CLP300 yazıcınızı seçin
2. Yazdırma ve temizleme sürelerini ayarlayın
3. "PDF Seç" butonuna tıklayarak yazdırmak istediğiniz PDF dosyasını seçin
4. Çift yönlü yazdırma istiyorsanız ilgili seçeneği işaretleyin
5. "Yazdırmayı Başlat" butonuna tıklayın
6. Çift yönlü yazdırma seçiliyse, tek sayfalar yazdırıldıktan sonra kağıtları çevirmeniz istenecektir

## Geliştirme

### Gereksinimler

- Node.js 18 veya üzeri
- npm 8 veya üzeri

### Kurulum

```bash
# Projeyi klonlayın
git clone https://github.com/kullaniciadi/samsung-clp300-printer-manager.git
cd samsung-clp300-printer-manager

# Bağımlılıkları yükleyin
npm install

# Geliştirme modunda çalıştırın
npm run dev
```

### Dağıtım

```bash
# Windows için exe oluşturma
npm run build
npm run dist
```

## Lisans

MIT

