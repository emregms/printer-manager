import React, { useEffect, useState } from 'react';
import { EnhancedPdfViewer } from './components/EnhancedPdfViewer';
import { usePrintSplitPdf, PrintSettings } from './utils/usePrintSplitPdf';
import './styles.css';
import './components/pdfViewer.css';

// Artık sıcak/soğuk modu kullanmıyoruz

type Settings = {
  printerName?: string;
  printMs?: number;
  cleanMs?: number;
};

export const App: React.FC = () => {
  // Genel durum
  const [settings, setSettings] = useState<Settings>({});
  const [pdfPath, setPdfPath] = useState<string | null>(null);
  const [duplex, setDuplex] = useState<boolean>(false);
  const [printers, setPrinters] = useState<{ name: string }[]>([]);
  const [totalPages, setTotalPages] = useState<number>(1);
  const [showFlipPagesDialog, setShowFlipPagesDialog] = useState<boolean>(false);

  // Bekleme süresi
  const waitMs = {
    printMs: settings.printMs ?? 30000,
    cleanMs: settings.cleanMs ?? 8000
  };

  // Yazdırma yöneticisini başlat - PDF'i bölme ve ilk sayfayı hemen yazdırma destekli
  const printManager = usePrintSplitPdf({
    pdfPath,
    settings: {
      printerName: settings.printerName || '',
      printMs: waitMs.printMs,
      cleanMs: waitMs.cleanMs,
      duplex
    },
    totalPages
  });

  // İlk yükleme
  useEffect(() => {
    (async () => {
      // Ayarları yükle
      const s = await window.api.getSettings();
      setSettings(s);

      // Yazıcıları yükle
      const printers = await window.api.listPrinters();
      setPrinters(printers);

      // Temp klasör yolunu yazdır
      const tempPath = await window.api.getTempFolderPath();
      console.log(`[APP] Temp klasör yolu: ${tempPath}`);
    })();
  }, []);

  // PDF seçme işlemi
  const handlePickPdf = async () => {
    const pdfInfo = await window.api.openPdf();
    if (pdfInfo) {
      setPdfPath(pdfInfo.path);
      printManager.addLog(`PDF yüklendi: ${pdfInfo.name}, Boyut: ${formatFileSize(pdfInfo.size)}`);
    }
  };

  // Ayarları kaydetme
  const handleSaveSettings = async (patch: Partial<Settings>) => {
    const s = await window.api.setSettings({ ...settings, ...patch });
    setSettings(s);
  };

  // Sayfa sayısı değişikliği - sadece bir kez log ekle
  const handlePageCountChange = (count: number) => {
    setTotalPages(count);
    // Sayfa sayısı bilgisini sadece bir kez log'a ekle
    if (printManager.status.logs.length === 0 || !printManager.status.logs.some(log => log.includes('PDF sayfa sayısı:'))) {
      printManager.addLog(`PDF sayfa sayısı: ${count}`);
    }
  };

  // Manuel sayfa sayısı değişikliği
  const handleManualPageCountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseInt(e.target.value || '1', 10);
    setTotalPages(Math.max(1, value));
  };

  // Yazdırma işlemini başlat
  const handleStartPrinting = () => {
    printManager.startPrinting(totalPages);
    console.log(`Yazdırma başlatılıyor, sayfa sayısı: ${totalPages}`);
  };
  
  // Yazdırma durumunu izle - çift yönlü yazdırma için dialog gösterme
  useEffect(() => {
    if (printManager.status.error === 'FLIP_PAGES_DIALOG') {
      setShowFlipPagesDialog(true);
    }
  }, [printManager.status.error]);

  return (
    <div className="app-container">
      {/* Sol panel: Ayarlar ve PDF Yükleme */}
      <section className="app-sidebar">
        {/* Ayarlar kartı */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Yazıcı Ayarları</h2>
          </div>

          <div className="card-body">
            <label>
              <span>Yazıcı</span>
              <select
                value={settings.printerName ?? ''}
                onChange={e => handleSaveSettings({ printerName: e.target.value })}>
                <option value="">Seçiniz</option>
                {printers.map(p => <option key={p.name} value={p.name}>{p.name}</option>)}
              </select>
            </label>

            <div className="settings-grid">
              {/* Yazdırma süresi */}
              <div className="setting-item">
                <div className="setting-header">
                  <span>Yazdırma süresi</span>
                  <strong>{Math.round((settings.printMs ?? 30000) / 1000)} sn</strong>
                </div>
                <input
                  type="range"
                  min={10000}
                  max={60000}
                  step={1000}
                  value={settings.printMs ?? 30000}
                  onChange={e => handleSaveSettings({ printMs: Number(e.target.value) })}
                />
              </div>

              {/* Temizlik süresi */}
              <div className="setting-item">
                <div className="setting-header">
                  <span>Temizlik süresi</span>
                  <strong>{Math.round((settings.cleanMs ?? 8000) / 1000)} sn</strong>
                </div>
                <input
                  type="range"
                  min={2000}
                  max={15000}
                  step={500}
                  value={settings.cleanMs ?? 8000}
                  onChange={e => handleSaveSettings({ cleanMs: Number(e.target.value) })}
                />
              </div>
            </div>
          </div>
        </div>

        {/* PDF Yazdırma kartı */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">PDF Yazdırma</h2>
          </div>

          <div className="card-body">
            <button
              className="btn btn-primary"
              onClick={handlePickPdf}
              disabled={printManager.status.isPrinting}>
              PDF Seç
            </button>

            {pdfPath && (
              <div className="pdf-selection-info">
                <div className="selected-file">
                  <strong>Seçili PDF:</strong> {pdfPath.split('\\').pop()}
                </div>
                <div className="file-path">
                  {pdfPath}
                </div>
              </div>
            )}

            <div className="print-options">
              {/* Sayfa sayısı otomatik tespit edildiği için manuel giriş alanını kaldırıldı */}


              <label className="duplex-option">
                <span>Çift yönlü (kılavuzlu)</span>
                <input
                  type="checkbox"
                  checked={duplex}
                  onChange={e => setDuplex(e.target.checked)}
                  disabled={printManager.status.isPrinting}
                />
              </label>

              <button
                className={`btn ${printManager.status.isPrinting ? 'btn-danger' : 'btn-success'}`}
                onClick={printManager.status.isPrinting ? printManager.cancelPrinting : handleStartPrinting}
                disabled={!pdfPath || !settings.printerName || showFlipPagesDialog}>
                {printManager.status.isPrinting ? 'Yazdırmayı İptal Et' : 'Yazdırmayı Başlat'}
              </button>
            </div>
          </div>
        </div>

        {/* Yazıcı Günlüğü */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Yazdırma Günlüğü</h2>
          </div>
          <div className="log-container">
            {printManager.status.logs.length > 0 ? (
              printManager.status.logs.map((log, i) => (
                <div key={i} className="log-line">{log}</div>
              ))
            ) : (
              <div className="log-placeholder">Henüz yazdırma işlemi yapılmadı</div>
            )}
          </div>
        </div>
      </section>

      {/* Sağ panel: PDF Önizleme ve Yazdırma Durumu */}
      <section className="app-main">
        {/* Sayfaları çevirme diyaloğu */}
        {showFlipPagesDialog && (
          <div className="card flip-pages-dialog">
            <div className="card-header">
              <h2 className="card-title">Sayfaları Çeviriniz</h2>
            </div>
            <div className="card-body">
              <p>Lütfen kağıtları ters çevirip yazıcıya yükleyiniz.</p>
              <p>Tek numaralı sayfalar yazdırıldı, şimdi çift numaralı sayfaları yazdıracağız.</p>
              <button
                className="btn btn-primary"
                onClick={() => {
                  setShowFlipPagesDialog(false);
                  // Hata durumunu temizle
                  printManager.status.error = null;
                  printManager.startPrinting(totalPages, true); // İkinci parametre: çift sayfaları yazdır
                }}>
                Kağıtları Çevirdim, Devam Et
              </button>
            </div>
          </div>
        )}
        {/* Yazdırma durumu */}
        {printManager.status.isPrinting && (
          <div className="card print-status-card">
            <div className="card-header">
              <h2 className="card-title">Yazdırma Durumu</h2>
              <div className="page-counter">
                {printManager.status.currentPage ?? '-'}/{totalPages}
              </div>
            </div>

            <div className="card-body">
              <div className="print-progress">
                <div className="progress-info">
                  <div>
                    {printManager.status.isCleaningPhase ? 'Belt Temizleme' : 'Sayfa Yazdırma'}
                  </div>
                  <div>
                    Kalan: {Math.ceil(printManager.status.timeRemaining / 1000)} sn
                  </div>
                </div>

                <div className="progress-bar">
                  <div
                    className={`progress-bar-fill ${printManager.status.isCleaningPhase ? 'cleaning' : ''}`}
                    style={{ width: `${(1 - printManager.status.timeRemaining / (printManager.status.isCleaningPhase ? waitMs.cleanMs : waitMs.printMs)) * 100}%` }}>
                  </div>
                </div>
              </div>

              {printManager.status.error && (
                <div className="error-message">
                  {printManager.status.error}
                </div>
              )}
            </div>
          </div>
        )}

        {/* PDF Önizleme */}
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">PDF Önizleme</h2>
          </div>
          <div className="card-body">
            <EnhancedPdfViewer
              pdfPath={pdfPath}
              onPageCountChange={handlePageCountChange}
              currentPrintingPage={printManager.status.currentPage}
            />
            <div className="button-row">
              <button 
                className="btn btn-secondary" 
                onClick={() => {
                  setPdfPath(null);
                  setTotalPages(1);
                  printManager.status.logs = [];
                }}
                disabled={printManager.status.isPrinting}
              >
                Sıfırla
              </button>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
};

// Yardımcı fonksiyonlar
const formatFileSize = (bytes: number): string => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};