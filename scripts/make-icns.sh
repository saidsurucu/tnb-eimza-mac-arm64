#!/usr/bin/env bash
# assets/logo128.png -> assets/TNBTeknolojiImza.icns
# Kaynak eklentinin kendi logosu (128x128); buyuk boyutlar upscale edilir
# (kozmetik, kalite sinirli).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/assets/logo128.png}"
OUT="${2:-$ROOT/assets/TNBTeknolojiImza.icns}"

[ -f "$SRC" ] || { echo "HATA: kaynak yok: $SRC" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/icon.iconset"; mkdir -p "$ICONSET"

# Kare degilse seffaf dolguyla 512'lik kareye ortala
W="$(sips -g pixelWidth  "$SRC" | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')"
MASTER="$TMP/master.png"
if [ "$W" = "$H" ]; then
  sips -s format png -z 512 512 "$SRC" --out "$MASTER" >/dev/null
else
  sips -s format png -Z 480 "$SRC" --out "$MASTER" >/dev/null
  sips -p 512 512 "$MASTER" --out "$MASTER" >/dev/null
fi

for sz in 16 32 128 256 512; do
  sips -z "$sz" "$sz" "$MASTER" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz*2))
  [ "$dbl" -le 1024 ] && sips -z "$dbl" "$dbl" "$MASTER" \
    --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo ">> ikon: $OUT"
