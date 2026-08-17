#!/usr/bin/env bash
# Kullanilacak jpackage yolunu yazdirir.
#
#   find-jpackage.sh <beklenen-os.arch> <zulu21-onbellek-dizini>
#     <beklenen-os.arch>: aarch64 (Apple Silicon) | x86_64 (Intel)
#
# Sistemde Java 17+ jpackage varsa onu kullanmak istiyoruz (indirme yok), ama
# YALNIZCA hedefle ayni mimarideyse: jpackage uretilen .app'in launcher
# ikilisini (jpackageapplauncher) kendi JDK'sindan kopyalar, yani uygulamanin
# mimarisi jpackage'in mimarisidir. Intel bir JDK ile arm64 paket (veya tersi)
# uretilemez. Uygun degilse onbellege indirilecek yolu yazdiririz; indirmeyi
# Makefile'daki "jpackage-hazir" hedefi yapar.
set -uo pipefail

WANT_ARCH="${1:?beklenen os.arch verilmedi}"
CACHE_DIR="${2:?zulu21 onbellek dizini verilmedi}"
FALLBACK="$CACHE_DIR/bin/jpackage"

jp="$(command -v jpackage 2>/dev/null || true)"
if [ -z "$jp" ] || ! "$jp" --version >/dev/null 2>&1; then
  echo "$FALLBACK"; exit 0
fi

# jpackage'in yaninda duran java ile os.arch'i soruyoruz. /usr/bin/jpackage bir
# yonlendirici olabilir; o durumda /usr/bin/java da ayni JDK'ya yonlendigi icin
# okunan deger yine dogru olur.
jdir="$(dirname "$jp")"
arch=""
if [ -x "$jdir/java" ]; then
  arch="$("$jdir/java" -XshowSettings:properties -version 2>&1 \
          | awk -F'=' '/^[[:space:]]*os\.arch[[:space:]]*=/ { gsub(/[[:space:]]/,"",$2); print $2; exit }')"
fi

if [ "$arch" = "$WANT_ARCH" ]; then
  echo "$jp"
else
  echo "$FALLBACK"
fi
