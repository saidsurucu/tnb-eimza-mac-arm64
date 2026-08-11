#!/usr/bin/env bash
# TNB Teknoloji Elektronik İmza — macOS (Apple Silicon) tek-komut kurulum.
# Resmi değildir; topluluk portudur.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
info(){ echo "${GRN}>>${RST} $*"; }
warn(){ echo "${YEL}!!${RST} $*"; }
die(){ echo "${RED}HATA:${RST} $*" >&2; exit 1; }

# 1) Mimari kontrolü
[ "$(uname -s)" = "Darwin" ] || die "Yalnızca macOS."
[ "$(uname -m)" = "arm64" ] || die "Yalnızca Apple Silicon (arm64)."

info "Bu kurucu resmi değildir; TNB Teknoloji İmza'nın topluluk portudur."

# 2) Xcode CLT (make, git, curl için)
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode Command Line Tools kuruluyor — pencereyi onaylayın..."
  xcode-select --install || true
  die "CLT kurulumu bitince kur.sh'i tekrar çalıştırın."
fi

# 3) Repo kökünü bul; `curl | bash` ile çalıştırıldıysa repoyu klonla/güncelle
REPO_URL="https://github.com/saidsurucu/tnb-eimza-mac-arm64.git"
CLONE_DIR="$HOME/tnb-eimza-mac-arm64"
if [ -f "./Makefile" ] && [ -d "./app" ]; then
  REPO_ROOT="$(pwd)"
elif [ -n "${BASH_SOURCE:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/Makefile" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  if [ -d "$CLONE_DIR/.git" ]; then
    info "Mevcut kopya güncelleniyor: $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only || warn "güncelleme atlandı (yerel değişiklik olabilir)"
  else
    info "Depo klonlanıyor: $CLONE_DIR"
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  REPO_ROOT="$CLONE_DIR"
fi
cd "$REPO_ROOT"
[ -f Makefile ] && [ -d app ] || die "Repo kökü bulunamadı: $REPO_ROOT"

# 4) Build + kur + tarayıcı kaydı
if [ ! -f assets/TNBTeknolojiImza.icns ]; then
  info "İkon üretiliyor..."; ./scripts/make-icns.sh >/dev/null || warn "ikon üretilemedi (kozmetik)"
fi
info "Runtime ve build aracı hazırlanıyor..."; make jre
info "Uygulama derleniyor..."; make app
info "/Applications'a kuruluyor ve tarayıcıya kaydediliyor..."; make install

# 5) PKCS#11 sürücüsü arm64 mi?
# Uygulama sürücüyü KENDİ arm64 sürecine yükler; Intel-only bir dylib yüklenemez
# ("incompatible architecture") ve sertifika listesi boş kalır.
found_arm64=0; found_any=0
for drv in /usr/local/lib/libakisp11.dylib \
           /usr/local/lib/libeTPkcs11.dylib \
           /usr/local/lib/libaetpkss.dylib; do
  [ -f "$drv" ] || continue
  found_any=1
  archs="$(lipo -archs "$drv" 2>/dev/null || echo '?')"
  if echo "$archs" | grep -qw arm64; then
    info "sürücü hazır (arm64): $drv  [$archs]"; found_arm64=1
  else
    warn "sürücü arm64 DEĞİL: $drv  [$archs]"
  fi
done

if [ "$found_any" = "0" ]; then
  warn "Hiçbir PKCS#11 kart sürücüsü bulunamadı."
  warn "AKİS kartı için TÜBİTAK BİLGEM'den 'Mac OS Arm (Apple Silicon)' paketini kurun:"
  warn "  https://akiskart.bilgem.tubitak.gov.tr/tr/destek/"
elif [ "$found_arm64" = "0" ]; then
  warn "Kurulu sürücülerin hiçbirinde arm64 dilimi yok — kart okunamaz."
  warn "Sürücünün Apple Silicon sürümünü kurup kur.sh'i tekrar çalıştırın."
fi

echo
info "Bitti."
info "1) Chrome eklentisini kurun (kurulu değilse):"
info "   https://chromewebstore.google.com/detail/ppgjmopocehhllbjblnpdajkkkfghpan"
info "2) Chrome'u TAMAMEN kapatıp yeniden açın (kayıt böyle okunur)."
info "3) https://kep.hs02.kep.tr adresinden e-imza ile giriş yapın."
info "Loglar: ~/Library/Logs/TNBTeknolojiImza/"
