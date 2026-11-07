# PrinterManager for macOS 🖨️

<div align="center">

[![TR](https://img.shields.io/badge/lang-TR-red.svg)](README.md)
[![EN](https://img.shields.io/badge/lang-EN-blue.svg)](README_EN.md)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black.svg)](#requirements)
[![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-blue.svg)](#requirements)

</div>

**A macOS driver and printing app for the Samsung CLP-300.** It replaces Samsung's 2008 Mac driver, which crashes on Apple Silicon: the app prepares each page itself and sends it straight to the printer. On printers with a worn transfer belt cleaner, each page is sent only after the printer has printed the previous one and cleaned the belt. Double feeds, photo printing, toner, error codes and the printer staying hot while idle are all handled in one window.

The app's interface is in Turkish; the English names are given in parentheses below.

![PrinterManager main window](screenshots/main.png)

## 📥 Download

**[⬇️ PrinterManager v2.0.0 (DMG, 3.6 MB)](https://github.com/emregms/printer-manager/releases/download/v2.0.0/PrinterManager-v2.0.0.dmg)** · [All releases](https://github.com/emregms/printer-manager/releases)

Runs on Intel and Apple Silicon Macs (macOS 13 Ventura or later).

## 🚀 Setting Up a New Mac

Samsung's old driver is **not needed**. It takes 5–10 minutes, once.

1. **Open the DMG** and drag PrinterManager to the **Applications** folder next to it.
2. **Allow the first launch.** The app is not signed by Apple, so macOS blocks it the first time. Run once in Terminal:

   ```bash
   xattr -cr /Applications/PrinterManager.app
   ```

   Without Terminal: try to open the app, close the warning, then click **Open Anyway** at the bottom of **System Settings → Privacy & Security** and enter your Mac password.
3. **Connect the CLP-300 over USB and turn it on**, then open PrinterManager. The **Setup Assistant** (Kurulum Yardımcısı) opens by itself:
   - **1. Ghostscript:** One button. With Homebrew, Ghostscript is installed directly. Without Homebrew, Terminal opens and installs Homebrew, then Ghostscript; it asks for your Mac password and Enter once.
   - **2. Printer and Driver:** **Sürücüyü Kur ve Yazıcıyı Ekle** (install driver and add printer) → your Mac password. The printer appears in Printers & Scanners as "Samsung CLP-300".
   - **3. Optional:** add "PrinterManager ile Yazdır" to the PDF menu of the print dialog; turn on "open at login".
   - **4. iPhone and iPad (optional):** **Yazıcıyı yerel ağda paylaş** (share the printer on the local network) → your Mac password ([details](#printing-from-iphone-and-ipad)).
   - **5. Photo Mode:** nothing to install; shows which colour data is in use ([details](#photo-mode)).
4. **Done.** Drag a PDF onto the window and click **Yazdır** (Print).

<p align="center">
  <img src="screenshots/setup.png" alt="Setup Assistant" width="560"/>
  <br/>
  <em>Setup Assistant: the missing steps in one window; green ticks are done</em>
</p>

Open the Setup Assistant again later from **PrinterManager menu → Kurulum Yardımcısı…**. If the printer is already added on this Mac with Samsung's old driver, that queue is left alone; a second printer "Samsung CLP-300 (PrinterManager)" is added next to it.

<details>
<summary>Manual setup (Terminal)</summary>

```bash
# Without Homebrew: https://brew.sh
brew install ghostscript
```

Then in PrinterManager: **Settings (⌘,) → macOS Sürücüsü (macOS driver) → Sürücüyü Kur ve Yazıcıyı Ekle**.

</details>

## ✨ Features

**Printing**
- **Own driver:** Ghostscript + foo2qpdl prepare each page and it goes to the printer raw. Dense, colour and vector-heavy pages print reliably.
- **Smart page pacing:** The next page is sent once the printer has printed the page and cleaned the belt. No fixed delay; a cold printer takes longer for the first page, a warm one less.
- **Stops on errors:** On a paper jam, open cover, no paper and so on, sending stops and the queue doesn't fill up; it continues where it stopped once fixed.
- **Photo mode:** Photos are printed with the app's own colour table and halftone screens computed for the CLP-300; if Samsung's old driver is installed, its files are used instead.
- **Manual duplex:** odd pages first, flip the paper, even pages in reverse order.
- **Grayscale**, three qualities (600, 1200x600, 1200x1200 dpi).

**Monitoring and intervening**
- **Print queue:** the page printing now and the ones coming next, with thumbnails; pause, resume, cancel.
- **Double feeds:** on a front side, one click prints the same page again; on a back side, the two ruined sheets are reprinted on both sides after the series. Undoable.
- **Printer status and toner:** the status and error codes the printer reports over USB, with an explanation, plus each toner's level and cartridge number.
- **Fuser and sleep:** see whether the printer is hot or asleep while idle, and set how many minutes before it sleeps.

**Convenience**
- **From iPhone and iPad:** Share → Print; the document opens in PrinterManager on the Mac, where you set it up and print (AirPrint).
- **Light in the background:** with the window closed it waits in the menu bar; no polling, no CPU while idle. The window opens when a document arrives.
- **From any app:** Safari, Preview, Word… "Print" opens the document in PrinterManager.
- **Drag and drop**, PDF preview, time remaining.
- **Setup Assistant**, Intel + Apple Silicon, Swift + SwiftUI.

## 📸 Screenshots

<p align="center">
  <img src="screenshots/printing.png" alt="Print queue and a double-feed intervention" width="820"/>
  <br/>
  <em>Print queue: the back of page 4 is printing; sheet 5/6, marked spoiled, will be reprinted on both sides at the end</em>
</p>

<p align="center">
  <img src="screenshots/settings.png" alt="Settings: driver, other apps, power save" width="420"/>
  <br/>
  <em>Settings (⌘,): tool paths, macOS driver, printing from other apps, the printer's sleep time</em>
</p>

## Usage

1. **Printer** (Yazıcı) → "Samsung CLP-300" (added by the PrinterManager driver).
2. **Page pacing** (Sayfa Geçişi) → "Akıllı" (smart, recommended). With "Sabit süre" (fixed) you set one wait (default 38 s).
3. **Duplex / Grayscale / Photo Mode** (Çift Yönlü / Siyah Beyaz / Fotoğraf Modu) → as needed.
4. **Driver and quality** → "Kendi sürücü (önerilen)" (own driver), 1200x600 dpi (600 dpi is faster, 1200x1200 is finest).
5. **PDF** → drag it onto the window or pick it in the left panel.
6. **Print** (Yazdır) → follow it in "Baskı Sırası" (print queue).

Advanced settings (⌘, or the button next to the Driver heading): Ghostscript and foo2qpdl paths, raw queue name, the printer's power save. Paths left empty are found automatically.

## Printing from Other Apps

This printer's worn transfer belt cleaner needs a wait after every page. So Safari, Preview and other apps don't print to it directly; the document opens in PrinterManager and is printed from there with the waits (and manual duplex if wanted):

- **By choosing the printer:** In the print dialog, choose "Samsung CLP-300" (added by the PrinterManager driver) and click **Print**. The print queue briefly shows "PrinterManager'da açılıyor…" (opening in PrinterManager); within a few seconds PrinterManager takes the document, deletes the job and opens it in its window. No data goes to the printer. If the app isn't running, the job stops after 30 seconds with "PrinterManager açık değil" (not open); open PrinterManager and the document arrives.
- **From the PDF menu:** In any print dialog, bottom left **PDF ▾ → PrinterManager ile Yazdır**. Whatever printer is selected, the document opens in PrinterManager.
- **From Finder:** drag the PDF onto the window, or right-click it → **Open With → PrinterManager**.

## Printing from iPhone and iPad

iPhones and iPads on the same network see the CLP-300 as an AirPrint printer:

1. Once on the Mac: Settings (⌘,) or the Setup Assistant → **iPhone ve iPad'den Yazdırma** → **Yazıcıyı yerel ağda paylaş** (share on the local network) → your Mac password. If macOS asks to allow finding devices on the local network, click **Allow**.
2. On the iPhone: in any app, **Share → Print → Samsung CLP-300 (PrinterManager)** → **Print**.
3. Within seconds the document opens in PrinterManager on the Mac; set quality, duplex and photo mode, then click **Yazdır** (Print). Nothing goes from the phone straight to the printer.

The Mac must be on and on the same network, with PrinterManager running (with the window closed it waits in the menu bar). With "open at login" on, it starts in the background when the Mac starts.

How it works: macOS printer sharing announces the queue on the network, but without the `_universal` subtype and `URF` key the iOS AirPrint list looks for. While PrinterManager runs, it announces the same queue with those markers (Bonjour). The iPhone's job arrives in macOS's printing system, `pminbox` holds it, and PrinterManager takes the document. iPhone jobs arrive as another user ("mobile"); fetching them requires the Mac account to be an administrator.

## Running in the Background

- Closing the window (red button, or ⌘Q, "Arka Planda Çalıştır" in the menu) doesn't quit the app: the Dock icon hides and a small printer icon stays in the menu bar.
- To quit completely: menu bar icon → **PrinterManager'dan Çık**, or ⌥⌘Q.
- Don't want the menu bar icon? Settings (⌘,) → **Arka Planda Çalışma** → turn off "Menü çubuğunda simgeyi göster". The app still runs in the background; to open the window, open PrinterManager again from Applications or Spotlight.
- The window opens by itself when a document arrives or a print needs an answer (flip pages, printer error).
- No polling while idle: when a job arrives, `pminbox` sends a system notification that wakes the app (plus a light fallback check every 30 s). Printer status is read only while the window is open. Measured CPU use with the window open: 0–0.5%.

### Why?

Samsung's last Mac driver for the CLP-300 dates from 2008 and runs under Rosetta on Apple Silicon. Its `rastertosec` filter crashes on dense or colour pages (`JBIGClipColorFullPage`, SIGSEGV). The queue shows "Filter failed", and the printer, receiving truncated data, prints a `SPL-C ERROR - Including Corrupted Data` page. HP no longer offers a macOS driver for this printer.

The own driver bypasses that filter completely:

```
PDF page → Ghostscript → [clp300-raster] → foo2qpdl -z0 -p2 → lp -o raw → printer
```

The parameters are taken one-to-one from the `foo2qpdl-wrapper` script of the foo2zjs project, used for the CLP-300 on Linux for years (A4, 1200x600 dpi). Each page is rendered from the PDF itself; landscape and Letter pages are fitted to A4. `clp300-raster` only joins in photo mode.

## Print Queue and Double Feeds

When printing starts, the preview switches to **Baskı Sırası** (print queue). Each row is one side of a page (front, back or single): its order, thumbnail and state (queued, printing, printed, spoiled, to reprint, skipped). The bar at the top shows the page printing now and what you can do about it. The "Sayfalar" (pages) tab shows the same in the page grid.

The printer sometimes pulls two sheets at once:

- **While printing fronts or single-sided pages:** **Tekrar Yazdır** (print again) → the same page prints again right after.
- **While printing backs:** both sheets are ruined. **Çift Kağıt Çekti** (double feed) → this sheet and the next back's sheet are marked spoiled. After the series, spoiled sheets are reprinted duplex: fronts first, then flip and print the backs.
- **A sheet printed earlier came out bad:** use **Kağıt Bozuk, Sona Ekle** (sheet spoiled, add to end) from that row's menu.
- **Geri Al** (undo) reverts the last intervention until the next page starts. You are asked before reprints start and can skip them.

In smart mode each page is sent once the printer has printed the previous one, cleaned the belt and is Ready again. A cold printer takes longer for the first page; the remaining time is estimated from the recent pages. Pages are also sent to a sleeping printer, which wakes up by itself.

## Photo Mode

In the standard colour path, Ghostscript converts with a generic CMYK profile and turns cyan + magenta + yellow on the same dot into black. That is fine for text, but in photos shadows turn grey and blotchy. With **Fotoğraf Modu** (photo mode) on in the left panel:

- Ghostscript renders the page in continuous tone (RGB or grey).
- The `clp300-raster` helper runs each pixel through a CLP-300 colour table (17×17×17 RGB → CMYK) and turns each colour into dots with a halftone screen made for that resolution. The screens account for the printer's dot gain; mid greys are made from CMY, black only joins in dark tones.
- foo2qpdl encodes the result for the printer as usual.

**The colour data can come from two sources.** The Setup Assistant, and the caption under the switch while Photo Mode is on, say which one is in use.

1. **PrinterManager's own data** comes inside the app, so it is ready on every Mac and needs none of Samsung's files. It is computed from scratch by `Scripts/make-colour-tables.py`: nothing is copied from Samsung's data, and Samsung's data is not used as input. It ships under the app's license (MIT).
   - **Colour table:** solved from a printer model (Neugebauer) of typical colour laser toners. Gamut mapping is done in Oklab: pure sRGB colours go to solid toner, low-chroma colours such as greys, skin and sky barely move, and colours the printer can't reach are clipped keeping their hue. Low GCR: mid greys from C+M+Y, black only in dark tones. Total toner is limited to 240%. Prints a little lighter than the screen (mid grey ~12 L* lighter); saturated colours are not lightened.
   - **Halftone:** clustered dots, ~95 lpi; C 18.4°, M 71.6°, Y 0°, K 45°. At 1200x600 the pixels are not square, so the dots are computed round in physical space. Dot gain is built into the thresholds: the CLP-300's toner spreads a lot, so 50% input gives only ~16% coverage.
2. **Samsung's colour files** come with Samsung's old CLP-300 Mac driver. They are **not** in the repo or the app. If present, they are read in place and take priority.

Search order: `/Library/Printers/Samsung/CLP-300` (where Samsung's driver installs them) → `~/Library/Application Support/PrinterManager/CLP-300` (no admin rights needed) → inside the app. If you have a Mac with Samsung's driver installed, you can put its `CLP-300` folder in the second place on the new Mac; HP no longer offers a macOS driver for this printer.

Our own data was first tested on the computer (`Scripts/simulate-photo-mode.py`: grey balance, tone ramps, page size), then tuned on the CLP-300 with three A4 test sheets. The first guess (40% coverage looking like 50% on paper) printed far too dark; dot gain was set to `--gain-at-40 0.86` and lightness to `--lighten 12`. If another CLP-300 or toner prints darker or lighter, the data is regenerated with these two values.

For photos, **1200x600 dpi** is recommended: a full-page A4 photo is at most ~8 MB. At 1200x1200 it is ~12–13 MB and you are asked before it is sent.

## Printer Status and Toner

The card at the top of the window reads the printer's own status every 10 seconds:

- **Status:** ready, printing, power save, paper jam (tray / inside / exit), no paper, cover open, toner low / empty / not installed, waste toner full, transfer belt / fuser / imaging unit end of life, and hardware errors. Each comes with an explanation and what to do (in Turkish).
- **Toner:** each toner's level and cartridge number (CLP-C300A, CLP-M300A, CLP-Y300A, CLP-K300A). 10% or less is marked "Az" (low).
- **Details:** raw status code, the printer's own (English) message, USB state and the printer firmware version.

When a print starts, the status and any low toner go to the log. If there is a problem that stops printing (paper jam, cover open, no paper), the app asks first. If an error occurs while printing, sending stops and no more pages are queued ("Yazıcı Hatası: Duraklatıldı"); once fixed and you press Devam (continue), it goes on, and asks whether to resend a page that may have been cut short.

The status is read with read-only USB control requests: nothing is sent to the printer (except the power-save setting, below) and CUPS is not disturbed while printing. The codes are decoded with the printer's own status table (SM.xml). The method was taken, for interoperability, from the status monitor in Samsung's Mac driver.

Toner cannot be reset: the chip in each cartridge keeps its own level.

### Fuser and Power Save

The CLP-300 keeps its fuser hot after every job and only sleeps when its power-save timer runs out. A chip on the status card shows it: **Fırın sıcak** (hot; uses power while idle, and when the sleep time is known, at most how many minutes until it sleeps), **Fırın ısınıyor** (warming), **Fırın soğuk** (asleep).

To shorten it: Settings (⌘,) → **Yazıcı Güç Tasarrufu**, pick 5–120 min and press **Yazıcıya Uygula** (apply to printer). The printer we tested was set to 10 min; 5 min is the minimum. The value is stored in the printer and **takes effect after the printer is turned off and on**. A sleeping printer wakes by itself when a job arrives; the first page starts a bit later while it warms up.

The setting is read and written with PJL commands over the printer's USB interface. The helper only allows read commands and the two power-save settings. It can't be changed while printing, because the printer is busy.

## Troubleshooting

The app's messages are in Turkish; the English meaning is given here.

| Message | What to do |
|---|---|
| "PrinterManager can't be opened / is damaged" | The first launch wasn't allowed: `xattr -cr /Applications/PrinterManager.app`, or System Settings → Privacy & Security → **Open Anyway**. |
| "Ghostscript bulunamadı" (not found) | The button in the Setup Assistant, or `brew install ghostscript`. If it lives elsewhere, enter its path in Settings (⌘,). |
| "USB'deki yazıcı: Bulunamadı" (no printer on USB) | Turn the printer on and check the USB cable, then press refresh in the Setup Assistant. |
| "Yazıcı kuyruğu durdurulmuş" (queue stopped) | System Settings > Printers & Scanners > Print Queue > Resume, or `cupsenable Samsung_CLP_300 && cupsaccept Samsung_CLP_300` |
| "Kuyrukta bekleyen iş var" (pending jobs) | Delete old stuck jobs in the Print Queue window (`cancel -a Samsung_CLP_300`). |
| "Yazıcı kapalı görünüyor" (printer offline) | Turn the printer on and check the USB cable. While printing, the app waits until the printer is ready. |
| "Sayfa N çok büyük" (page N too large) | The page data is over 8 MB (normal: 1–4 MB). "600 dpi ile Gönder" roughly halves it. |
| Printer prints an `SPL-C ERROR` page | Make sure the driver mode is "Kendi sürücü"; "Sistem sürücüsü" (system driver) causes this error. If it persists, set quality to 600 dpi. |
| Printing from Safari doesn't open the document in PrinterManager | Is PrinterManager running? Is the printer added by the PrinterManager driver selected in the print dialog? The Setup Assistant should show the driver as "Kurulu" (installed); if you installed with an older version, click **Sürücüyü Güncelle** (update driver). |
| Print queue shows "PrinterManager açık değil" (not open) | Open PrinterManager; within a few seconds it takes the stopped job and opens the document. |
| iPhone says "No AirPrint Printers Found" | Is PrinterManager running (printer icon in the menu bar)? Is "Yazıcıyı yerel ağda paylaş" on in Settings? Are the iPhone and the Mac on the same Wi-Fi? In System Settings → Privacy & Security → Local Network, PrinterManager must be on. |
| The job is stuck at "printing" on the iPhone | PrinterManager was not running or could not take the document. Open PrinterManager; the waiting job is taken within seconds, the document opens and the job disappears from the iPhone. |
| Photo Mode can't be turned on | The driver mode must be "Kendi sürücü" (own driver). If it says the colour files weren't found, the app bundle is incomplete: download and install PrinterManager again. Details: [Photo Mode](#photo-mode). |
| Power-save time did not change | It takes effect when the printer starts: turn it off and on. In Settings, the "Şu an" (current) line should show the new time. |
| Need details | The print log shows each page's size, time and any Ghostscript warnings. |

The "Sistem sürücüsü" (system driver) mode remains in settings as the old path (splits with PDFKit, sends with `lp`); use it only as a fallback.

## Requirements

- macOS 13 (Ventura) or later; Intel or Apple Silicon
- Samsung CLP-300 connected over USB
- [Ghostscript](https://www.ghostscript.com) (the Setup Assistant installs it with Homebrew)

## Build from Source

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Press ⌘R to run
```

The build compiles the helpers and puts them in the app bundle (`Contents/Helpers/`):

- `foo2qpdl`: from the source in `ThirdParty/foo2qpdl`.
- `cups-jobs`: from `Driver/cups-jobs.c`. Lists jobs that arrive in the queue, fetches their documents and deletes the job.
- `clp300-status`: from `Driver/clp300-status.c`. Reads the printer's status, toners and status table over USB; sets power save with PJL.
- `clp300-raster`: from `Driver/clp300-raster.c`. In photo mode, turns the raster into dots with a colour table and halftone screens.

The printer queue's files (`pminbox` filter, PPD, `install-driver.sh`) are in `Driver/`.

Photo mode's own colour data is in `PrinterManager/Resources/ColorTables/CLP-300` and is copied into the bundle's `Contents/Resources`. `python3 Scripts/make-colour-tables.py` regenerates it (needs numpy, ~1 minute, the same files every time). `Scripts/simulate-photo-mode.py` compares data sets without printing and prepares a side-by-side A4 test page (raw QPDL).

Scripts:

- `Scripts/make-dmg.sh`: builds Release (Intel + Apple Silicon) and makes `build/PrinterManager-v<version>.dmg`.
- `Scripts/screenshots.sh`: regenerates the screenshots on this page. A Debug build opens with a sample document and draws its own windows; nothing is sent to the printer (needs Python + Pillow).

## License

[MIT](LICENSE) - Hüseyin Emre Gümüş (info@hegg.tr)

The bundled **foo2qpdl** is not covered by that license: it comes from the foo2zjs project (Rick Richardson; JBIG code by Markus Kuhn) and is licensed under **GPL-2.0**. The source is Debian's `foo2zjs_20200505dfsg0` package (the original site is offline). The app runs it as a separate program; none of its code is copied into Swift. The unmodified source, the license text (`COPYING`) and where it came from are in [ThirdParty/foo2qpdl](ThirdParty/foo2qpdl). The license text is also in the app bundle as `Contents/Resources/foo2qpdl-COPYING.txt`.

**Ghostscript** (AGPL) is not distributed with the app; it is installed separately on the user's Mac with Homebrew. Samsung's colour table and halftone files are not distributed either; Photo Mode reads them where they are on the user's Mac.
