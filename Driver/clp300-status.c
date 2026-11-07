/*
 * clp300-status: Samsung CLP-300'ün durumunu USB kontrol kanalından okur.
 *
 * Yazıcıya baskı verisi göndermez ve USB aygıtını açmaz (yazdırma sürerken
 * CUPS'a karışmaz); yalnızca okuma yapan kontrol istekleri kullanır:
 *   - Samsung isteği 0x02: 8 baytlık durum kodu. Bayt 0 önem derecesi
 *     (01 normal, 02 uyarı, 04 hata), bayt 1-3 durum, bayt 4-7 toner
 *     seviyesi % (siyah, camgöbeği, macenta, sarı; ff = bilinmiyor).
 *   - Samsung isteği 0x0D: yazıcının kendi durum tablosu (SM.xml): her
 *     durumun maskesi, kodu ve açıklaması.
 *   - Yazıcı sınıfı GET_DEVICE_ID (IEEE 1284 kimliği) ve GET_PORT_STATUS.
 * İstek parametreleri Samsung'un Mac sürücüsündeki durum izleyicisinden
 * (commandtosec), birlikte çalışabilirlik için çıkarıldı.
 *
 *   clp300-status status        code/deviceid/port satırları
 *   clp300-status xml <dosya>   durum tablosunu dosyaya yazar
 *   clp300-status pjl <komut>   PJL komutu gönderir, yanıtı yazar. Yalnızca
 *                               güç tasarrufu ayarı ve sorgular (INQUIRE,
 *                               DINQUIRE, INFO, DEFAULT POWERSAVE...) kabul
 *                               edilir: sayfa basacak bir şey gönderilmez.
 *                               Yazıcı arayüzü açılır; yazdırırken kullanılamaz.
 *
 * Güç tasarrufu (CLP-300'de denendi): DEFAULT POWERSAVETIME dakika alır ve
 * 5/10/15/30/45/60/120'ye yuvarlar; DINQUIRE kademe (0-6), INQUIRE geçerli
 * dakikayı döndürür. Yeni kalıcı değer @PJL RESET ile hemen değişmedi.
 *
 * Çıkış kodu: 0 başarı, 2 kullanım, 3 yazıcı bağlı değil, 4 istek başarısız,
 * 5 yazıcı meşgul (arayüz başka bir işte açık).
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SAMSUNG_VENDOR_ID   0x04e8
#define CLP300_PRODUCT_ID   0x3272

#define REQ_STATUS_CODE     0x02
#define REQ_STATUS_TABLE    0x0d
#define TABLE_CHUNK         255
#define TABLE_MAX           (256 * 1024)

static IOUSBDeviceInterface182 **device;

static int find_printer(void)
{
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    SInt32 vendor = SAMSUNG_VENDOR_ID, product = CLP300_PRODUCT_ID;
    CFNumberRef vendorRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &vendor);
    CFNumberRef productRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &product);
    CFDictionarySetValue(match, CFSTR("idVendor"), vendorRef);
    CFDictionarySetValue(match, CFSTR("idProduct"), productRef);
    CFRelease(vendorRef);
    CFRelease(productRef);

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!service) {
        return -1;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || !plugin) {
        return -1;
    }
    (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182), (LPVOID *)&device);
    (*plugin)->Release(plugin);
    return device ? 0 : -1;
}

/* Cihazdan bilgisayara kontrol isteği; okunan bayt sayısını döndürür, hata -1 */
static int control_in(UInt8 type, UInt8 request, UInt16 value, UInt16 index, void *buffer, UInt16 length)
{
    IOUSBDevRequestTO r;
    memset(&r, 0, sizeof(r));
    r.bmRequestType = type;
    r.bRequest = request;
    r.wValue = value;
    r.wIndex = index;
    r.wLength = length;
    r.pData = buffer;
    r.noDataTimeout = 5000;
    r.completionTimeout = 5000;

    if ((*device)->DeviceRequestTO(device, &r) != kIOReturnSuccess) {
        return -1;
    }
    return (int)r.wLenDone;
}

static int print_status(void)
{
    UInt8 code[8];
    if (control_in(0xc1, REQ_STATUS_CODE, 0, 0, code, sizeof(code)) != 8) {
        fprintf(stderr, "Durum kodu okunamadı\n");
        return 4;
    }
    printf("code:");
    for (int i = 0; i < 8; i++) {
        printf(" %02x", code[i]);
    }
    printf("\n");

    /* GET_DEVICE_ID: ilk 2 bayt büyük-endian uzunluk (kendisi dahil) */
    UInt8 id[1024];
    memset(id, 0, sizeof(id));
    if (control_in(0xa1, 0, 0, 0, id, sizeof(id) - 1) > 2) {
        int length = (id[0] << 8) | id[1];
        if (length > 2 && length < (int)sizeof(id)) {
            printf("deviceid: %.*s\n", length - 2, id + 2);
        }
    }

    /* GET_PORT_STATUS: bit 5 kağıt yok, bit 4 seçili, bit 3 hata yok */
    UInt8 port = 0;
    if (control_in(0xa1, 1, 0, 0, &port, 1) == 1) {
        printf("port: %02x\n", port);
    }
    return 0;
}

static int save_table(const char *path)
{
    /* Başlık (8 bayt) tabloyu hazırlatır; ardından 1'den başlayan parçalar.
     * Başlıktaki boyutlar içerikle tutarlı değil: kapanış etiketine kadar oku. */
    UInt8 header[8];
    if (control_in(0xc1, REQ_STATUS_TABLE, 0, 0, header, sizeof(header)) < 0) {
        fprintf(stderr, "Durum tablosu başlığı okunamadı\n");
        return 4;
    }

    char *table = malloc(TABLE_MAX + 1);
    size_t total = 0;
    const char *closing = "</StatusMonitorInfo>";
    char *end = NULL;

    for (UInt16 chunk = 1; total + TABLE_CHUNK <= TABLE_MAX; chunk++) {
        int n = control_in(0xc1, REQ_STATUS_TABLE, chunk, 0, table + total, TABLE_CHUNK);
        if (n <= 0) {
            break;
        }
        total += (size_t)n;
        table[total] = '\0';
        if ((end = strstr(table, closing)) != NULL) {
            break;
        }
    }

    if (!end) {
        fprintf(stderr, "Durum tablosu eksik geldi (%zu bayt)\n", total);
        free(table);
        return 4;
    }

    FILE *out = fopen(path, "wb");
    if (!out) {
        perror(path);
        free(table);
        return 4;
    }
    fwrite(table, 1, (size_t)(end - table) + strlen(closing), out);
    fclose(out);
    free(table);
    return 0;
}

/* Yalnızca okuma ve güç tasarrufu ayarı: yanlışlıkla baskı verisi gönderilmesin */
static int pjl_allowed(const char *command)
{
    const char *allowed[] = {
        "@PJL INQUIRE ", "@PJL DINQUIRE ", "@PJL INFO ",
        "@PJL DEFAULT POWERSAVE = ", "@PJL DEFAULT POWERSAVETIME = ",
    };
    if (strpbrk(command, "\r\n\033")) {
        return 0;
    }
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); i++) {
        if (strncmp(command, allowed[i], strlen(allowed[i])) == 0) {
            return 1;
        }
    }
    return 0;
}

/* Yazıcı sınıfı arayüzünü (bInterfaceClass 7) bulur */
static io_service_t find_printer_interface(void)
{
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &iterator) != KERN_SUCCESS) {
        return 0;
    }
    io_service_t found = 0, candidate;
    while (!found && (candidate = IOIteratorNext(iterator))) {
        int vendor = 0, product = 0, class = 0;
        CFTypeRef value;
        if ((value = IORegistryEntrySearchCFProperty(candidate, kIOServicePlane, CFSTR("idVendor"), NULL,
                                                     kIORegistryIterateRecursively | kIORegistryIterateParents))) {
            CFNumberGetValue(value, kCFNumberIntType, &vendor);
            CFRelease(value);
        }
        if ((value = IORegistryEntrySearchCFProperty(candidate, kIOServicePlane, CFSTR("idProduct"), NULL,
                                                     kIORegistryIterateRecursively | kIORegistryIterateParents))) {
            CFNumberGetValue(value, kCFNumberIntType, &product);
            CFRelease(value);
        }
        if ((value = IORegistryEntryCreateCFProperty(candidate, CFSTR("bInterfaceClass"), NULL, 0))) {
            CFNumberGetValue(value, kCFNumberIntType, &class);
            CFRelease(value);
        }
        if (vendor == SAMSUNG_VENDOR_ID && product == CLP300_PRODUCT_ID && class == 7) {
            found = candidate;
        } else {
            IOObjectRelease(candidate);
        }
    }
    IOObjectRelease(iterator);
    return found;
}

/* PJL komutunu bulk OUT ile gönderir, bulk IN'den gelen yanıtı yazar */
static int send_pjl(const char *command)
{
    io_service_t service = find_printer_interface();
    if (!service) {
        fprintf(stderr, "CLP-300 USB'de bulunamadı\n");
        return 3;
    }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || !plugin) {
        return 4;
    }
    IOUSBInterfaceInterface300 **interface = NULL;
    (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&interface);
    (*plugin)->Release(plugin);
    if (!interface) {
        return 4;
    }
    if ((*interface)->USBInterfaceOpen(interface) != kIOReturnSuccess) {
        fprintf(stderr, "Yazıcı meşgul (yazdırıyor olabilir)\n");
        (*interface)->Release(interface);
        return 5;
    }

    UInt8 endpoints = 0, in_pipe = 0, out_pipe = 0;
    (*interface)->GetNumEndpoints(interface, &endpoints);
    for (UInt8 pipe = 1; pipe <= endpoints; pipe++) {
        UInt8 direction, number, type, interval;
        UInt16 max_packet;
        (*interface)->GetPipeProperties(interface, pipe, &direction, &number, &type, &max_packet, &interval);
        if (type == kUSBBulk && direction == kUSBIn) in_pipe = pipe;
        if (type == kUSBBulk && direction == kUSBOut) out_pipe = pipe;
    }

    char buffer[4096];
    UInt32 size;

    /* Önceki bir sorgudan kalan yanıt varsa at */
    for (int drained = 0; in_pipe && drained < 4; drained++) {
        size = sizeof(buffer);
        if ((*interface)->ReadPipeTO(interface, in_pipe, buffer, &size, 200, 200) != kIOReturnSuccess || size == 0) {
            break;
        }
    }

    int result = 4;
    char message[512];
    int length = snprintf(message, sizeof(message), "\033%%-12345X@PJL\r\n%s\r\n\033%%-12345X", command);
    if (out_pipe && length < (int)sizeof(message) &&
        (*interface)->WritePipeTO(interface, out_pipe, message, (UInt32)length, 3000, 3000) == kIOReturnSuccess) {
        result = 0;
        /* Yanıt parça parça ve gecikmeli gelir; PJL yanıtı form-feed (\f) ile biter.
         * Yanıtı olmayan komutlarda (DEFAULT) zaman aşımı normal. */
        int expects_reply = strncmp(command, "@PJL DEFAULT ", 13) != 0;
        int waited_ms = 0;
        while (in_pipe && expects_reply && waited_ms < 5000) {
            size = sizeof(buffer);
            IOReturn read = (*interface)->ReadPipeTO(interface, in_pipe, buffer, &size, 500, 500);
            if (read == kIOReturnSuccess && size > 0) {
                fwrite(buffer, 1, size, stdout);
                if (memchr(buffer, '\f', size)) {
                    break;
                }
            } else {
                waited_ms += 500;
                if (read != kIOReturnSuccess) {
                    (*interface)->ClearPipeStallBothEnds(interface, in_pipe);
                }
            }
        }
        fflush(stdout);
    }

    (*interface)->USBInterfaceClose(interface);
    (*interface)->Release(interface);
    return result;
}

int main(int argc, char *argv[])
{
    if (argc == 3 && strcmp(argv[1], "pjl") == 0) {
        if (!pjl_allowed(argv[2])) {
            fprintf(stderr, "İzin verilmeyen PJL komutu\n");
            return 2;
        }
        return send_pjl(argv[2]);
    }

    int is_status = argc == 2 && strcmp(argv[1], "status") == 0;
    int is_xml = argc == 3 && strcmp(argv[1], "xml") == 0;
    if (!is_status && !is_xml) {
        fprintf(stderr, "Kullanım: %s status | xml <dosya> | pjl <komut>\n", argv[0]);
        return 2;
    }

    if (find_printer() != 0) {
        fprintf(stderr, "CLP-300 USB'de bulunamadı\n");
        return 3;
    }

    int result = is_status ? print_status() : save_table(argv[2]);
    (*device)->Release(device);
    return result;
}
