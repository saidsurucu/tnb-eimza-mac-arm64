#!/usr/bin/env bash
# Tarayicisiz duman testi: Chrome'un native-messaging cerceve formatini taklit
# edip uygulamaya "selectCertificate" istegi gonderir ve logu ozetler.
#
# Ne dogrular:
#   - jpackage launcher'i stdin/stdout'u dogru aktariyor mu
#   - PKCS#11 modulleri (AKIS dahil) uygulamanin mimarisinde yukleniyor mu
#     (surucu ile uygulama farkli mimarideyse "incompatible architecture")
#   - IAIK native katmani kalintisi (UnsatisfiedLinkError) kalmis mi
#
# Kart takiliysa sertifika secim penceresi acilir; degilse "sertifika yok" der.
set -uo pipefail

APP="${1:-/Applications/TNBTeknolojiImza.app}"
EXEC="$APP/Contents/MacOS/TNBTeknolojiImza"
WAIT="${WAIT:-20}"
LOGDIR="$HOME/Library/Logs/TNBTeknolojiImza"

[ -x "$EXEC" ] || { echo "HATA: uygulama yok: $EXEC" >&2; exit 1; }

APP_ARCH="$(lipo -archs "$EXEC" 2>/dev/null | awk '{print $1}')"
[ -n "$APP_ARCH" ] || APP_ARCH="$(uname -m)"
echo ">> uygulama mimarisi: $APP_ARCH"

MSG="$(mktemp)"; trap 'rm -f "$MSG"' EXIT
/usr/bin/python3 - "$MSG" <<'PY'
import json, struct, sys
body = json.dumps({
    "extensionVersion": "1.0.0",
    "isPkcs11Supported": True,
    "isCspSupported": False,
    "logLevel": "255",
    "language": "tr",
    "request": {"functionName": "selectCertificate"},
}).encode("utf-8")
open(sys.argv[1], "wb").write(struct.pack("<I", len(body)) + body)
PY

rm -f "$LOGDIR/TnbTeknolojiImza.log" "$LOGDIR/TnbTeknolojiImza.err.log"

echo ">> uygulama calistiriliyor (en fazla ${WAIT}s; pencere acilirsa kapatabilirsiniz)"
"$EXEC" < "$MSG" > /dev/null 2>&1 &
PID=$!
for _ in $(seq "$WAIT"); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo
echo "----- log ($LOGDIR) -----"
# Uygulama yanit JSON'unu (base64 sertifika dahil) loga da yaziyor; terminale
# kilometrelerce base64 dokmemek icin uzun satirlari kisaltiyoruz.
if [ -f "$LOGDIR/TnbTeknolojiImza.log" ]; then
  awk 'length > 160 { print substr($0,1,160) "  …(" length " karakter, kisaltildi)"; next } { print }' \
    "$LOGDIR/TnbTeknolojiImza.log"
else
  echo "(log yok)"
fi
ERR="$(cat "$LOGDIR/TnbTeknolojiImza.err.log" 2>/dev/null || true)"
if [ -n "$ERR" ]; then echo "----- stderr -----"; echo "$ERR"; fi
echo "-------------------------"

fail=0
if ! grep -q 'MODULE PATH BU' "$LOGDIR/TnbTeknolojiImza.log" 2>/dev/null; then
  echo "✗ hicbir PKCS#11 modulu denenmemis (istek uygulamaya ulasmadi?)"; fail=1
else
  echo "✓ PKCS#11 modulleri denendi:"
  grep 'MODULE PATH BU' "$LOGDIR/TnbTeknolojiImza.log" | sed 's/^/    /'
fi
# Surucu ile uygulama farkli mimarideyse dyld "incompatible architecture" der;
# kullaniciya hangi surucunun hangi mimaride oldugunu da gosterelim.
if printf '%s' "$ERR" | grep -qi 'incompatible architecture'; then
  echo "✗ kart surucusu uygulamayla ayni mimaride degil (uygulama: $APP_ARCH)"
  for drv in /usr/local/lib/libakisp11.dylib /usr/local/lib/libeTPkcs11.dylib \
             /usr/local/lib/libaetpkss.dylib; do
    [ -f "$drv" ] && echo "    $drv  [$(lipo -archs "$drv" 2>/dev/null || echo '?')]"
  done
  echo "    Surucunun $APP_ARCH surumunu kurun: https://akiskart.bilgem.tubitak.gov.tr/tr/destek/"
  fail=1
fi
if printf '%s' "$ERR" | grep -q 'UnsatisfiedLinkError'; then
  echo "✗ native kutuphane hatasi surüyor (yama uygulanmamis)"; fail=1
elif printf '%s' "$ERR" | grep -q 'Exception'; then
  echo "✗ calisma zamani istisnasi var (yukariya bakin)"; fail=1
else
  echo "✓ istisna yok"
fi

echo
if [ "$fail" = "0" ]; then
  echo "SONUC: duman testi gecti. Gercek imza icin kart takip tarayicidan deneyin."
else
  echo "SONUC: duman testi BASARISIZ."
fi
exit "$fail"
