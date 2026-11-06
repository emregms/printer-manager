#!/bin/sh
# PrinterManager'ın Samsung CLP-300 kuyruğunu kurar ya da kaldırır.
# root olarak çalışır: uygulama bunu macOS'un yönetici şifresi penceresiyle çağırır.
#
#   install-driver.sh install <kaynak-klasör> <kuyruk> <aygıt-uri> <açıklama>
#   install-driver.sh uninstall [kuyruk...]
#
# Kuyruk gelen işleri basmadan bekletir; PrinterManager onları alıp kendi
# penceresinde açar ve sayfa arası bekleme / elle çift yönle basar.
# Kurulan dosyalar:
#   /Library/Printers/PrinterManager/Filters/pminbox     yönlendirme filtresi
#   /Library/Printers/PrinterManager/<ppd>               kuyruğun PPD'si
#   /Library/Printers/PPDs/Contents/Resources/<ppd>      "Yazıcı Ekle" listesi için
# Başka kuyruklara (ör. Samsung'un eski sürücüsüyle kurulmuş olana) dokunmaz.

set -eu

DEST=/Library/Printers/PrinterManager
PPD_NAME=Samsung-CLP-300-PrinterManager.ppd
PPD_LIBRARY_DIR=/Library/Printers/PPDs/Contents/Resources
PPD_LIBRARY="$PPD_LIBRARY_DIR/Samsung CLP-300 PrinterManager.ppd"

usage() {
    echo "Kullanım: $0 install <kaynak> <kuyruk> <uri> <açıklama> | uninstall [kuyruk...]" >&2
    exit 2
}

case "${1:-}" in
install)
    [ $# -eq 5 ] || usage
    SRC=$2
    QUEUE=$3
    URI=$4
    DESCRIPTION=$5

    # Önceki sürümün dosyaları (ör. eski filtre) kalmasın
    rm -rf "$DEST"

    # CUPS, root'a ait olmayan ya da başkalarınca yazılabilen filtreleri çalıştırmaz
    install -d -o root -g wheel -m 755 "$DEST" "$DEST/Filters"
    install -o root -g wheel -m 755 "$SRC/pminbox" "$DEST/Filters/pminbox"
    install -o root -g wheel -m 644 "$SRC/$PPD_NAME" "$DEST/$PPD_NAME"

    if [ ! -d "$PPD_LIBRARY_DIR" ]; then
        install -d -o root -g admin -m 755 "$PPD_LIBRARY_DIR"
    fi
    install -o root -g wheel -m 644 "$SRC/$PPD_NAME" "$PPD_LIBRARY"

    # İndirilen uygulamadan kopyalanan dosyalarda karantina kalmasın
    xattr -cr "$DEST" 2>/dev/null || true
    xattr -c "$PPD_LIBRARY" 2>/dev/null || true

    # Gelen işler beklesin (PrinterManager alır); PrinterManager'ın kendi ham
    # işleri "-H immediate" ile gönderilir. Hata olursa kuyruk durmasın.
    lpadmin -p "$QUEUE" -D "$DESCRIPTION" -E -v "$URI" -P "$DEST/$PPD_NAME" \
        -o printer-is-shared=false -o printer-error-policy=abort-job \
        -o job-hold-until-default=indefinite
    cupsenable "$QUEUE"
    cupsaccept "$QUEUE"

    echo "Kuruldu: $QUEUE ($URI)"
    ;;
uninstall)
    shift
    for queue in "$@"; do
        lpadmin -x "$queue" || true
    done
    rm -rf "$DEST"
    rm -f "$PPD_LIBRARY"
    echo "Kaldırıldı"
    ;;
*)
    usage
    ;;
esac
