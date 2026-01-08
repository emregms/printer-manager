import { contextBridge, ipcRenderer } from 'electron';

export type Settings = {
  printerName?: string;
  coldPrintMs?: number;
  coldCleanMs?: number;
  hotPrintMs?: number;
  hotCleanMs?: number;
};

export type PdfInfo = {
  exists: boolean;
  path?: string;
  name?: string;
  size?: number;
  lastModified?: string;
  error?: string;
};

export type OpenPdfResult = {
  path: string;
  name: string;
  size: number;
  lastModified: string;
} | null;

export type SplitPdfResult = {
  success: boolean;
  pageCount?: number;
  pages?: string[];
  error?: string;
};

export type BlankPdfResult = {
  success: boolean;
  path?: string;
  error?: string;
};

export type PreviewResult = {
  success: boolean;
  previewPath?: string;
  width?: number;
  height?: number;
  error?: string;
};

contextBridge.exposeInMainWorld('api', {
  getSettings: async (): Promise<Settings> => ipcRenderer.invoke('settings:get'),
  setSettings: async (payload: Partial<Settings>): Promise<Settings> => ipcRenderer.invoke('settings:set', payload),
  openPdf: async (): Promise<OpenPdfResult> => ipcRenderer.invoke('dialog:openPdf'),
  getPdfInfo: async (pdfPath: string): Promise<PdfInfo> => ipcRenderer.invoke('pdf:getInfo', pdfPath),
  listPrinters: async (): Promise<any[]> => ipcRenderer.invoke('printer:list'),
  splitPdf: async (pdfPath: string): Promise<SplitPdfResult> => ipcRenderer.invoke('pdf:split', pdfPath),
  createBlankPdf: async (): Promise<BlankPdfResult> => ipcRenderer.invoke('pdf:createBlank'),
  cleanupTempFiles: async (): Promise<{success: boolean; message?: string; error?: string}> => ipcRenderer.invoke('pdf:cleanup'),
  getTempFolderPath: async (): Promise<string> => ipcRenderer.invoke('pdf:getTempPath'),
  printPdf: async (args: { pdfPath: string; printerName: string; pageNumber?: number; landscape?: boolean; silent?: boolean; isFirstPage?: boolean }): Promise<{ ok: boolean; message?: string; error?: string }> => ipcRenderer.invoke('print:pdf', args),
  generatePreview: async (args: { pdfPath: string; pageNumber: number; width?: number; height?: number }): Promise<PreviewResult> => ipcRenderer.invoke('pdf:generatePreview', args),
});

declare global {
  interface Window {
    api: {
      getSettings: () => Promise<Settings>;
      setSettings: (payload: Partial<Settings>) => Promise<Settings>;
      openPdf: () => Promise<OpenPdfResult>;
      getPdfInfo: (pdfPath: string) => Promise<PdfInfo>;
      listPrinters: () => Promise<any[]>;
      splitPdf: (pdfPath: string) => Promise<SplitPdfResult>;
      createBlankPdf: () => Promise<BlankPdfResult>;
      cleanupTempFiles: () => Promise<{success: boolean; message?: string; error?: string}>;
      printPdf: (args: { pdfPath: string; printerName: string; pageNumber?: number; landscape?: boolean; silent?: boolean; isFirstPage?: boolean }) => Promise<{ ok: boolean; message?: string; error?: string }>;
      getTempFolderPath: () => Promise<string>;
      generatePreview: (args: { pdfPath: string; pageNumber: number; width?: number; height?: number }) => Promise<PreviewResult>;
    };
  }
}



