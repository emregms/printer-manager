#!/bin/sh
# PrinterManager'ın Samsung CLP-300 sürücüsünü kurar ya da kaldırır.
# root olarak çalışır: uygulama bunu macOS'un yönetici şifresi penceresiyle çağırır.
#
#   install-driver.sh install <kaynak-klasör> <foo2qpdl> <kuyruk> <aygıt-uri> <açıklama>
#   install-driver.sh uninstall [kuyruk...]
#
# Kurulum:
#   /Library/Printers/PrinterManager/Filters/pdftoqpdl   CUPS filtresi
#   /Library/Printers/PrinterManager/Filters/foo2qpdl    QPDL kodlayıcısı (GPL-2.0)
#   /Library/Printers/PrinterManager/<ppd>               kuyruğun PPD'si
#   /Library/Printers/PPDs/Contents/Resources/<ppd>      "Yazıcı Ekle" listesi için
# ve verilen USB aygıtına bu PPD ile bir CUPS kuyruğu ekler. Başka kuyruklara
# (ör. Samsung'un eski sürücüsüyle kurulmuş olana) dokunmaz.

set -eu

DEST=/Library/Printers/PrinterManager
PPD_NAME=Samsung-CLP-300-PrinterManager.ppd
PPD_LIBRARY_DIR=/Library/Printers/PPDs/Contents/Resources
PPD_LIBRARY="$PPD_LIBRARY_DIR/Samsung CLP-300 PrinterManager.ppd"

usage() {
    echo "Kullanım: $0 install <kaynak> <foo2qpdl> <kuyruk> <uri> <açıklama> | uninstall [kuyruk...]" >&2
    exit 2
}

case "${1:-}" in
install)
    [ $# -eq 6 ] || usage
    SRC=$2
    FOO2QPDL=$3
    QUEUE=$4
    URI=$5
    DESCRIPTION=$6

    # CUPS, root'a ait olmayan ya da başkalarınca yazılabilen filtreleri çalıştırmaz
    install -d -o root -g wheel -m 755 "$DEST" "$DEST/Filters"
    install -o root -g wheel -m 755 "$SRC/pdftoqpdl" "$DEST/Filters/pdftoqpdl"
    install -o root -g wheel -m 755 "$FOO2QPDL" "$DEST/Filters/foo2qpdl"
    install -o root -g wheel -m 644 "$SRC/$PPD_NAME" "$DEST/$PPD_NAME"
    install -o root -g wheel -m 644 "$SRC/foo2qpdl-COPYING.txt" "$DEST/foo2qpdl-COPYING.txt"

    if [ ! -d "$PPD_LIBRARY_DIR" ]; then
        install -d -o root -g admin -m 755 "$PPD_LIBRARY_DIR"
    fi
    install -o root -g wheel -m 644 "$SRC/$PPD_NAME" "$PPD_LIBRARY"

    # İndirilen uygulamadan kopyalanan dosyalarda karantina kalmasın
    xattr -cr "$DEST" 2>/dev/null || true
    xattr -c "$PPD_LIBRARY" 2>/dev/null || true

    # Hata olursa yalnızca o iş iptal olsun, kuyruk durmasın
    lpadmin -p "$QUEUE" -D "$DESCRIPTION" -E -v "$URI" -P "$DEST/$PPD_NAME" \
        -o printer-is-shared=false -o printer-error-policy=abort-job
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
