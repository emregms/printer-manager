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

## Usage

1. **Select Printer** → Choose from dropdown
2. **Set Delays** → Print (30s) + Cleaning (8s)
3. **Select PDF** → Load your file
4. **Print** → Monitor progress

## Build from Source

```bash
git clone https://github.com/emregms/printer-manager.git
cd printer-manager
open PrinterManager.xcodeproj
# Press ⌘+R to run
```

## License

[MIT](LICENSE) - Hüseyin Emre Gümüş (info@hegg.tr)
