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

# --- sudo ile calistirildiysa normal kullaniciya geri don --------------------
# Root olarak yazilan manifest kullanicinin ev dizininde root'a ait kalir ve bir
# sonraki (sudo'suz) kurulum "Permission denied" ile patlar. Bunu en bastan
# engelliyoruz.
if [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  echo ">> Tarayıcı kaydı normal kullanıcı ($SUDO_USER) olarak yapılıyor."
  exec sudo -u "$SUDO_USER" -H "$SELF" "$@"
fi

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

ME="$(id -un)"

# Yonetici hakki: sifreyi en fazla bir kez sorar, sonrasi sudo onbelleginden.
# Not: "curl | bash" ile calistirildiginda stdin betigin kendisidir; sudo
# parolayi /dev/tty uzerinden okudugu icin bu durumda da calisir.
SUDO_STATE="?"
have_sudo() {
  case "$SUDO_STATE" in 1) return 0 ;; 0) return 1 ;; esac
  if ! command -v sudo >/dev/null 2>&1; then SUDO_STATE=0; return 1; fi
  if sudo -n true 2>/dev/null; then SUDO_STATE=1; return 0; fi
  if [ -e /dev/tty ] && sudo -v -p "   Mac kullanıcı şifreniz: " </dev/tty; then
    SUDO_STATE=1; return 0
  fi
  SUDO_STATE=0; return 1
}

# Daha once "sudo" ile kurulum yapildiysa bu klasorler root'a ait kalir.
# Once sifre gerektirmeyen onarimi deniyoruz (klasor bizimse izin biti yeter),
# olmazsa sahipligi kullaniciya geri veriyoruz. Profilin tamamina degil sadece
# gerekli iki dizine dokunuyoruz ki islem hizli olsun.
fix_perms() {
  local d="$1" nm="$1/NativeMessagingHosts"
  chflags nouchg "$d" 2>/dev/null || true
  chmod u+rwx "$d" 2>/dev/null || true
  if [ -e "$nm" ]; then
    chflags -R nouchg "$nm" 2>/dev/null || true
    chmod -R u+rwX "$nm" 2>/dev/null || true
  fi
  if [ -w "$d" ] && { [ ! -e "$nm" ] || [ -w "$nm" ]; }; then return 0; fi

  echo "   ! Bu klasör daha önce yönetici olarak oluşturulmuş, izinler onarılıyor..."
  if ! have_sudo; then return 1; fi
  sudo chflags nouchg "$d" 2>/dev/null || true
  sudo chown "$ME:staff" "$d" 2>/dev/null || true
  sudo chmod u+rwx "$d" 2>/dev/null || true
  if [ -e "$nm" ]; then
    sudo chflags -R nouchg "$nm" 2>/dev/null || true
    sudo chown -R "$ME:staff" "$nm" 2>/dev/null || true
    sudo chmod -R u+rwX "$nm" 2>/dev/null || true
  fi
  return 0
}

if [ "$UNINSTALL" = "1" ]; then
  n=0
  for d in "${BROWSER_DIRS[@]}"; do
    f="$d/NativeMessagingHosts/$HOST_NAME.json"
    [ -f "$f" ] || continue
    if rm -f "$f" 2>/dev/null; then
      echo "   silindi: $f"; n=$((n+1))
    elif fix_perms "$d" && rm -f "$f" 2>/dev/null; then
      echo "   silindi: $f"; n=$((n+1))
    else
      echo "   silinemedi (izin): $f" >&2
    fi
  done
  echo ">> $n kayıt kaldırıldı."
  exit 0
fi

[ -x "$EXEC" ] || { echo "HATA: uygulama bulunamadı: $EXEC" >&2; exit 1; }

# Kurulu uygulamanin gercek mimarisi (arm64 | x86_64) — yalnizca aciklama metni.
APP_ARCH="$(lipo -archs "$EXEC" 2>/dev/null | awk '{print $1}')"
[ -n "$APP_ARCH" ] || APP_ARCH="$(uname -m)"

manifest_json() {
  cat <<EOF
{
  "name": "$HOST_NAME",
  "description": "TnbTeknoloji Imza Chrome Native Messaging Host (macOS $APP_ARCH)",
  "path": "$EXEC",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF
}

try_write() {
  local nm="$1/NativeMessagingHosts" f
  mkdir -p "$nm" 2>/dev/null || return 1
  f="$nm/$HOST_NAME.json"
  # Eski dosya root'a aitse uzerine yazilamaz; klasor bizimse silmek yeterli.
  if [ -e "$f" ] && [ ! -w "$f" ]; then rm -f "$f" 2>/dev/null || true; fi
  # Yonlendirme hatasini da yutmak icin alt kabuk (yoksa bash ham "Permission
  # denied" satirini ekrana basar).
  ( manifest_json > "$f" ) 2>/dev/null || return 1
  return 0
}

installed=0
skipped=()
failed=()
for d in "${BROWSER_DIRS[@]}"; do
  # Yalnizca gercekten kurulu tarayicilar icin yaz (bos klasor birakmayalim).
  if [ ! -d "$d" ]; then skipped+=("$(basename "$d")"); continue; fi
  # Yazamiyorsak sebebi neredeyse her zaman eski bir "sudo" kurulumudur:
  # izinleri onarip bir kez daha deniyoruz. Bir tarayici basarisiz olsa bile
  # digerlerine devam ediyoruz.
  if try_write "$d" || { fix_perms "$d" && try_write "$d"; }; then
    echo "   kayıt: $d/NativeMessagingHosts/$HOST_NAME.json"
    installed=$((installed+1))
  else
    failed+=("$d")
  fi
done

if [ "$installed" = "0" ]; then
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "!! Tarayıcı kaydı yazılamadı (izin sorunu, otomatik onarım da başarısız):" >&2
    for f in "${failed[@]}"; do echo "!!   $f/NativeMessagingHosts" >&2; done
    echo "!! Terminal'e şunu yapıştırıp kur.sh'i tekrar çalıştırın:" >&2
    for f in "${failed[@]}"; do echo "!!   sudo chown -R \"\$(id -un)\" \"$f\"" >&2; done
  else
    echo "!! Chromium tabanlı hiçbir tarayıcı profili bulunamadı." >&2
    echo "!! Chrome'u bir kez açıp kapatın, sonra bu betiği tekrar çalıştırın." >&2
  fi
  exit 1
fi

echo ">> $installed tarayıcıya kaydedildi (host: $HOST_NAME)."
if [ "${#failed[@]}" -gt 0 ]; then
  echo "   (yazılamayanlar: ${failed[*]})" >&2
fi
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "   (kurulu olmayanlar atlandı: ${skipped[*]})"
fi
echo ">> Kayıt sonrası tarayıcıyı TAMAMEN kapatıp yeniden açın."
