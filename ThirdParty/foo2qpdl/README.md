# foo2qpdl (third-party, GPL-2.0)

Samsung CLP-300 için QPDL (SPL-C) kodlayıcısı. Uygulama bunu ayrı bir
çalıştırılabilir dosya olarak çağırır; kodu Swift'e kopyalanmamıştır.
Bu dizindeki dosyalar GNU GPL v2 (veya sonrası) lisanslıdır, bkz. `COPYING`.
Uygulamanın geri kalanı MIT lisanslıdır.

The QPDL (SPL-C) encoder for the Samsung CLP-300. The app runs it as a
separate executable; none of its code is copied into the Swift sources.
Files in this directory are licensed under the GNU GPL v2 (or later), see
`COPYING`. The rest of the app is MIT licensed.

## Kaynak / Source

- Proje: foo2zjs, Rick Richardson (JBIG kodu: JBIG-KIT, Markus Kuhn).
  Asıl site `foo2zjs.rkkda.com` artık yayında değil.
- Alındığı yer: Debian kaynak paketi
  `https://deb.debian.org/debian/pool/main/f/foo2zjs/foo2zjs_20200505dfsg0.orig.tar.xz`
  (SHA-256 `87465e6a31f8501b90508d50e97901d2cce8b5b3de5418cc156e66d5c500421b`,
  `foo2zjs_20200505dfsg0-5.dsc` ile doğrulandı).
- Sürüm: `foo2qpdl.c,v 1.56 2019/09/06`.
- Değişiklik yok: dosyalar arşivdekiyle birebir aynı. Debian yamalarının hiçbiri
  bu dosyalara dokunmuyor.

| Dosya | SHA-256 |
|---|---|
| foo2qpdl.c | `e7d38c1a4b41108c0bf415823d5f7c6519d07fdd6bff6f4aeea0069730914cff` |
| jbig.c | `2b1f7aa83461803cd588cf2e48bac4ba50e64e09cfb0da048c511b94c8c175db` |
| jbig.h | `0c016a8c69e349c510630edbf5b96057be952c2ac19c1a9b8488ad8c9864d7a4` |
| jbig_ar.c | `ae9fa2575d73a0cd50c6a32621ab2b6c4ca5f1115d27d636f461275c1d1e62f3` |
| jbig_ar.h | `292c4c43c944e2573b558d89b7004cec6c59c70dbbfd7b9890868a2291d1250a` |
| qpdl.h | `84b46fba4df46cf055cde9b4ad0fca6e370c0dd6a501ab500e8316b1960697ae` |
| COPYING | `62b5d10a9370a11bf75b4a23cb06ca84a7df884e9f88f722fe1e47a562aeed89` |

## Derleme / Build

Xcode, "Build foo2qpdl" adımında `build-helper.sh` betiğini çalıştırır ve
ikiliyi `PrinterManager.app/Contents/Helpers/foo2qpdl` olarak pakete koyar.
Elle derlemek için:

```sh
clang -O2 -Wall -o foo2qpdl foo2qpdl.c jbig.c jbig_ar.c
```
