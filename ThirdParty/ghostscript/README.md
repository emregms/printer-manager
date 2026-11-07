# Ghostscript (third-party, AGPL-3.0)

Sayfaları yazıcının çözünürlüğünde rastera çeviren program. Uygulama bunu ayrı
bir çalıştırılabilir dosya olarak çağırır (`Contents/Helpers/gs`); kodu Swift'e
kopyalanmamıştır ve uygulamaya bağlanmamıştır. Ghostscript GNU AGPL v3 (veya
sonrası) lisanslıdır, bkz. `COPYING`. İçine derlenen kütüphanelerin ve yazı
tiplerinin lisansları `THIRD-PARTY.txt` dosyasındadır. Uygulamanın geri kalanı
MIT lisanslıdır.

The program that rasterises pages at the printer's resolution. The app runs it
as a separate executable (`Contents/Helpers/gs`); none of its code is copied into
the Swift sources or linked into the app. Ghostscript is licensed under the GNU
AGPL v3 (or later), see `COPYING`. Licenses of the libraries and fonts compiled
into it are in `THIRD-PARTY.txt`. The rest of the app is MIT licensed.

## Kaynak / Source

- Proje: GPL Ghostscript, Artifex Software — https://ghostscript.com
- Sürüm / version: **10.08.0** (2026-09-08)
- Arşiv / tarball:
  `https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/ghostscript-10.08.0.tar.xz`
  (69 197 208 bayt)
  - SHA-512 `8006e2a32d03759a905b9548bdd83d4563173041006750e17e428b9eea24ad519aa4452ceecd7c073d3c420a68bf1b07ccc9e0533b1a05935f6b39ea8d9ce875`
    (Artifex'in aynı sürümdeki `SHA512SUMS` dosyasıyla doğrulandı / matches Artifex's `SHA512SUMS`)
  - SHA-256 `c20492bc8ebb96c87fa2e52a0926e1cda8cde95d66145e018ac713fed5da38cf`
- Kaynak kodunda değişiklik yok. Derleme betiği yalnız `configure`'un ürettiği
  Makefile'a bir modül ekler (aşağıda). / The source is unmodified; the build
  script only adds one module to the Makefile that `configure` generates (below).

## Bu klasör / This directory

| Dosya | İçerik |
|---|---|
| `build-gs.sh` | Kaynaktan derleme betiği (indirir, doğrular, iki mimari için derler) |
| `bin/gs` | Derlenmiş ikili, arm64 + x86_64; Xcode bunu pakete koyar |
| `COPYING` | GNU AGPL v3 metni (`doc/COPYING`) |
| `THIRD-PARTY.txt` | Ghostscript'in `LICENSE`'ı ve içine derlenen bileşenlerin lisansları |
| `SHA256SUMS` | Yukarıdaki üç dosyanın sağlama toplamları; Xcode her derlemede kontrol eder |
| `bundle-helper.sh` | Xcode "Bundle Ghostscript" adımı: kopyalar, imzalar |

## Derleme / Build

```sh
ThirdParty/ghostscript/build-gs.sh                          # indirir / downloads
ThirdParty/ghostscript/build-gs.sh ghostscript-10.08.0.tar.xz  # elde varsa / local copy
```

Apple Silicon'da yaklaşık 1 dakika sürer (x86_64 çapraz derlenir). Xcode
Ghostscript'i derlemez; "Bundle Ghostscript" adımı `bin/gs`'yi
`PrinterManager.app/Contents/Helpers/gs` olarak kopyalar, `COPYING` ve
`THIRD-PARTY.txt`'yi `Resources/ghostscript-*.txt` olarak koyar ve imzalar.
Ghostscript sürümü yükseltilirse betik yeniden çalıştırılır ve `bin/gs`,
`COPYING`, `THIRD-PARTY.txt`, `SHA256SUMS` birlikte commit edilir.

Takes about a minute on Apple Silicon (x86_64 is cross-compiled). Xcode does not
compile Ghostscript; its "Bundle Ghostscript" phase copies `bin/gs` to
`PrinterManager.app/Contents/Helpers/gs`, puts `COPYING` and `THIRD-PARTY.txt`
into `Resources/ghostscript-*.txt` and signs it. To upgrade, rerun the script and
commit `bin/gs`, `COPYING`, `THIRD-PARTY.txt` and `SHA256SUMS` together.

Seçenekler / options (`build-gs.sh`):

- Yalnız uygulamanın kullandığı aygıtlar: `--with-drivers=bitcmyk,pbmraw,pgmraw,ppmraw`
  (`gs -h`: `bbox bitcmyk nullpage pbmraw pgmraw ppmraw`).
- Kaynaklar ikilinin içinde (`COMPILE_INITS=1`, varsayılan): init dosyaları,
  URW yazı tipleri, CMap'ler, ICC profilleri `%rom%` dosya sisteminde.
- Ghostscript'le gelen kütüphaneler statik bağlanır (FreeType 2.14.2,
  IJG libjpeg 10, lcms2mt, libpng, zlib, OpenJPEG, jbig2dec, Brotli).
  `otool -L bin/gs` yalnız `/usr/lib/libSystem.B.dylib` gösterir.
- Kapalı: CUPS, fontconfig, dbus, GTK, X11, Tesseract (OCR), libidn, libpaper,
  libtiff, IJS, URF, iconv. Gömülmemiş yazı tipleri için uygulama gs'ye Mac'in
  yazı tipi klasörlerini `-sFONTPATH` ile verir (fontconfig'in yerine).
- `--prefix=/nonexistent/printermanager-ghostscript`: Mac'te kurulu başka bir
  Ghostscript'in (ör. Homebrew) dosyalarını okumasın; `%rom%` her zaman önce aranır.
- `FEATURE_DEVS`'e `$(GLD)sarc4.dev` eklenir: PDF yorumlayıcısı RC4 şifreli
  PDF'ler için onu kullanıyor ama `pdf/pdf.mak` onu istemiyor; normalde `pdfwrite`
  ile gelir, onsuz derlemede bağlama hatası verir (`_s_arcfour_set_key`).
- Tekrarlanabilir: `SOURCE_DATE_EPOCH` sürümün yayın günü, `-ffile-prefix-map`
  geçici klasörü siler. Aynı Xcode ile iki temiz derleme bayt bayt aynı `bin/gs`'yi
  verir (Xcode 27.2, Apple clang 21.0.0, macOS 27.2'de denendi).

## Homebrew gs ile karşılaştırma / Compared with Homebrew gs

Uygulamanın kendi sürücü hattıyla (gs → [clp300-raster] → foo2qpdl, renkli/siyah-beyaz,
Fotoğraf Modu açık/kapalı) Homebrew'un Ghostscript 10.08.0'ı ve bu ikili aynı QPDL
çıktısını verir: gömülü yazı tipli metin ve vektör çizim (600, 1200x600, 1200x1200 dpi),
Flate sıkıştırmalı görseller, RC4 şifreli PDF, gömülmemiş yazı tipleri (600 dpi).
Küçük farklar:

- 4:2:0 JPEG görseller: Homebrew libjpeg-turbo kullanıyor, bu ikili Ghostscript'le
  gelen IJG libjpeg'i; renk (chroma) büyütmesi farklı. 150 dpi bir sayfada piksellerin
  %6'sı ortalama 0,13/255 düzey farklı, 8 düzeyden büyük fark yalnız 22 pikselde ve
  hepsi keskin renk kenarlarında. 4:4:4 JPEG'ler birebir aynı.
- Gömülmemiş, ipuçlu (hinted) TrueType yazı tipleri 1200x600 dpi'de: FreeType 2.14.2
  ile 2.15.0 arasındaki fark; mürekkepli piksellerin %0,03'ü.
