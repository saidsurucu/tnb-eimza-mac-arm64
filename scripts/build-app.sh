#!/usr/bin/env bash
# build/app/ -> build/TNBTeknolojiImza.app
# (gomulu Java 11 runtime; mimari kabuktan gelir: arm64 veya x86_64)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# MACH_ARCH: Mach-O adi (arm64 | x86_64), Makefile'dan gelir; tek basina
# calistirildiginda kabuktan okunur.
MACH_ARCH="${MACH_ARCH:-$(uname -m)}"

# Desteklenen en dusuk macOS: Intel'de hedef macOS 13 (Ventura), Apple Silicon
# zaten en dusuk macOS 11 ile geliyor. Onbellek dizini de mimariye gore ayrilir.
if [ "$MACH_ARCH" = "arm64" ]; then
  TARGET_ARCH="arm64"; MIN_MACOS="${MIN_MACOS:-11.0}"
else
  TARGET_ARCH="x64";   MIN_MACOS="${MIN_MACOS:-13.0}"
fi

RUNTIME="${RUNTIME:-$ROOT/.jre-cache/zulu11-runtime-$TARGET_ARCH}"
JPACKAGE="${JPACKAGE:-jpackage}"
APPNAME="TNBTeknolojiImza"
DISPLAYNAME="TNB Teknoloji İmza"
BUNDLE_ID="tr.org.tnb.teknoloji.imza"
DEST="$ROOT/build"

test -f "$ROOT/build/app/TNBTeknolojiImza.jar" || { echo "build/app yok — once 'make prep'"; exit 1; }
test -x "$RUNTIME/bin/java" || { echo "runtime yok — once 'make jre'"; exit 1; }

# bash 3.2 (macOS) + `set -u`: bos dizi genislemesi hata verir -> ${a[@]:+...}
ICON_ARG=()
[ -f "$ROOT/assets/$APPNAME.icns" ] && ICON_ARG=(--icon "$ROOT/assets/$APPNAME.icns")

rm -rf "$DEST/$APPNAME.app"
"$JPACKAGE" \
  --type app-image \
  --name "$APPNAME" \
  --input "$ROOT/build/app" \
  --main-jar TNBTeknolojiImza.jar \
  --main-class com.tnbt.imza.applet.MainApplet \
  --runtime-image "$RUNTIME" \
  ${ICON_ARG[@]:+"${ICON_ARG[@]}"} \
  --java-options "--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED" \
  --java-options "-Dfile.encoding=UTF-8" \
  --mac-package-identifier "$BUNDLE_ID" \
  --dest "$DEST"
# NOT: --java-options degerlerinde BOSLUK KULLANMA. jpackage bunlari
# Contents/app/*.cfg icine tirnaksiz yazar; bosluklu bir deger (orn.
# -Dapple.awt.application.name="TNB Teknoloji İmza") launcher tarafindan
# ayri argumanlara bolunur ve "Could not find or load main class Teknoloji"
# hatasi alirsiniz. Gorunen ad zaten CFBundleName/CFBundleDisplayName'den gelir.

PLIST="$DEST/$APPNAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAYNAME" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $DISPLAYNAME" "$PLIST"
# Retina'da keskin Swing (Java 11 = JEP 263)
/usr/libexec/PlistBuddy -c "Set :NSHighResolutionCapable true" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_MACOS" "$PLIST"

# Uretilen launcher gercekten hedef mimaride mi? jpackage launcher ikilisini
# KENDI JDK'sindan kopyalar; yanlis mimarideki bir jpackage sessizce Intel bir
# .app uretir (arm64 kart surucusu boyle bir surece yuklenemez, tersi de).
LAUNCHER="$DEST/$APPNAME.app/Contents/MacOS/$APPNAME"
BUILT_ARCHS="$(lipo -archs "$LAUNCHER" 2>/dev/null || echo '?')"
if ! printf '%s\n' $BUILT_ARCHS | grep -qx "$MACH_ARCH"; then
  echo "HATA: uretilen uygulama $MACH_ARCH degil (launcher: $BUILT_ARCHS)." >&2
  echo "      Kullanilan jpackage: $JPACKAGE" >&2
  exit 1
fi

# Ad-hoc imza (notarize edilmemistir)
find "$DEST/$APPNAME.app" -name '._*' -delete 2>/dev/null || true
codesign -s - --deep --force "$DEST/$APPNAME.app"
codesign --verify --strict "$DEST/$APPNAME.app" >/dev/null 2>&1 \
  && echo ">> imza gecerli (adhoc)" || { echo "HATA: imza dogrulanamadi" >&2; exit 1; }

echo ">> app: $DEST/$APPNAME.app [$BUILT_ARCHS, macOS $MIN_MACOS+] ($(du -sh "$DEST/$APPNAME.app" | cut -f1))"
