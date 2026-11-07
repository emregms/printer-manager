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
 *
 * Çıkış kodu: 0 başarı, 2 kullanım, 3 yazıcı bağlı değil, 4 istek başarısız.
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

int main(int argc, char *argv[])
{
    int is_status = argc == 2 && strcmp(argv[1], "status") == 0;
    int is_xml = argc == 3 && strcmp(argv[1], "xml") == 0;
    if (!is_status && !is_xml) {
        fprintf(stderr, "Kullanım: %s status | xml <dosya>\n", argv[0]);
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
