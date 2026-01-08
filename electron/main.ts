import { app, BrowserWindow, ipcMain, dialog } from 'electron';
import { join } from 'path';
import { fileURLToPath } from 'url';
import Store from 'electron-store';
import fs from 'fs/promises';
import path from 'path';
import { PDFDocument } from 'pdf-lib';
import { splitPdfPages, cleanupTempFolder, getTempFolderPath } from './pdfSplitter';

const isDev = !!process.env.VITE_DEV_SERVER_URL;
const store = new Store<{
  printerName?: string;
  coldPrintMs?: number;
  coldCleanMs?: number;
  hotPrintMs?: number;
  hotCleanMs?: number;
}>({
  name: 'settings',
});

let mainWindow: BrowserWindow | null = null;

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 720,
    webPreferences: {
      preload: fileURLToPath(new URL('./preload.cjs', import.meta.url)),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // Yükleme hatası olursa kullanıcıya bildir
  mainWindow.webContents.on('did-fail-load', (event, errorCode, errorDescription) => {
    console.error(`Yükleme hatası: ${errorDescription} (${errorCode})`);
  });

  if (isDev) {
    await mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL!);
    // Geliştirme modunda DevTools'u aç
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  } else {
    try {
      const indexPath = fileURLToPath(new URL('../dist/index.html', import.meta.url));
      console.log(`[MAIN] HTML dosyası yükleniyor: ${indexPath}`);
      await mainWindow.loadFile(indexPath);
    } catch (error) {
      console.error('[MAIN] HTML dosyası yükleme hatası:', error);
    }
  }
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// Settings IPC
ipcMain.handle('settings:get', () => {
  return store.store;
});

ipcMain.handle('settings:set', (_e, payload: Record<string, unknown>) => {
  store.set(payload as any);
  return store.store;
});

// PDF dosyası seçme ve analiz etme
ipcMain.handle('dialog:openPdf', async () => {
  try {
    const res = await dialog.showOpenDialog({
      filters: [{ name: 'PDF', extensions: ['pdf'] }],
      properties: ['openFile'],
    });
    
    if (res.canceled || res.filePaths.length === 0) return null;
    const filePath = res.filePaths[0];
    
    // PDF hakkında temel bilgileri al
    const stats = await fs.stat(filePath);
    
    return {
      path: filePath,
      name: path.basename(filePath),
      size: stats.size,
      lastModified: stats.mtime.toISOString()
    };
  } catch (error) {
    console.error('PDF seçme hatası:', error);
    return null;
  }
});

// Yazıcı listesini al
ipcMain.handle('printer:list', async () => {
  if (!mainWindow) return [];
  try {
    const printers = await mainWindow.webContents.getPrintersAsync();
    console.log(`${printers.length} yazıcı bulundu:`, printers.map(p => p.name).join(', '));
    return printers;
  } catch (error) {
    console.error('Yazıcı listesi alma hatası:', error);
    return [];
  }
});

// PDF hakkında bilgi al
ipcMain.handle('pdf:getInfo', async (_e, pdfPath: string) => {
  try {
    // PDF dosyasının varlığını kontrol et
    await fs.access(pdfPath);
    
    // PDF bilgilerini döndür
    const stats = await fs.stat(pdfPath);
    
    return {
      exists: true,
      path: pdfPath,
      name: path.basename(pdfPath),
      size: stats.size,
      lastModified: stats.mtime.toISOString()
    };
  } catch (error) {
    console.error('PDF bilgisi alma hatası:', error);
    return { exists: false, error: (error as Error).message };
  }
});

// PDF sayfa önizlemesi (PNG) oluştur - Temiz HTML ile
ipcMain.handle('pdf:generatePreview', async (_e, args: { pdfPath: string; pageNumber: number; width?: number; height?: number }) => {
  const { pdfPath, pageNumber, width = 150, height = 200 } = args;
  
  try {
    const tempFolder = getTempFolderPath();
    const previewsFolder = path.join(tempFolder, 'previews');
    await fs.mkdir(previewsFolder, { recursive: true });
    
    const previewPath = path.join(previewsFolder, `page_${pageNumber}.png`);
    
    console.log(`[PREVIEW] PDF yolu: ${pdfPath}`);
    console.log(`[PREVIEW] PNG yolu: ${previewPath}`);
    
    // PDF'i tek sayfalık dosyaya böl
    const splitResult = await splitPdfPages(pdfPath);
    if (!splitResult.success || !splitResult.pageFiles) {
      throw new Error('PDF bölme başarısız');
    }
    
    const pageFile = splitResult.pageFiles[pageNumber - 1];
    if (!pageFile) {
      throw new Error(`Sayfa ${pageNumber} bulunamadı`);
    }
    
    console.log(`[PREVIEW] Tek sayfa PDF: ${pageFile}`);
    
    // Görünmez pencere oluştur
    const previewWindow = new BrowserWindow({
      width: width * 2,
      height: height * 2,
      show: false,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        webSecurity: false
      }
    });
    
    // Temiz HTML oluştur - sadece PDF içeriği
    const htmlContent = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }
          body {
            background: white;
            overflow: hidden;
            width: 100vw;
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
          }
          iframe {
            width: 100%;
            height: 100%;
            border: none;
            background: white;
          }
        </style>
      </head>
      <body>
        <iframe src="file:///${pageFile.replace(/\\/g, '/')}"></iframe>
      </body>
      </html>
    `;
    
    // Geçici HTML dosyası oluştur
    const tempHtmlPath = path.join(tempFolder, `preview_${pageNumber}.html`);
    await fs.writeFile(tempHtmlPath, htmlContent);
    
    console.log(`[PREVIEW] HTML oluşturuldu: ${tempHtmlPath}`);
    
    // HTML'i yükle
    await previewWindow.loadURL(`file:///${tempHtmlPath.replace(/\\/g, '/')}`);
    
    // Yüklenmesini bekle
    await new Promise(resolve => setTimeout(resolve, 4000));
    
    // Sayfa görüntüsünü al - sadece içerik alanı
    const image = await previewWindow.webContents.capturePage({
      x: 0,
      y: 0,
      width: width * 2,
      height: height * 2
    });
    
    // PNG olarak kaydet
    const pngBuffer = image.toPNG();
    await fs.writeFile(previewPath, pngBuffer);
    
    console.log(`[PREVIEW] PNG oluşturuldu: ${previewPath}, boyut: ${pngBuffer.length} bytes`);
    
    // Pencereyi kapat
    previewWindow.destroy();
    
    // Geçici HTML dosyasını sil
    try {
      await fs.unlink(tempHtmlPath);
    } catch (e) {
      // Silme hatası önemsiz
    }
    
    return {
      success: true,
      previewPath,
      width,
      height
    };
  } catch (error) {
    console.error(`[PREVIEW] PDF önizleme hatası (sayfa ${pageNumber}):`, error);
    return {
      success: false,
      error: (error as Error).message
    };
  }
});

// PDF'i tek sayfalık dosyalara böl ve hazırla
ipcMain.handle('pdf:split', async (_e, pdfPath: string) => {
  try {
    console.log(`[MAIN] PDF bölme isteği: ${pdfPath}`);
    
    // Önce temp klasörü temizle
    await cleanupTempFolder();
    
    // PDF'i böl
    const result = await splitPdfPages(pdfPath);
    
    if (result.success) {
      console.log(`[MAIN] PDF bölme tamamlandı. ${result.pageCount} adet tek sayfalık PDF oluşturuldu.`);
      return {
        success: true,
        pageCount: result.pageCount,
        pageFiles: result.pageFiles
      };
    } else {
      console.error(`[MAIN] PDF bölme başarısız: ${result.error}`);
      return {
        success: false,
        error: result.error
      };
    }
  } catch (error) {
    console.error('[MAIN] PDF bölme hatası:', error);
    return {
      success: false,
      error: (error as Error).message
    };
  }
});

// Tek sayfalık PDF yazdırma - Electron'un native PDF yazdırma özelliğini kullan
ipcMain.handle('print:pdf', async (_e, args: { pdfPath: string; printerName: string; pageNumber?: number; landscape?: boolean; silent?: boolean; isFirstPage?: boolean }) => {
  const { pdfPath, printerName, pageNumber = 1, landscape, silent = true, isFirstPage = false } = args;
  
  try {
    console.log(`[MAIN] Yazdırma isteği alındı: ${pdfPath}, sayfa: ${pageNumber}, yazıcı: ${printerName}, ilk sayfa: ${isFirstPage}`);
    
    // Dosyanın varlığını kontrol et
    try {
      await fs.access(pdfPath);
      const stats = await fs.stat(pdfPath);
      console.log(`[MAIN] Dosya mevcut: ${pdfPath}, boyut: ${stats.size} byte`);
    } catch (err) {
      console.error(`[MAIN] DOSYA BULUNAMADI: ${pdfPath}`, err);
      return { ok: false, error: `Dosya bulunamadı: ${pdfPath}` };
    }
    
    // Geçici bir PDF penceresi aç
    console.log(`[MAIN] Yazdırma penceresi açılıyor...`);
    const pdfWindow = new BrowserWindow({
      width: 800,
      height: 600,
      show: false, // Görünmez pencere
      webPreferences: {
        offscreen: true,
      }
    });

    // PDF'i doğrudan aç
    console.log(`[MAIN] PDF yükleniyor: ${pdfPath}`);
    await pdfWindow.loadURL(`file://${pdfPath}`);
    
    // Yüklemenin tamamlanmasını bekle
    console.log(`[MAIN] PDF yükleme tamamlanması bekleniyor...`);
    await new Promise(r => setTimeout(r, 1000));
    
    // Yazdırma seçenekleri
    const printOptions = {
      silent, // Sessiz yazdırma diyalogu gösterme
      deviceName: printerName,
      printBackground: true,
      margins: { marginType: 'printableArea' }, // En iyi kalite için yazdırılabilir alan
      landscape: !!landscape,
      pageSize: 'A4',
      copies: 1,
    };
    
    console.log(`[MAIN] Yazdırma başlatılıyor... Seçenekler:`, printOptions);
    
    // Yazdırma işlemini gerçekleştir
    const result = await new Promise<{success: boolean; error?: string}>((resolve) => {
      try {
        console.log(`[MAIN] webContents.print çağrılıyor...`);
        
        // Timeout ekle - 10 saniye sonra otomatik olarak başarılı say
        const timeoutId = setTimeout(() => {
          console.log(`[MAIN] Yazdırma timeout oldu, başarılı kabul ediliyor: ${pdfPath}`);
          resolve({ success: true });
        }, 10000);
        
        pdfWindow.webContents.print(printOptions, (success, errorType) => {
          // Timeout'u temizle
          clearTimeout(timeoutId);
          
          if (success) {
            console.log(`[MAIN] PDF yazdırma BAŞARILI: ${pdfPath}`);
            resolve({ success: true });
          } else {
            console.error(`[MAIN] PDF yazdırma HATASI:`, errorType);
            resolve({ success: false, error: errorType });
          }
        });
      } catch (printError) {
        console.error(`[MAIN] Print çağrısı sırasında hata:`, printError);
        resolve({ success: false, error: (printError as Error).message });
      }
    });
    
    // İşlem bittiğinde pencereyi kapat
    console.log(`[MAIN] Yazdırma penceresi kapatılıyor...`);
    pdfWindow.destroy();
    
    if (result.success) {
      console.log(`[MAIN] Yazdırma işlemi başarıyla tamamlandı: ${pdfPath}, sayfa: ${pageNumber}`);
      return { ok: true, message: 'Yazdırma işlemi tamamlandı' };
    } else {
      console.error(`[MAIN] Yazdırma işlemi başarısız: ${result.error}`);
      return { ok: false, error: result.error || 'Yazdırma hatası' };
    }
  } catch (error) {
    console.error('[MAIN] Yazdırma sırasında kritik hata:', error);
    return { ok: false, error: (error as Error).message };
  }
});

// Temp klasörü temizleme
ipcMain.handle('pdf:cleanup', async () => {
  try {
    await cleanupTempFolder();
    return { success: true, message: 'Temp klasörü temizlendi' };
  } catch (error) {
    console.error('Temp klasör temizleme hatası:', error);
    return { success: false, error: (error as Error).message };
  }
});

// Temp klasör yolunu al
ipcMain.handle('pdf:getTempPath', async () => {
  const tempFolderPath = getTempFolderPath();
  console.log(`[MAIN] Temp klasör yolu: ${tempFolderPath}`);
  console.log(`[MAIN] Önizleme klasörü: ${path.join(tempFolderPath, 'previews')}`);
  return tempFolderPath;
});

// Boş PDF oluştur
ipcMain.handle('pdf:createBlank', async () => {
  try {
    console.log(`Boş PDF oluşturma isteği alındı`);
    
    // Boş PDF oluştur
    const pdfDoc = await PDFDocument.create();
    const page = pdfDoc.addPage([595, 842]); // A4 boyutu (72 DPI'da)
    
    // Boş sayfa, herhangi bir içerik eklemeye gerek yok
    
    // PDF'i kaydet
    const tempFolderPath = getTempFolderPath();
    const blankPdfPath = path.join(tempFolderPath, 'blank_page.pdf');
    
    // Dizinin var olduğundan emin ol
    try {
      await fs.mkdir(tempFolderPath, { recursive: true });
    } catch (err) {
      // Dizin zaten varsa hata verme
    }
    
    // PDF'i kaydet
    const pdfBytes = await pdfDoc.save();
    await fs.writeFile(blankPdfPath, pdfBytes);
    
    console.log(`Boş PDF oluşturuldu: ${blankPdfPath}`);
    
    return {
      success: true,
      path: blankPdfPath
    };
  } catch (error) {
    console.error('Boş PDF oluşturma hatası:', error);
    return {
      success: false,
      error: (error as Error).message
    };
  }
});



