#!/usr/bin/env bash
# build/app/ -> build/TNBTeknolojiImza.app  (gomulu arm64 Java 11 runtime)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${RUNTIME:-$ROOT/.jre-cache/zulu11-runtime}"
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

# Ad-hoc imza (notarize edilmemistir)
find "$DEST/$APPNAME.app" -name '._*' -delete 2>/dev/null || true
codesign -s - --deep --force "$DEST/$APPNAME.app"
codesign --verify --strict "$DEST/$APPNAME.app" >/dev/null 2>&1 \
  && echo ">> imza gecerli (adhoc)" || { echo "HATA: imza dogrulanamadi" >&2; exit 1; }

echo ">> app: $DEST/$APPNAME.app ($(du -sh "$DEST/$APPNAME.app" | cut -f1))"
