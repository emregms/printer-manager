import { PDFDocument } from 'pdf-lib';
import fs from 'fs/promises';
import path from 'path';
import { app } from 'electron';

export const getTempFolderPath = () => {
  return path.join(app.getPath('temp'), 'samsung-clp300-printer-manager');
};

export const cleanupTempFolder = async () => {
  const tempFolder = getTempFolderPath();
  try {
    await fs.rm(tempFolder, { recursive: true, force: true });
    await fs.mkdir(tempFolder, { recursive: true });
  } catch (error) {
    console.error('Temp klasör temizleme hatası:', error);
  }
};

export const splitPdfPages = async (pdfPath: string): Promise<{ success: boolean; pageFiles?: string[]; pageCount?: number; error?: string }> => {
  try {
    const tempFolder = getTempFolderPath();
    await fs.mkdir(tempFolder, { recursive: true });
    
    console.log(`[SPLIT] PDF yolu: ${pdfPath}`);
    console.log(`[SPLIT] Temp klasör: ${tempFolder}`);
    
    const pdfBytes = await fs.readFile(pdfPath);
    const pdfDoc = await PDFDocument.load(pdfBytes);
    const pageCount = pdfDoc.getPageCount();
    
    console.log(`[SPLIT] Sayfa sayısı: ${pageCount}`);
    
    const singlePagePaths: string[] = [];
    
    for (let i = 0; i < pageCount; i++) {
      const newPdf = await PDFDocument.create();
      const [copiedPage] = await newPdf.copyPages(pdfDoc, [i]);
      newPdf.addPage(copiedPage);
      
      const singlePageBytes = await newPdf.save();
      const singlePagePath = path.join(tempFolder, `page_${i + 1}.pdf`);
      await fs.writeFile(singlePagePath, singlePageBytes);
      singlePagePaths.push(singlePagePath);
      
      console.log(`[SPLIT] Sayfa ${i + 1} oluşturuldu: ${singlePagePath}`);
    }
    
    console.log(`[SPLIT] Tüm sayfalar oluşturuldu: ${singlePagePaths.length} dosya`);
    
    return {
      success: true,
      pageFiles: singlePagePaths,
      pageCount: pageCount
    };
  } catch (error) {
    console.error(`[SPLIT] PDF bölme hatası:`, error);
    return {
      success: false,
      error: (error as Error).message
    };
  }
};