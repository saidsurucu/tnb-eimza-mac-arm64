#!/usr/bin/env bash
# TNB Teknoloji Elektronik İmza — macOS tek-komut kurulum.
# Apple Silicon (arm64) ve Intel (x86_64) Mac'ler; hedef macOS 13+.
# Resmi değildir; topluluk portudur.
set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
info(){ echo "${GRN}>>${RST} $*"; }
warn(){ echo "${YEL}!!${RST} $*"; }
die(){ echo "${RED}HATA:${RST} $*" >&2; exit 1; }

# 0) "sudo ./kur.sh" ile başlatıldıysa normal kullanıcıya dön.
# Root olarak yazılan dosyalar (depo, .jre-cache, tarayıcı kaydı) kullanıcının
# ev dizininde root'a ait kalır ve sonraki kurulum "Permission denied" ile
# patlar. Gerekli yerlerde yönetici iznini zaten adım adım istiyoruz.
if [ "$(id -u)" = "0" ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    warn "Kurulum 'sudo' ile başlatıldı; normal kullanıcı ($SUDO_USER) olarak devam ediliyor."
    exec sudo -u "$SUDO_USER" -H "$SELF" "$@"
  fi
  die "Bu kurulumu 'sudo' ile çalıştırmayın. Normal kullanıcı olarak: ./kur.sh"
fi

# 1) Mimari ve macOS sürümü kontrolü
[ "$(uname -s)" = "Darwin" ] || die "Yalnızca macOS."

# Apple Silicon donanımda Terminal x86_64 (Rosetta) modunda açılmış olabilir —
# Bilgi penceresinde "Rosetta kullanarak aç" işaretliyse veya kabuk Intel
# Homebrew'dan geliyorsa `uname -m` x86_64 döner. Bu modda arm64 runtime ve
# arm64 kart sürücüsü yüklenemez; donanım gerçekten arm64 ise kendimizi arm64
# olarak yeniden başlatıyoruz (depo hazırlandıktan sonra, 3c adımında).
# Gerçek Intel Mac'te ise x86_64 doğru hedeftir, dokunmuyoruz.
ARCH_SWITCH=0
IS_ARM_HW="$(sysctl -n hw.optional.arm64 2>/dev/null || true)"
case "$(uname -m)" in
  arm64)
    BUILD_ARCH="arm64"
    ;;
  x86_64)
    if [ "$IS_ARM_HW" = "1" ]; then
      if [ "${TNB_ARCH_SWITCHED:-0}" != "1" ] && command -v arch >/dev/null 2>&1; then
        warn "Terminal Rosetta (x86_64) modunda çalışıyor; otomatik olarak arm64'e geçilecek."
        ARCH_SWITCH=1
        BUILD_ARCH="arm64"
      else
        die "Donanım Apple Silicon ama kabuk Rosetta modunda. Şunu deneyin: arch -arm64 ./kur.sh"
      fi
    else
      BUILD_ARCH="x86_64"
    fi
    ;;
  *)
    die "Desteklenmeyen mimari: $(uname -m) (yalnızca arm64 ve x86_64)"
    ;;
esac

# macOS 13 (Ventura) ve üstü hedefleniyor. Daha eskisinde jpackage'ın indirdiği
# Zulu 21 çalışmayabilir; engellemiyoruz ama uyarıyoruz.
OSVER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
OSMAJ="${OSVER%%.*}"
if [ "${OSMAJ:-0}" -lt 13 ] 2>/dev/null; then
  warn "macOS $OSVER algılandı; bu port macOS 13 (Ventura) ve üstü için hazırlandı."
  warn "Kurulum denenecek ancak derleme araçları eski sürümlerde çalışmayabilir."
fi

# (arm64'e geçilecekse banner'ı ikinci geçişte gösteriyoruz)
if [ "$ARCH_SWITCH" != "1" ]; then
  info "Bu kurucu resmi değildir; TNB Teknoloji İmza'nın topluluk portudur."
  info "Hedef: macOS $OSVER / $BUILD_ARCH"
fi

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

# 3b) Daha önce sudo ile çalıştırıldıysa depo/önbellek root'a aittir; onar.
if [ ! -w "$REPO_ROOT" ] || { [ -e "$REPO_ROOT/.jre-cache" ] && [ ! -w "$REPO_ROOT/.jre-cache" ]; } \
   || { [ -e "$REPO_ROOT/build" ] && [ ! -w "$REPO_ROOT/build" ]; }; then
  warn "Depo klasörü daha önce yönetici olarak oluşturulmuş; izinler onarılıyor (şifre isteyebilir)..."
  sudo chown -R "$(id -un)":staff "$REPO_ROOT" || die "İzinler onarılamadı: $REPO_ROOT"
fi

# 3c) Rosetta altındaysak depo artık diskte; kendimizi arm64 olarak başlatıyoruz.
# (Erken yapamıyoruz: "curl | bash" ile çalıştırıldığında yeniden başlatılacak
#  bir dosya henüz yok.)
if [ "$ARCH_SWITCH" = "1" ]; then
  info "arm64 mimarisine geçiliyor..."
  export TNB_ARCH_SWITCHED=1
  exec arch -arm64 /bin/bash "$REPO_ROOT/kur.sh" "$@"
fi

# 4) Build + kur + tarayıcı kaydı
if [ ! -f assets/TNBTeknolojiImza.icns ]; then
  info "İkon üretiliyor..."; ./scripts/make-icns.sh >/dev/null || warn "ikon üretilemedi (kozmetik)"
fi
info "Runtime ve build aracı hazırlanıyor..."; make jre
info "Uygulama derleniyor..."; make app
info "/Applications'a kuruluyor ve tarayıcıya kaydediliyor..."; make install

# 5) PKCS#11 sürücüsü uygulamayla aynı mimaride mi?
# Uygulama sürücüyü KENDİ sürecine yükler: arm64 uygulamaya Intel-only bir
# dylib, Intel uygulamaya arm64-only bir dylib yüklenemez ("incompatible
# architecture") ve sertifika listesi boş kalır.
if [ "$BUILD_ARCH" = "arm64" ]; then
  DRIVER_PKG="Mac OS Arm (Apple Silicon)"
else
  DRIVER_PKG="Mac OS (Intel)"
fi

found_match=0; found_any=0
for drv in /usr/local/lib/libakisp11.dylib \
           /usr/local/lib/libeTPkcs11.dylib \
           /usr/local/lib/libaetpkss.dylib; do
  [ -f "$drv" ] || continue
  found_any=1
  archs="$(lipo -archs "$drv" 2>/dev/null || echo '?')"
  if echo "$archs" | tr ' ' '\n' | grep -qx "$BUILD_ARCH"; then
    info "sürücü hazır ($BUILD_ARCH): $drv  [$archs]"; found_match=1
  else
    warn "sürücüde $BUILD_ARCH dilimi YOK: $drv  [$archs]"
  fi
done

if [ "$found_any" = "0" ]; then
  warn "Hiçbir PKCS#11 kart sürücüsü bulunamadı."
  warn "AKİS kartı için TÜBİTAK BİLGEM'den '$DRIVER_PKG' paketini kurun:"
  warn "  https://akiskart.bilgem.tubitak.gov.tr/tr/destek/"
elif [ "$found_match" = "0" ]; then
  warn "Kurulu sürücülerin hiçbirinde $BUILD_ARCH dilimi yok — kart okunamaz."
  warn "Sürücünün '$DRIVER_PKG' sürümünü kurup kur.sh'i tekrar çalıştırın."
fi

echo
info "Bitti."
info "1) Chrome eklentisini kurun (kurulu değilse):"
info "   https://chromewebstore.google.com/detail/ppgjmopocehhllbjblnpdajkkkfghpan"
info "2) Chrome'u TAMAMEN kapatıp yeniden açın (kayıt böyle okunur)."
info "3) https://kep.hs02.kep.tr adresinden e-imza ile giriş yapın."
info "Loglar: ~/Library/Logs/TNBTeknolojiImza/"
