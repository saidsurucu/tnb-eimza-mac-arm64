#!/usr/bin/env bash
# app/ (dokunulmamis satici payload'u) -> build/app/ (yamali).
# Tracked dosyalara ASLA dokunmaz.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app"
DST="$ROOT/build/app"
CACHE="$ROOT/.jre-cache"
WORK="$ROOT/build/_patch"

VENDOR_JAR="$SRC/TNBTeknolojiImza.jar"
WRAPPER_JAR="$SRC/sunpkcs11-wrapper-1.4.10.jar"
OUT_JAR="$DST/TNBTeknolojiImza.jar"
JAVASSIST_VER="3.30.2-GA"
JAVASSIST_JAR="$CACHE/javassist-$JAVASSIST_VER.jar"
JAVASSIST_URL="https://repo1.maven.org/maven2/org/javassist/javassist/$JAVASSIST_VER/javassist-$JAVASSIST_VER.jar"

JDK="${JDK:-}"
if [ -z "$JDK" ]; then
  # Kabugun mimarisi hedef mimaridir (arm64 | x86_64); java_home ayni adlari kullanir.
  JDK="$(/usr/libexec/java_home -v 11 -a "$(uname -m)" 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
fi
[ -x "$JDK/bin/javac" ] || { echo "HATA: javac bulunamadi (JDK=$JDK). Once 'make jre'." >&2; exit 1; }

test -f "$VENDOR_JAR"  || { echo "HATA: $VENDOR_JAR yok" >&2; exit 1; }
test -f "$WRAPPER_JAR" || { echo "HATA: $WRAPPER_JAR yok" >&2; exit 1; }

if [ ! -f "$JAVASSIST_JAR" ]; then
  echo ">> javassist indiriliyor..."
  mkdir -p "$CACHE"
  curl -fsSL "$JAVASSIST_URL" -o "$JAVASSIST_JAR"
fi

rm -rf "$DST" "$WORK"
mkdir -p "$DST" "$WORK/classes" "$WORK/patcher"

echo ">> satici jar aciliyor"
( cd "$WORK/classes" && unzip -oq "$VENDOR_JAR" )

# Jar imzali (META-INF/1.SF + 1.RSA). Icerigi degistirdigimiz icin imza
# kalintilari kalirsa JVM SecurityException atar; manifest'i de sadelestiriyoruz
# (orijinali her sinifin SHA-256'sini tasiyan ~35 KB'lik bir liste).
rm -f "$WORK"/classes/META-INF/*.SF "$WORK"/classes/META-INF/*.RSA "$WORK"/classes/META-INF/*.DSA
printf 'Manifest-Version: 1.0\nMain-Class: com.tnbt.imza.applet.MainApplet\n\n' \
  > "$WORK/classes/META-INF/MANIFEST.MF"

# IAIK'in hata mesajlari paketi sunpkcs11-wrapper'da YOK ama Pkcs11Shell
# yapicisi bu ResourceBundle'i acmaya calisiyor -> saklayip geri koyuyoruz.
EM="iaik/pkcs/pkcs11/wrapper/ExceptionMessages.properties"
test -f "$WORK/classes/$EM" || { echo "HATA: $EM satici jar'inda yok" >&2; exit 1; }
cp "$WORK/classes/$EM" "$WORK/ExceptionMessages.properties"

# NOT: Bu adim mimariden bagimsizdir. .jnilib'in x86_64 dilimi VAR, yani Intel
# Mac'te teorik olarak yuklenebilirdi; yine de her iki mimaride de saf-Java
# sunpkcs11-wrapper'a geciyoruz — tek kod yolu, ayni davranis, ayni testler.
echo ">> native IAIK katmani cikariliyor (eski .jnilib dahil)"
rm -rf "$WORK/classes/iaik"
rm -f  "$WORK"/classes/*.dll "$WORK"/classes/*.so "$WORK"/classes/*.jnilib

echo ">> saf-Java sunpkcs11-wrapper yerlestiriliyor"
( cd "$WORK/classes" && unzip -oq "$WRAPPER_JAR" 'iaik/*' )
mkdir -p "$WORK/classes/iaik/pkcs/pkcs11/wrapper"
cp "$WORK/ExceptionMessages.properties" "$WORK/classes/$EM"

echo ">> yardimci siniflar derleniyor"
"$JDK/bin/javac" -nowarn -encoding UTF-8 -d "$WORK/classes" \
  "$ROOT/patch/MacPkcs11Modules.java" "$ROOT/patch/MacPaths.java"

echo ">> bytecode yamalari uygulaniyor"
"$JDK/bin/javac" -nowarn -encoding UTF-8 -cp "$JAVASSIST_JAR" -d "$WORK/patcher" \
  "$ROOT/patch/Patch.java" "$ROOT/patch/ApiCheck.java"
"$JDK/bin/java" -cp "$JAVASSIST_JAR:$WORK/patcher" Patch "$WORK/classes"

# sunpkcs11-wrapper IAIK API'sinin birebir kopyasi degil. Uygulamanin cagirdigi
# her iaik.* uyesi gercekten var mi? Eksik bir uye derlemede GORULMEZ, ancak
# kullanici o ozelligi calistirinca (orn. imzalama) NoSuchFieldError/
# NoSuchMethodError olarak patlar. Bu yuzden paketlemeden once zorunlu denetim.
echo ">> API uyumlulugu denetleniyor"
"$JDK/bin/java" -cp "$JAVASSIST_JAR:$WORK/patcher" ApiCheck "$WORK/classes"

echo ">> yamali jar paketleniyor"
( cd "$WORK/classes" && zip -qr "$OUT_JAR" . )

# ApiCheck statik; <clinit> icinde patlayan bir shim'i goremez. Bu yuzden
# uyeleri yamali jar'a karsi gercekten calistirip dogruluyoruz.
echo ">> shim calisma zamaninda dogrulaniyor"
"$JDK/bin/javac" -nowarn -encoding UTF-8 -cp "$OUT_JAR" -d "$WORK/patcher" \
  "$ROOT/patch/ShimTest.java"
"$JDK/bin/java" --add-exports=jdk.crypto.cryptoki/sun.security.pkcs11.wrapper=ALL-UNNAMED \
  -cp "$OUT_JAR:$WORK/patcher" ShimTest

# Dogrulama: native kalinti kalmasin, yeni wrapper gercekten iceride olsun.
# NOT: `unzip -l | grep -q` KULLANMA — grep ilk eslesmede cikinca unzip SIGPIPE
# alir ve `set -o pipefail` yuzunden dogru sonucta bile betik olur. Once dosyaya al.
LISTING="$WORK/listing.txt"
unzip -l "$OUT_JAR" > "$LISTING"
if grep -qE '\.(jnilib|dll|so)$' "$LISTING"; then
  echo "HATA: yamali jar'da hala native kutuphane var" >&2; exit 1
fi
grep -q 'iaik/pkcs/pkcs11/objects/PKCS11Object.class' "$LISTING" \
  || { echo "HATA: sunpkcs11-wrapper siniflari jar'a girmemis" >&2; exit 1; }

rm -rf "$WORK"
echo "prep OK -> $OUT_JAR ($(du -h "$OUT_JAR" | cut -f1))"
