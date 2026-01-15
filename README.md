# 🖨️ PrinterManager for macOS

Modern, native macOS uygulaması - **Lazer yazıcılardaki belt (transfer kayışı) yıpranma sorununu çözer**.

Çok sayfalı PDF'leri yazdırırken sayfalar arası bekleme süresi ayarlayarak, yazıcının transfer kayışının (belt) aşırı ısınmasını ve erken yıpranmasını önler. Özellikle **eski veya hassas lazer yazıcılar** için ideal bir çözümdür.

> 🧪 **Test:** Bu uygulama Samsung CLP-300 renkli lazer yazıcı ile test edilmiştir, ancak benzer sorun yaşayan tüm lazer yazıcılarda kullanılabilir.

---

## 📸 Ekran Görüntüleri

<p align="center">
  <img src="screenshots/3.png" alt="PDF Önizleme" width="800"/>
  <br/>
  <em>Çoklu sayfa önizleme ve yazdırma ayarları</em>
</p>

<p align="center">
  <img src="screenshots/1.png" alt="Yazdırma İşlemi" width="800"/>
  <br/>
  <em>Sayfa sayfa yazdırma ve ilerleme durumu</em>
</p>

<p align="center">
  <img src="screenshots/2.png" alt="Çift Yönlü Yazdırma" width="800"/>
  <br/>
  <em>Çift yönlü (duplex) yazdırma - kağıt çevirme uyarısı</em>
</p>

---

## ✨ Özellikler

| Özellik                               | Açıklama                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------- |
| ⏱️ **Ayarlanabilir Bekleme Süreleri** | Yazdırma ve temizlik süreleri slider ile ayarlanır                         |
| 📄 **Sayfa Sayfa Yazdırma**           | Her sayfa ayrı ayrı yazıcıya gönderilir                                    |
| 🔄 **Çift Yönlü (Duplex) Yazdırma**   | Tek sayfaları yazdır → Kağıtları çevir → Çift sayfaları ters sırada yazdır |
| 👁️ **PDF Önizleme**                   | Thumbnail grid ile tüm sayfaları görüntüle                                 |
| ⏸️ **Durdur/Devam Et**                | Yazdırmayı istediğiniz zaman duraklatıp devam ettirin                      |
| ⏰ **Tahmini Süre**                   | Kalan yazdırma süresini görün                                              |
| 🖤 **Siyah Beyaz Modu**               | Daha hızlı ve ekonomik yazdırma                                            |
| 🧹 **Otomatik Temizlik**              | Temp dosyaları otomatik silinir                                            |
| 🍎 **Native macOS**                   | Swift + SwiftUI ile Apple Silicon için optimize                            |

---

## 🖨️ Hangi Yazıcılar İçin?

Bu uygulama özellikle şu durumlarda faydalıdır:

- **Eski lazer yazıcılar** - Transfer kayışı (belt) yıpranma sorunu yaşayanlar
- **Renkli lazer yazıcılar** - Daha hassas mekanizmaya sahip modeller
- **Yüksek hacimli yazdırma** - Çok sayfalı dökümanları sık yazdıranlar
- **Isınma sorunu yaşayanlar** - Art arda yazdırmada kalite kaybı görenler

### Test Edilen Yazıcılar

| Yazıcı          | Durum         |
| --------------- | ------------- |
| Samsung CLP-300 | ✅ Tam uyumlu |

> 💡 Başka bir yazıcı ile test ettiyseniz lütfen issue açarak bildirin!

---

## 📋 Sistem Gereksinimleri

- **macOS:** 13.0 (Ventura) veya üzeri
- **İşlemci:** Intel veya Apple Silicon (M1/M2/M3)
- **Yazıcı:** CUPS uyumlu herhangi bir yazıcı

---

## 🚀 Kurulum

### Derlenmiş Uygulama

1. [Releases](../../releases) sayfasından `.dmg` dosyasını indirin
2. DMG'yi açın ve uygulamayı `/Applications` klasörüne sürükleyin
3. Uygulamayı çalıştırın

### Kaynak Koddan Derleme

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Xcode'da ⌘+R ile çalıştırın veya ⌘+B ile derleyin
```

---

## 📖 Kullanım

1. **Yazıcı Seçin** - Dropdown'dan yazıcınızı seçin
2. **Süreleri Ayarlayın**
   - 🖨️ **Yazdırma Süresi:** Her sayfa arasındaki bekleme (örn: 30 sn)
   - ✨ **Temizlik Süresi:** Belt temizliği için ek bekleme (örn: 8 sn)
3. **PDF Seçin** - "PDF Seç" butonu ile dosyanızı yükleyin
4. **Çift Yönlü (opsiyonel)** - Toggle ile aktif edin
5. **Yazdır** - Yazdırma başlar, ilerlemeyi izleyin

### Çift Yönlü Yazdırma

1. Uygulama önce tek sayfaları (1, 3, 5...) yazdırır
2. "Kağıtları Çeviriniz" uyarısı gelir
3. Kağıtları ters çevirip yazıcıya yükleyin
4. "Çevirdim, Devam Et" butonuna tıklayın
5. Çift sayfalar (6, 4, 2...) ters sırada yazdırılır

---

## 🔧 Teknik Detaylar

### Proje Yapısı

```
PrinterManager/
├── App/
│   └── PrinterManagerApp.swift    # Uygulama giriş noktası
├── Views/
│   ├── ContentView.swift          # Ana ekran
│   ├── SettingsView.swift         # Ayarlar paneli
│   ├── PDFPreviewView.swift       # PDF thumbnail grid
│   └── PrintProgressView.swift    # İlerleme durumu
├── Services/
│   ├── PrintManager.swift         # Yazdırma yönetimi
│   ├── PrinterService.swift       # CUPS entegrasyonu (lp komutu)
│   └── PDFProcessor.swift         # PDF işleme (PDFKit)
├── Models/
│   └── SettingsStore.swift        # Ayar kalıcılığı (UserDefaults)
└── Resources/
    └── Assets.xcassets/           # Uygulama ikonları
```

### Kullanılan Teknolojiler

- **Swift 5.9+**
- **SwiftUI** - Modern deklaratif UI
- **PDFKit** - Native PDF işleme
- **CUPS** - macOS yazdırma sistemi (`lp` komutu)
- **Combine** - Reaktif programlama

---

## 📄 Lisans

MIT License - Detaylar için [LICENSE](LICENSE) dosyasına bakın.

---

## 🤝 Katkıda Bulunma

Katkılarınız memnuniyetle karşılanır!

1. Fork yapın
2. Feature branch oluşturun (`git checkout -b feature/amazing-feature`)
3. Commit atın (`git commit -m 'feat: Add amazing feature'`)
4. Push yapın (`git push origin feature/amazing-feature`)
5. Pull Request açın

---

<p align="center">
  Made with ❤️ for macOS
</p>
