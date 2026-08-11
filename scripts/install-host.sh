#!/usr/bin/env bash
# Chrome "native messaging host" kaydini kurar/kaldirir.
#
# Uygulama cift tiklanarak degil, TARAYICI tarafindan calistirilir: eklenti
# imzalama isteyince Chrome bu manifest'teki "path"i baslatir ve stdin/stdout
# uzerinden JSON konusur. Manifest yoksa eklenti "uygulama kurulu degil" der.
#
# Kullanim:  install-host.sh [--uninstall] [uygulama-yolu]
set -euo pipefail

HOST_NAME="tnbtimzahost"
EXTENSION_ID="ppgjmopocehhllbjblnpdajkkkfghpan"
APP_DEFAULT="/Applications/TNBTeknolojiImza.app"

UNINSTALL=0
if [ "${1:-}" = "--uninstall" ]; then UNINSTALL=1; shift; fi
APP="${1:-${APP_PATH:-$APP_DEFAULT}}"
EXEC="$APP/Contents/MacOS/TNBTeknolojiImza"

SUPPORT="$HOME/Library/Application Support"
# Chromium tabanli tarayicilarin profil kokleri
BROWSER_DIRS=(
  "$SUPPORT/Google/Chrome"
  "$SUPPORT/Google/Chrome Beta"
  "$SUPPORT/Google/Chrome Dev"
  "$SUPPORT/Google/Chrome Canary"
  "$SUPPORT/Chromium"
  "$SUPPORT/Microsoft Edge"
  "$SUPPORT/BraveSoftware/Brave-Browser"
  "$SUPPORT/Vivaldi"
  "$SUPPORT/Yandex/YandexBrowser"
  "$SUPPORT/com.operasoftware.Opera"
)

if [ "$UNINSTALL" = "1" ]; then
  n=0
  for d in "${BROWSER_DIRS[@]}"; do
    f="$d/NativeMessagingHosts/$HOST_NAME.json"
    if [ -f "$f" ]; then rm -f "$f"; echo "   silindi: $f"; n=$((n+1)); fi
  done
  echo ">> $n kayit kaldirildi."
  exit 0
fi

[ -x "$EXEC" ] || { echo "HATA: uygulama bulunamadi: $EXEC" >&2; exit 1; }

installed=0
skipped=()
for d in "${BROWSER_DIRS[@]}"; do
  # Yalnizca gercekten kurulu tarayicilar icin yaz (bos klasor birakmayalim).
  if [ ! -d "$d" ]; then skipped+=("$(basename "$d")"); continue; fi
  mkdir -p "$d/NativeMessagingHosts"
  cat > "$d/NativeMessagingHosts/$HOST_NAME.json" <<EOF
{
  "name": "$HOST_NAME",
  "description": "TnbTeknoloji Imza Chrome Native Messaging Host (macOS arm64)",
  "path": "$EXEC",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF
  echo "   kayit: $d/NativeMessagingHosts/$HOST_NAME.json"
  installed=$((installed+1))
done

if [ "$installed" = "0" ]; then
  echo "!! Chromium tabanli hicbir tarayici profili bulunamadi." >&2
  echo "!! Chrome'u bir kez acip kapatin, sonra bu betigi tekrar calistirin." >&2
  exit 1
fi

echo ">> $installed tarayiciya kaydedildi (host: $HOST_NAME)."
[ "${#skipped[@]}" -gt 0 ] && echo "   (kurulu olmayanlar atlandi: ${skipped[*]})"
echo ">> Kayit sonrasi tarayiciyi TAMAMEN kapatip yeniden acin."
