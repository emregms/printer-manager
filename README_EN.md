# PrinterManager for macOS 🖨️

<div align="center">

[![TR](https://img.shields.io/badge/lang-TR-red.svg)](README.md)
[![EN](https://img.shields.io/badge/lang-EN-blue.svg)](README_EN.md)

</div>

A native macOS application that prevents laser printer transfer belt wear. Adds configurable delays between pages when printing multi-page PDFs, preventing the transfer belt from overheating and premature wear.

> 🧪 **Tested:** With Samsung CLP-300, compatible with all laser printers experiencing similar issues.

![App Screenshot](screenshots/1.png)

## 📥 Download

**[⬇️ Download PrinterManager v1.0.0 DMG](https://github.com/emregms/printer-manager/releases/download/v1.0.0/PrinterManager-v1.0.0.dmg)**

### ⚠️ macOS Security Warning on First Launch

macOS blocks unsigned applications. To open the app:

**Method 1 - Terminal (Recommended):**

```bash
xattr -cr /Applications/PrinterManager.app
```

**Method 2 - Manual:**

1. **Right-click** on the app (or Control+click)
2. Select **"Open"**
3. Click **"Open"** in the dialog

## Features

- **Own Driver (Samsung CLP-300)**: Instead of the old Samsung driver in macOS, the app prepares each page itself (Ghostscript + foo2qpdl) and sends it to the printer raw. Dense, colour and vector-heavy pages print reliably
- **Adjustable Delays**: Print and cleaning delays with sliders
- **Page-by-Page Printing**: Each page sent separately to printer
- **Manual Duplex**: Odd pages → Flip → Even pages reversed
- **PDF Preview**: Thumbnail grid for all pages
- **Pause/Resume**: Pause and continue printing anytime
- **Time Estimate**: See remaining print time
- **Grayscale Mode**: Faster and more economical
- **Native macOS**: Swift + SwiftUI, Apple Silicon optimized

## Screenshots

<p align="center">
  <img src="screenshots/2.png" alt="Printing Progress" width="800"/>
  <br/>
  <em>Page-by-page printing with progress tracking</em>
</p>

<p align="center">
  <img src="screenshots/3.png" alt="Duplex Printing" width="800"/>
  <br/>
  <em>Duplex printing - flip pages prompt</em>
</p>

## Requirements

- macOS 13.0 (Ventura) or later
- Intel or Apple Silicon (M1/M2/M3)
- For the own driver: [Ghostscript](https://www.ghostscript.com) (via Homebrew)

## Setting Up a New Mac (from scratch)

Samsung's old driver is **not needed**. You only do this once:

1. **Ghostscript:** if you don't have Homebrew, install it with the command on [brew.sh](https://brew.sh), then:

   ```bash
   brew install ghostscript
   ```

   If Homebrew is installed, the **Ghostscript'i Kur** (Install Ghostscript) button in the app's Settings window does this too.
2. **App:** put PrinterManager in `/Applications` and open it (see the first-launch macOS warning steps above).
3. **Printer:** connect the CLP-300 over USB and turn it on. In PrinterManager choose **Settings (⌘,) → macOS Sürücüsü → Sürücüyü Kur ve Yazıcıyı Ekle** (Install driver and add printer) and enter your admin password in the macOS prompt. The printer is added to Printers & Scanners as "Samsung CLP-300".
4. **Optional**, in the "Başka Uygulamalardan Yazdırma" (Printing from other apps) section of the same window:
   - Add "PrinterManager ile Yazdır" to the PDF menu of print dialogs.
   - Turn on launch at login, so documents sent from other apps arrive right away.

In the **Sürücü** (Driver) section of the side panel, "Ghostscript" and "foo2qpdl" should both show a green check. foo2qpdl needs no separate install; it ships inside the app.

If the printer is already set up on this Mac with Samsung's old driver, that queue is left alone and a second printer named "Samsung CLP-300 (PrinterManager)" is added next to it. The app sends pages to either one unfiltered with `lp -o raw`.

## Printing from Other Apps

The transfer belt cleaner is broken, so this printer needs a delay between pages on every job. That's why apps like Safari or Preview don't print to it directly; the document opens in PrinterManager instead, which prints it with the delay (and manual duplex if you want):

- **By choosing the printer:** in the print dialog pick "Samsung CLP-300" (the one added by the PrinterManager driver) and click **Print**. The print queue briefly shows "PrinterManager'da açılıyor…" (opening in PrinterManager); within a few seconds PrinterManager takes the document, deletes the job and opens it in its window. No data is sent to the printer. If the app is closed, the job stops after 30 seconds with "PrinterManager açık değil" (PrinterManager is not open); the document arrives when you open PrinterManager.
- **From the PDF menu:** in any print dialog, **PDF ▾ → PrinterManager ile Yazdır** at the bottom left. Whatever printer is selected, the document opens in PrinterManager.
- **From Finder:** right-click a PDF → **Open With → PrinterManager**.
### Why?

Samsung's last Mac driver for the CLP-300 dates from 2008 and runs under Rosetta on Apple Silicon. Its `rastertosec` filter crashes on dense or colour pages (`JBIGClipColorFullPage`, SIGSEGV). The queue shows "Filter failed", and when the printer receives the truncated data it prints a `SPL-C ERROR - Including Corrupted Data` page.

The own driver bypasses that filter completely:

```
PDF page → Ghostscript (bitcmyk / pbmraw) → foo2qpdl -z0 -p2 → lp -o raw → printer
```

The parameters are taken verbatim from the `foo2qpdl-wrapper` script of the foo2zjs project, which Linux has used for the CLP-300 for years (A4, 1200x600 dpi). Each page is rendered from the PDF itself; landscape and Letter pages are fitted to A4.

## Usage

1. **Select Printer** → Choose from dropdown
2. **Set Delays** → Print (30s) + Cleaning (8s)
3. **Driver and Quality** → "Kendi sürücü (önerilen)" (own driver), quality 1200x600 dpi (600 dpi is faster with less data, 1200x1200 is best)
4. **Select PDF** → Load your file
5. **Print** → Monitor progress

Advanced settings (⌘, or the button next to the Driver heading): Ghostscript and foo2qpdl paths, raw queue name. Left empty, they are found automatically.

## Troubleshooting

The app's messages are in Turkish; the English meaning is given here.

| Message | What to do |
|---|---|
| "Ghostscript bulunamadı" (not found) | `brew install ghostscript`. If it lives elsewhere, enter its path in Settings (⌘,). |
| "Yazıcı kuyruğu durdurulmuş" (queue stopped) | System Settings > Printers & Scanners > Print Queue > Resume, or `cupsenable Samsung_CLP_300 && cupsaccept Samsung_CLP_300` |
| "Kuyrukta bekleyen iş var" (pending jobs) | Delete old stuck jobs in the Print Queue window (`cancel -a Samsung_CLP_300`). |
| "Yazıcı kapalı görünüyor" (printer offline) | Turn the printer on and check the USB cable. While printing, the app waits until the printer is ready. |
| "Sayfa N çok büyük" (page N too large) | The page data is over 8 MB (normal: 1–4 MB). "600 dpi ile Gönder" roughly halves it. |
| Printer prints an `SPL-C ERROR` page | Make sure the driver mode is "Kendi sürücü"; "Sistem sürücüsü" (system driver) causes this error. If it persists, set quality to 600 dpi. |
| Printing from Safari doesn't open the document in PrinterManager | Is PrinterManager running? Is the printer added by the PrinterManager driver selected in the print dialog? Settings → macOS Sürücüsü should say "Kurulu" (installed); if you installed with an older version, click **Sürücüyü Güncelle** (Update driver). |
| Print queue shows "PrinterManager açık değil" (not open) | Open PrinterManager; within a few seconds it takes the stopped job and opens the document. |
| Need details | The print log shows each page's size, time and any Ghostscript warnings. |

The "Sistem sürücüsü" (system driver) mode remains in settings as the old path (splits with PDFKit, sends with `lp`); use it only as a fallback.

## Build from Source

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Press ⌘+R to run
```

During the build, two helper programs are compiled and placed in the app bundle (`Contents/Helpers/`):

- `foo2qpdl`: from the source in `ThirdParty/foo2qpdl`.
- `cups-jobs`: from `Driver/cups-jobs.c`. It lists held jobs, fetches their documents and deletes the job.

The printer queue's files (`pminbox` filter, PPD, `install-driver.sh`) are in `Driver/`.

## License

[MIT](LICENSE) - Hüseyin Emre Gümüş (info@hegg.tr)

The bundled **foo2qpdl** is not covered by that license: it comes from the foo2zjs project (Rick Richardson; JBIG code by Markus Kuhn) and is licensed under the **GPL-2.0**. The source is Debian's `foo2zjs_20200505dfsg0` package (the original site is no longer online). The app runs it as a separate program; none of its code is copied into the Swift sources. The unmodified source code, the license text (`COPYING`) and its provenance are in [ThirdParty/foo2qpdl](ThirdParty/foo2qpdl). The license text also ships in the app bundle as `Contents/Resources/foo2qpdl-COPYING.txt`.
