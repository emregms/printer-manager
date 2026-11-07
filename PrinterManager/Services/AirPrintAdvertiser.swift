import Foundation
import OSLog
import dnssd

/// Paylaşılan kuyruğu iPhone ve iPad'e AirPrint yazıcısı olarak duyurur.
///
/// macOS'un yazıcı paylaşımı kuyruğu ağda duyurur, ama iOS'un AirPrint listesi için
/// baktığı "_universal" alt türünü ve URF kaydını eklemez; iPhone yazıcıyı görmez.
/// Bu sınıf aynı kuyruğu o işaretlerle ayrıca duyurur. İşler yine macOS'un yazdırma
/// sistemine (631) gider: pminbox bekletir, PrinterManager belgeyi alıp pencerede açar.
/// Duyuru uygulama çalıştığı sürece (pencere kapalıyken de) durur; işlemci harcamaz.
@MainActor
final class AirPrintAdvertiser {
    static let shared = AirPrintAdvertiser()
    
    private static let log = Logger(subsystem: "com.samsungclp300.printermanager", category: "airprint")
    private var service: DNSServiceRef?
    private var advertisedQueue: String?
    
    private init() {}
    
    /// Kuyruk paylaşılıyorsa duyurur, değilse duyuruyu kaldırır
    func update() {
        Task {
            let target = await Task.detached { () -> (queue: String, info: String, uuid: String?)? in
                let service = PrinterService.shared
                guard service.isPrinterSharingEnabled,
                      let queue = DriverInstaller.inboxQueues().first,
                      let status = service.queueStatus(queue), status.isShared else { return nil }
                return (queue, status.info, service.printerUUID(queue))
            }.value
            
            if let target = target {
                guard advertisedQueue != target.queue else { return }
                start(queue: target.queue, name: target.info, uuid: target.uuid)
            } else {
                stop()
            }
        }
    }
    
    private func start(queue: String, name: String, uuid: String?) {
        stop()
        
        // Apple'ın Bonjour Printing belirtimindeki anahtarlar. TLS anahtarı yok: iOS düz
        // IPP kullansın (macOS'un kendinden imzalı sertifikasıyla uğraşmasın).
        var keys: [(String, String)] = [
            ("txtvers", "1"),
            ("qtotal", "1"),
            ("rp", "printers/\(queue)"),
            ("ty", name),
            ("product", "(Samsung CLP-300)"),
            ("note", "PrinterManager"),
            ("priority", "0"),
            ("pdl", "application/octet-stream,application/pdf,image/jpeg,image/png,image/urf"),
            ("URF", "W8,SRGB24,CP1,RS300"),
            ("Color", "T"),
            ("Duplex", "F"),
            ("Transparent", "T"),
            ("Binary", "T"),
            ("PaperMax", "legal-A4"),
            ("kind", "document"),
            ("printer-state", "3"),
            ("air", "none"),
        ]
        if let uuid = uuid {
            keys.append(("UUID", uuid))
        }
        
        var txt = TXTRecordRef()
        TXTRecordCreate(&txt, 0, nil)
        defer { TXTRecordDeallocate(&txt) }
        for (key, value) in keys {
            let bytes = Array(value.utf8.prefix(255))
            _ = TXTRecordSetValue(&txt, key, UInt8(bytes.count), bytes)
        }
        
        var reference: DNSServiceRef?
        let error = DNSServiceRegister(
            &reference, 0, 0, name, "_ipp._tcp,_universal", nil, nil,
            UInt16(631).bigEndian, TXTRecordGetLength(&txt), TXTRecordGetBytesPtr(&txt),
            { _, _, errorCode, name, _, _, _ in
                let log = Logger(subsystem: "com.samsungclp300.printermanager", category: "airprint")
                if errorCode == kDNSServiceErr_NoError {
                    log.info("AirPrint duyurusu yayında: \(name.map { String(cString: $0) } ?? "?", privacy: .public)")
                } else {
                    log.error("AirPrint duyurusu başarısız: \(errorCode)")
                }
            },
            nil
        )
        guard error == kDNSServiceErr_NoError, let reference = reference else {
            Self.log.error("AirPrint duyurusu kaydedilemedi: \(error)")
            return
        }
        DNSServiceSetDispatchQueue(reference, .main)
        service = reference
        advertisedQueue = queue
        Self.log.info("AirPrint duyurusu başlatıldı: \(queue, privacy: .public)")
    }
    
    func stop() {
        if let service = service {
            DNSServiceRefDeallocate(service)
            Self.log.info("AirPrint duyurusu kaldırıldı")
        }
        service = nil
        advertisedQueue = nil
    }
}
