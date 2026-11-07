# PrinterManager for macOS 🖨️

<div align="center">

[![TR](https://img.shields.io/badge/lang-TR-red.svg)](README.md)
[![EN](https://img.shields.io/badge/lang-EN-blue.svg)](README_EN.md)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#gereksinimler)
[![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-blue.svg)](#gereksinimler)

</div>

**Samsung CLP-300 için macOS sürücüsü ve yazdırma uygulaması.** Samsung'un 2008'den kalma, Apple Silicon'da çöken Mac sürücüsüne gerek bırakmaz: sayfaları kendisi hazırlar ve yazıcıya doğrudan gönderir. Transfer kayışı temizleyicisi yorulmuş yazıcılarda her sayfayı, yazıcı bir öncekini basıp kayışı temizledikten sonra gönderir. Çift kağıt çekme, fotoğraf baskısı, toner, hata kodları ve yazıcının boşta ısınması gibi günlük dertleri tek pencerede toplar.

![PrinterManager ana pencere](screenshots/main.png)

## 📥 İndirme

**[⬇️ PrinterManager v2.0.0 (DMG, 29 MB)](https://github.com/emregms/printer-manager/releases/download/v2.0.0/PrinterManager-v2.0.0.dmg)** · [Tüm sürümler](https://github.com/emregms/printer-manager/releases)

Intel ve Apple Silicon Mac'lerde çalışır (macOS 13 Ventura ve sonrası).

## 🚀 Yeni Bir Mac'e Kurulum

Samsung'un eski sürücüsü ve Homebrew **gerekmez**. Birkaç dakika sürer, bir kez yapılır.

1. **DMG'yi açın** ve PrinterManager'ı yanındaki **Applications** klasörüne sürükleyin.
2. **İlk açılış izni.** Uygulama Apple tarafından imzalı değil; macOS ilk açılışta engeller. Terminal'de bir kez:

   ```bash
   xattr -cr /Applications/PrinterManager.app
   ```

   Terminal kullanmadan: uygulamayı açmayı deneyin, uyarıyı kapatın, sonra **Sistem Ayarları → Gizlilik ve Güvenlik** sayfasının altındaki **Yine de Aç** düğmesine basın ve Mac şifrenizi girin.
3. **CLP-300'ü USB ile bağlayıp açın**, sonra PrinterManager'ı açın. **Kurulum Yardımcısı** kendiliğinden açılır:
   - **1. Yazdırma Araçları:** Ghostscript ve foo2qpdl uygulamanın içinde gelir; bu adım baştan yeşil tiklidir.
   - **2. Yazıcı ve Sürücü:** **Sürücüyü Kur ve Yazıcıyı Ekle** → Mac şifreniz. Yazıcı, Yazıcılar ve Tarayıcılar'a "Samsung CLP-300" olarak eklenir.
   - **3. İsteğe bağlı:** Yazdırma penceresinin PDF menüsüne "PrinterManager ile Yazdır"ı ekleyin; "Oturum açılınca başlat"ı açın.
   - **4. Fotoğraf Modu:** Samsung'un renk dosyaları bulunursa açılabilir ([ayrıntı](#fotoğraf-modu)).
4. **Bitti.** Bir PDF'i pencereye sürükleyip **Yazdır**'a basın.

<p align="center">
  <img src="screenshots/setup.png" alt="Kurulum Yardımcısı" width="560"/>
  <br/>
  <em>Kurulum Yardımcısı: eksik adımlar tek pencerede; yeşil tikli olanlar tamam</em>
</p>

Kurulum Yardımcısı'nı sonradan **PrinterManager menüsü → Kurulum Yardımcısı…** ile açabilirsiniz. Yazıcı bu Mac'te Samsung'un eski sürücüsüyle zaten ekliyse ona dokunulmaz; yanına "Samsung CLP-300 (PrinterManager)" adlı ikinci bir yazıcı eklenir.

Sürücü Ayarlar'dan da kurulabilir: **Ayarlar (⌘,) → macOS Sürücüsü → Sürücüyü Kur ve Yazıcıyı Ekle**.

## ✨ Özellikler

**Yazdırma**
- **Kendi sürücü:** Sayfaları Ghostscript + foo2qpdl hazırlar ve yazıcıya ham olarak gider. Yoğun, renkli ve vektör ağırlıklı sayfalar da sorunsuz basılır.
- **Akıllı sayfa geçişi:** Yazıcı sayfayı basıp kayışı temizleyince sıradaki sayfa gönderilir. Sabit bekleme gerekmez; soğuk yazıcıda ilk sayfa uzun, ısınınca kısa sürer.
- **Hata olunca durur:** Kağıt sıkışması, kapak açık, kağıt yok gibi bir hatada gönderim durur, kuyruk şişmez; sorun giderilince kaldığı yerden sürer.
- **Fotoğraf modu:** Fotoğraflar Samsung'un CLP-300 için ayarladığı renk tablosu ve yarım ton desenleriyle basılır; gölgeler açık, renkler doğal çıkar.
- **Elle çift yön:** Önce tek sayfalar, sonra kağıtları çevirin, çift sayfalar ters sırada.
- **Siyah beyaz**, üç kalite (600, 1200x600, 1200x1200 dpi).

**Takip ve müdahale**
- **Baskı sırası:** Şu an basılan ve sıradaki sayfalar küçük resimleriyle; durdur, devam, iptal.
- **Çift kağıt çekme:** Ön yüzde tek tıkla aynı sayfa tekrar; arka yüzde bozulan iki kağıt seri bitince iki yüzüyle yeniden basılır. Geri alınabilir.
- **Yazıcı durumu ve toner:** Yazıcının USB'den bildirdiği durum ve hata kodları Türkçe açıklamasıyla, dört tonerin yüzdesi ve kartuş numaraları.
- **Fırın ve uyku:** Yazıcının boşta sıcak mı uykuda mı olduğu görünür; kaç dakikada uyuyacağı yazıcıya ayarlanır.

**Kolaylık**
- **Her uygulamadan:** Safari, Önizleme, Word… "Yazdır" deyince belge PrinterManager'da açılır.
- **Sürükle-bırak**, PDF önizleme, kalan süre tahmini.
- **Kurulum Yardımcısı**, Intel + Apple Silicon, Swift + SwiftUI.

## 📸 Ekran Görüntüleri

<p align="center">
  <img src="screenshots/printing.png" alt="Baskı sırası ve çift kağıt müdahalesi" width="820"/>
  <br/>
  <em>Baskı sırası: 4. sayfanın arka yüzü basılıyor; bozuk işaretlenen 5/6 kağıdı en sonda iki yüzüyle yeniden basılacak</em>
</p>

<p align="center">
  <img src="screenshots/settings.png" alt="Ayarlar: sürücü, başka uygulamalar, güç tasarrufu" width="420"/>
  <br/>
  <em>Ayarlar (⌘,): araç yolları, macOS sürücüsü, başka uygulamalardan yazdırma, yazıcının uyku süresi</em>
</p>

## Kullanım

1. **Yazıcı** → "Samsung CLP-300" (PrinterManager sürücüsüyle eklenen).
2. **Sayfa Geçişi** → "Akıllı" (önerilen). "Sabit süre" seçilirse tek bir Bekleme Süresi ayarlanır (varsayılan 38 sn).
3. **Çift Yönlü / Siyah Beyaz / Fotoğraf Modu** → gerektiği gibi.
4. **Sürücü ve kalite** → "Kendi sürücü (önerilen)", 1200x600 dpi (600 dpi daha hızlı, 1200x1200 en ince).
5. **PDF** → pencereye sürükleyin ya da sol panelden seçin.
6. **Yazdır** → Baskı Sırası'ndan izleyin.

Gelişmiş ayarlar (⌘, ya da Sürücü başlığının yanındaki düğme): Ghostscript ve foo2qpdl yolları, ham gönderim kuyruğu, yazıcının güç tasarrufu. Yollar boş bırakılırsa uygulamanın içindeki araçlar kullanılır; kendi Ghostscript'inizi kullanmak isterseniz yolunu buraya girin.

## Başka Uygulamalardan Yazdırma

Transfer kayışı temizleyicisi yorulmuş bu yazıcı her sayfadan sonra beklemek ister. Bu yüzden Safari, Önizleme gibi uygulamalardan doğrudan basılmaz; belge PrinterManager'da açılır, oradan beklemeli (ve istenirse elle çift yönlü) basılır:

- **Yazıcıyı seçerek:** Yazdırma penceresinde "Samsung CLP-300" (PrinterManager sürücüsüyle eklenen) yazıcısını seçip **Yazdır** deyin. Yazdırma Sırası'nda kısa bir süre "PrinterManager'da açılıyor…" görünür; PrinterManager birkaç saniye içinde belgeyi alır, işi siler ve pencerede açar. Yazıcıya hiç veri gitmez. Uygulama kapalıysa iş 30 saniye sonra "PrinterManager açık değil" mesajıyla durur; PrinterManager'ı açınca belge gelir.
- **PDF menüsünden:** Herhangi bir yazdırma penceresinde sol alttaki **PDF ▾ → PrinterManager ile Yazdır**. Hangi yazıcı seçili olursa olsun belge PrinterManager'da açılır.
- **Finder'dan:** PDF'i pencereye sürükleyin ya da sağ tıklayıp **Birlikte Aç → PrinterManager** deyin.

### Neden?

Samsung'un CLP-300 için son Mac sürücüsü 2008'den kalma ve Apple Silicon'da Rosetta ile çalışıyor. Bu sürücünün `rastertosec` filtresi yoğun ya da renkli sayfalarda çöküyor (`JBIGClipColorFullPage`, SIGSEGV). Kuyrukta "Filter failed" hatası görünüyor. Yazıcı ise yarım kalmış veriyi aldığında `SPL-C ERROR - Including Corrupted Data` sayfası basıyor. HP de artık bu yazıcı için macOS sürücüsü sunmuyor.

Kendi sürücü bu filtreyi tamamen devre dışı bırakır:

```
PDF sayfası → Ghostscript → [clp300-raster] → foo2qpdl -z0 -p2 → lp -o raw → yazıcı
```

Parametreler, Linux'ta yıllardır CLP-300 için kullanılan foo2zjs projesinin `foo2qpdl-wrapper` betiğinden birebir alınmıştır (A4, 1200x600 dpi). Her sayfa PDF'in kendisinden render edilir; yatay ve Letter sayfalar A4'e sığdırılır. `clp300-raster` yalnızca fotoğraf modunda araya girer.

## Baskı Sırası ve Çift Kağıt

Yazdırma başlayınca önizleme **Baskı Sırası**'na geçer. Her satır bir sayfanın bir yüzüdür (ön, arka ya da tek yüz): sırası, küçük resmi ve durumu (sırada, basılıyor, basıldı, bozuk, yeniden basılacak, atlandı) görünür. Üstteki çubuk şu an basılan sayfayı ve o an yapılabilecekleri gösterir. "Sayfalar" sekmesi aynı bilgiyi sayfa ızgarasında gösterir.

Yazıcı bazen iki kağıdı birden çeker:

- **Ön yüz ya da tek yüz basılırken:** **Tekrar Yazdır** → aynı sayfa hemen ardından bir daha basılır.
- **Arka yüzler basılırken:** iki kağıt da çöp olur. **Çift Kağıt Çekti** → bu kağıt ve sıradaki arka yüzün kağıdı bozuk sayılır. Seri bitince bozulan kağıtlar çift yönlü yeniden basılır: önce ön yüzleri, sonra kağıtları çevirip arka yüzleri.
- **Daha önce basılmış bir kağıt bozuk çıktıysa:** listede o satırın menüsünden **Kağıt Bozuk, Sona Ekle**.
- Son müdahale, sonraki sayfa başlayana kadar **Geri Al** ile geri alınır. Yeniden basım başlamadan önce sorulur; istenirse atlanır.

Akıllı modda her sayfa, yazıcı bir öncekini basıp kayışı temizleyip yeniden "Hazır" olunca gönderilir. Soğuk yazıcıda ilk sayfa uzun, ısınınca kısa sürer; kalan süre son sayfaların ortalamasından tahmin edilir. Uykudaki yazıcıya sayfa gönderilir, yazıcı kendiliğinden uyanır.

## Fotoğraf Modu

Standart renkli yolda Ghostscript genel bir CMYK profiliyle çevirir ve aynı noktaya düşen camgöbeği + macenta + sarıyı siyaha çevirir. Yazı için iyi, fotoğrafta gölgeler griye ve lekeye döner. Sol paneldeki **Fotoğraf Modu** açıkken:

- Ghostscript sayfayı sürekli tonlu (RGB ya da gri) verir.
- `clp300-raster` yardımcı aracı her pikseli Samsung'un CLP-300 renk tablosundan (17×17×17 RGB → CMYK) geçirir ve her rengi Samsung'un o çözünürlük için hazırladığı yarım ton deseniyle noktalara çevirir. Desenler yazıcının nokta kazancını hesaba katar; orta griler CMY ile, siyah yalnız koyu tonlarda kullanılır.
- foo2qpdl her zamanki gibi yazıcı diline çevirir.

**Renk dosyaları:** Bu dosyalar Samsung'un eski CLP-300 Mac sürücüsüyle gelir; repoda ve uygulamada **yoktur**, çalışırken yerinden okunur. Uygulama iki yere bakar:

- `/Library/Printers/Samsung/CLP-300` (Samsung sürücüsünün kurduğu yer)
- `~/Library/Application Support/PrinterManager/CLP-300` (yönetici izni gerekmez)

HP artık bu yazıcı için macOS sürücüsü sunmuyor. Samsung sürücüsü kurulu bir Mac'iniz varsa `CLP-300` klasörünü yeni Mac'te ikinci yere koymanız yeterli. Dosyalar bulunamazsa her şey çalışır; yalnızca Fotoğraf Modu kapalı kalır ve nedeni yazılır.

Fotoğraf için **1200x600 dpi** önerilir: A4 tam sayfa fotoğraf ~6,7 MB. 1200x1200'de ~13 MB olur ve gönderilmeden önce sorulur.

## Yazıcı Durumu ve Toner

Pencerenin üstündeki kart, yazıcının kendi bildirdiği durumu 10 saniyede bir okur:

- **Durum:** Hazır, yazdırıyor, güç tasarrufu, kağıt sıkışması (tepsi / iç / çıkış), kağıt yok, kapak açık, toner az / bitti / takılı değil, atık toner kabı dolu, transfer kayışı / ısıtıcı / görüntüleme ünitesi ömrü ve donanım hataları. Her biri Türkçe açıklaması ve ne yapılacağıyla gösterilir.
- **Toner:** Dört tonerin yüzdesi ve kartuş numarası (CLP-C300A, CLP-M300A, CLP-Y300A, CLP-K300A). %10 ve altı "Az" olarak işaretlenir.
- **Ayrıntılar:** Ham durum kodu, yazıcının İngilizce mesajı, USB durumu ve yazıcının ürün yazılımı sürümü.

Yazdırma başlarken durum ve azalan tonerler günlüğe yazılır. Kağıt sıkışması, kapak açık ya da kağıt yok gibi baskıyı durduran bir sorun varsa sorulur. Baskı sürerken hata olursa gönderim durur ve kuyruğa yeni sayfa eklenmez ("Yazıcı Hatası: Duraklatıldı"); sorun giderilip Devam'a basılınca sürer, sayfa yarım kaldıysa yeniden gönderilip gönderilmeyeceği sorulur.

Durum, yazıcıdan yalnızca okuma yapan USB kontrol istekleriyle alınır. Yazıcıya veri gönderilmez (güç tasarrufu ayarı hariç, aşağıda) ve yazdırma sürerken CUPS'a karışılmaz. Kodların anlamı yazıcının kendi durum tablosundan (SM.xml) okunur. Bu yöntem, Samsung'un Mac sürücüsündeki durum izleyicisinden birlikte çalışabilirlik için çıkarıldı.

Toner sıfırlama yapılamaz: kartuşlardaki çip seviyeyi kendisi tutar.

### Fırın ve Güç Tasarrufu

CLP-300 her işten sonra fırınını (ısıtıcı ünite) sıcak tutar ve ancak güç tasarrufu süresi dolunca uyur. Durum kartındaki çip bunu gösterir: **Fırın sıcak** (boşta enerji harcıyor; süre biliniyorsa en geç kaç dakikada uyuyacağı), **Fırın ısınıyor**, **Fırın soğuk** (uykuda).

Süreyi kısaltmak için Ayarlar (⌘,) → **Yazıcı Güç Tasarrufu**: 5–120 dk arasından seçip **Yazıcıya Uygula**. Denediğimiz yazıcı 10 dk'ya ayarlıydı; en kısa süre 5 dk. Ayar yazıcının belleğine yazılır ve **yazıcı kapatılıp açılınca** geçerli olur. Uyuyan yazıcı iş gelince kendiliğinden uyanır; ilk sayfa ısınma yüzünden biraz geç başlar.

Ayar, yazıcının USB arayüzünden PJL komutlarıyla okunur ve yazılır. Yardımcı araç yalnızca okuma komutlarına ve iki güç tasarrufu ayarına izin verir. Yazdırma sürerken yazıcı meşgul olduğu için ayar yapılamaz.

## Sorun Giderme

| Durum | Ne yapmalı |
|---|---|
| "PrinterManager açılamıyor / hasarlı" | İlk açılış izni verilmemiş: `xattr -cr /Applications/PrinterManager.app` ya da Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç**. |
| "Ghostscript bulunamadı" | Ghostscript uygulamanın içinde gelir. Ayarlar'da (⌘,) Ghostscript yolu girildiyse silin; girilmediyse PrinterManager'ı yeniden indirip kurun. |
| "USB'deki yazıcı: Bulunamadı" | Yazıcıyı açın ve USB kablosunu kontrol edin, sonra Kurulum Yardımcısı'nda yenile düğmesine basın. |
| "Yazıcı kuyruğu durdurulmuş" | Sistem Ayarları > Yazıcılar ve Tarayıcılar > Yazdırma Sırası > Sürdür, ya da `cupsenable Samsung_CLP_300 && cupsaccept Samsung_CLP_300` |
| "Kuyrukta bekleyen iş var" | Önceki takılı işleri Yazdırma Sırası penceresinden silin (`cancel -a Samsung_CLP_300`). |
| "Yazıcı kapalı görünüyor" | Yazıcıyı açın, USB kablosunu kontrol edin. Yazdırma sırasında yazıcı hazır olana kadar uygulama bekler. |
| "Sayfa N çok büyük" | Sayfa verisi 8 MB'ı aşmış (olağan: 1–4 MB). "600 dpi ile Gönder" veriyi yaklaşık yarıya indirir. |
| Yazıcı `SPL-C ERROR` sayfası basıyor | Sürücü modunun "Kendi sürücü" olduğundan emin olun; "Sistem sürücüsü" bu hatayı verir. Devam ederse kaliteyi 600 dpi yapın. |
| Safari'den yazdırınca belge PrinterManager'da açılmıyor | PrinterManager açık mı? Yazdırma penceresinde PrinterManager sürücüsüyle eklenen yazıcı mı seçili? Kurulum Yardımcısı'nda sürücü "Kurulu" görünmeli; eski sürümle kurduysanız **Sürücüyü Güncelle** deyin. |
| Yazdırma Sırası'nda "PrinterManager açık değil" | PrinterManager'ı açın; durdurulan iş birkaç saniye içinde alınır ve belge açılır. |
| Fotoğraf Modu açılmıyor | Samsung'un renk dosyaları bulunamadı; [Fotoğraf Modu](#fotoğraf-modu) bölümüne bakın. |
| Güç tasarrufu süresi değişmedi | Ayar yazıcı açılırken geçerli olur: yazıcıyı kapatıp açın. Ayarlar'da "Şu an" satırı yeni süreyi göstermeli. |
| Ayrıntı gerekiyor | Yazdırma Günlüğü her sayfanın boyutunu, süresini ve Ghostscript uyarılarını gösterir. |

"Sistem sürücüsü" modu eski yol olarak ayarlarda duruyor (PDFKit ile bölüp `lp` ile gönderir); yalnızca yedek olarak kullanın.

## Gereksinimler

- macOS 13 (Ventura) ya da sonrası; Intel ya da Apple Silicon
- Samsung CLP-300, USB ile bağlı

Başka bir şey kurmak gerekmez: [Ghostscript](https://www.ghostscript.com) uygulamanın içinde gelir.

## Kaynak Koddan Derleme

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Xcode'da ⌘R ile çalıştırın
```

Derleme sırasında yardımcı programlar otomatik derlenip uygulama paketine (`Contents/Helpers/`) konur:

- `foo2qpdl`: `ThirdParty/foo2qpdl` klasöründeki kaynaktan.
- `gs`: `ThirdParty/ghostscript/bin/gs`'den kopyalanır. Ghostscript 10.08.0'dır, `ThirdParty/ghostscript/build-gs.sh` ile resmi kaynak arşivinden (Intel + Apple Silicon) derlenmiştir; Xcode onu yeniden derlemez. Ayrıntı: [ThirdParty/ghostscript](ThirdParty/ghostscript).
- `cups-jobs`: `Driver/cups-jobs.c`'den. Kuyruğa gelen işleri listeler, belgelerini alır ve işi siler.
- `clp300-status`: `Driver/clp300-status.c`'den. Yazıcının durumunu, tonerlerini ve durum tablosunu USB'den okur; güç tasarrufunu PJL ile ayarlar.
- `clp300-raster`: `Driver/clp300-raster.c`'den. Fotoğraf modunda Samsung'un renk tablosuyla rasteri noktalara çevirir.

Yazıcı kuyruğunun dosyaları (`pminbox` filtresi, PPD, `install-driver.sh`) `Driver/` klasöründedir.

Betikler:

- `Scripts/make-dmg.sh`: Release'i (Intel + Apple Silicon) derler ve `build/PrinterManager-v<sürüm>.dmg` üretir.
- `Scripts/screenshots.sh`: Bu sayfadaki ekran görüntülerini yeniden üretir. Debug derlemesi örnek bir belgeyle açılır ve kendi pencerelerini çizer; yazıcıya hiçbir şey gönderilmez (Python + Pillow gerekir).

## Lisans

[MIT](LICENSE) - Hüseyin Emre Gümüş (info@hegg.tr)

Uygulama içinde gelen **foo2qpdl** bu lisansa dahil değildir: foo2zjs projesinden (Rick Richardson; JBIG kodu Markus Kuhn) alınmıştır ve **GPL-2.0** lisanslıdır. Kaynak, Debian'ın `foo2zjs_20200505dfsg0` paketidir (asıl site artık yayında değil). Uygulama onu ayrı bir program olarak çalıştırır; kodu Swift'e kopyalanmamıştır. Değiştirilmemiş kaynak kodu, lisans metni (`COPYING`) ve kaynağın nereden alındığı [ThirdParty/foo2qpdl](ThirdParty/foo2qpdl) klasöründedir. Lisans metni uygulama paketinde `Contents/Resources/foo2qpdl-COPYING.txt` olarak da bulunur.

Uygulama içinde gelen **Ghostscript** de bu lisansa dahil değildir: Artifex Software'in GPL Ghostscript 10.08.0'ıdır ve **AGPL-3.0** lisanslıdır. Uygulama onu ayrı bir program olarak çalıştırır (`Contents/Helpers/gs`); kodu Swift'e kopyalanmamış ve uygulamaya bağlanmamıştır. Değiştirilmemiş resmi kaynak arşivinin adresi ve sağlama toplamları, ikiliyi bu kaynaktan yeniden üreten derleme betiği ve lisans metinleri [ThirdParty/ghostscript](ThirdParty/ghostscript) klasöründedir. Uygulama paketinde AGPL metni `Contents/Resources/ghostscript-COPYING.txt`, Ghostscript'e derlenen kütüphanelerin (FreeType, libjpeg, Little CMS, libpng, zlib, OpenJPEG, jbig2dec, Brotli) ve yazı tiplerinin lisansları `ghostscript-THIRD-PARTY.txt` olarak bulunur.

Samsung'un renk tablosu ve yarım ton dosyaları dağıtılmaz; Fotoğraf Modu onları kullanıcının Mac'indeki yerlerinden okur.
