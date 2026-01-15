# PrinterManager for macOS 🖨️

<div align="center">

[![TR](https://img.shields.io/badge/lang-TR-red.svg)](README.md)
[![EN](https://img.shields.io/badge/lang-EN-blue.svg)](README_EN.md)

</div>

Lazer yazıcılardaki belt (transfer kayışı) yıpranma sorununu çözen native macOS uygulaması. Çok sayfalı PDF'leri yazdırırken sayfalar arası bekleme süresi ayarlayarak, yazıcının transfer kayışının aşırı ısınmasını önler.

> 🧪 **Test:** Samsung CLP-300 ile test edilmiştir, benzer sorun yaşayan tüm lazer yazıcılarda kullanılabilir.

![App Screenshot](screenshots/1.png)

## 📥 İndirme

**[⬇️ PrinterManager v1.0.0 DMG İndir](https://github.com/emregms/printer-manager/releases/download/v1.0.0/PrinterManager-v1.0.0.dmg)**

### ⚠️ İlk Açılışta macOS Uyarısı

macOS imzasız uygulamaları engeller. Uygulamayı açmak için:

**Yöntem 1 - Terminal (Önerilen):**

```bash
xattr -cr /Applications/PrinterManager.app
```

**Yöntem 2 - Manuel:**

1. Uygulamaya **sağ tıklayın** (veya Control+tıklama)
2. **"Aç"** seçeneğini tıklayın
3. Açılan pencerede tekrar **"Aç"** butonuna tıklayın

## Özellikler

- **Ayarlanabilir Bekleme Süreleri**: Yazdırma ve temizlik süreleri slider ile ayarlanır
- **Sayfa Sayfa Yazdırma**: Her sayfa ayrı ayrı yazıcıya gönderilir
- **Çift Yönlü Yazdırma**: Tek → Çevir → Çift sayfalar ters sırada
- **PDF Önizleme**: Thumbnail grid ile tüm sayfaları görüntüle
- **Durdur/Devam**: Yazdırmayı duraklatıp devam ettirin
- **Tahmini Süre**: Kalan yazdırma süresini görün
- **Siyah Beyaz Modu**: Daha hızlı ve ekonomik yazdırma
- **Native macOS**: Swift + SwiftUI, Apple Silicon optimize

## Ekran Görüntüleri

<p align="center">
  <img src="screenshots/2.png" alt="Yazdırma İşlemi" width="800"/>
  <br/>
  <em>Sayfa sayfa yazdırma ve ilerleme durumu</em>
</p>

<p align="center">
  <img src="screenshots/3.png" alt="Çift Yönlü Yazdırma" width="800"/>
  <br/>
  <em>Çift yönlü yazdırma - kağıt çevirme uyarısı</em>
</p>

## Gereksinimler

- macOS 13.0 (Ventura) veya üzeri
- Intel veya Apple Silicon (M1/M2/M3)

## Kullanım

1. **Yazıcı Seçin** → Dropdown'dan yazıcınızı seçin
2. **Süreleri Ayarlayın** → Yazdırma (30sn) + Temizlik (8sn)
3. **PDF Seçin** → Dosyanızı yükleyin
4. **Yazdır** → İlerlemeyi izleyin

## Kaynak Koddan Derleme

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Xcode'da ⌘+R ile çalıştırın
```

## Lisans

[MIT](LICENSE) - Hüseyin Emre Gümüş (info@hegg.tr)
