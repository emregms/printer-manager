# Samsung CLP300 Yazıcı Yöneticisi (macOS)

Samsung CLP300 model lazer yazıcılar için özel geliştirilmiş native macOS yazdırma yönetim uygulaması. Bu uygulama, yazıcının belt ünitesinin her sayfadan sonra temizlenmesini sağlayarak, art arda yapılan baskılarda lekeli çıktı sorununu çözer.

## ✨ Özellikler

- **Sayfa Sayfa Yazdırma**: Her sayfayı ayrı bir yazdırma işi olarak gönderir
- **Özelleştirilebilir Bekleme Süreleri**: Yazdırma ve temizleme süreleri ayarlanabilir
- **Çift Yönlü Yazdırma Desteği**: Önce tek sayfalar, sonra çift sayfalar yazdırılır
- **PDF Görüntüleyici**: PDF dosyalarını önizleme ve sayfa sayısını otomatik tespit etme
- **Yazıcı Seçimi**: macOS'ta yüklü olan yazıcılar arasından seçim yapabilme
- **Apple Silicon Optimized**: M1/M2/M3 işlemciler için native ARM64 desteği

## 📋 Gereksinimler

- macOS 13.0 (Ventura) veya üzeri
- Xcode 15.0 veya üzeri

## 🚀 Kurulum

### Geliştirici için

```bash
# Projeyi klonlayın
git clone https://github.com/emregms/printer-manager.git
cd printer-manager

# Xcode ile açın
open PrinterManager.xcodeproj
```

### Kullanıcı için

1. Releases sayfasından en son sürümü indirin
2. `.dmg` dosyasını açın ve uygulamayı Applications klasörüne sürükleyin
3. Uygulamayı başlatın

## 📖 Kullanım

1. Uygulamayı başlatın
2. Yazıcı ayarlarından Samsung CLP300 yazıcınızı seçin
3. Yazdırma ve temizleme sürelerini ayarlayın
4. "PDF Seç" butonuna tıklayarak yazdırmak istediğiniz PDF dosyasını seçin
5. Çift yönlü yazdırma istiyorsanız ilgili seçeneği işaretleyin
6. "Yazdırmayı Başlat" butonuna tıklayın
7. Çift yönlü yazdırma seçiliyse, tek sayfalar yazdırıldıktan sonra kağıtları çevirmeniz istenecektir

## 📁 Proje Yapısı

```
PrinterManager/
├── App/
│   └── PrinterManagerApp.swift    # Ana uygulama giriş noktası
├── Views/
│   ├── ContentView.swift          # Ana görünüm
│   ├── SettingsView.swift         # Ayarlar paneli
│   ├── PDFPreviewView.swift       # PDF önizleme
│   └── PrintProgressView.swift    # Yazdırma durumu
├── Services/
│   ├── PDFProcessor.swift         # PDF işleme servisi
│   ├── PrinterService.swift       # Yazıcı entegrasyonu
│   └── PrintManager.swift         # Ana yazdırma yöneticisi
├── Models/
│   └── Settings.swift             # Ayar modeli
└── Resources/
    └── Assets.xcassets            # Uygulama ikonları ve görseller
```

## 🛠 Dağıtım

```bash
# Release build oluşturma
xcodebuild -scheme PrinterManager -configuration Release -archivePath build/PrinterManager.xcarchive archive
```

## 📄 Lisans

MIT
