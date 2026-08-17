SHELL := /bin/bash
ROOT := $(shell pwd)
CACHE := $(ROOT)/.jre-cache
BUILD := $(ROOT)/build
APPNAME := TNBTeknolojiImza
DISPLAYNAME := TNB Teknoloji İmza

# Hedef mimari kabuğun mimarisidir: Apple Silicon'da arm64, Intel Mac'te x86_64.
# Bir istisna var: Apple Silicon donanımda kabuk Rosetta (x86_64) modundaysa
# arm64 runtime/paket üretilemez; kur.sh bunu kendisi düzeltir, doğrudan `make`
# çağıranları burada uyarıyoruz.
ARCH := $(shell uname -m)
ARM_HW := $(shell sysctl -n hw.optional.arm64 2>/dev/null)
GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),app)
ARCH_GOALS := $(filter jre prep app dmg run install,$(GOALS))

# TARGET_ARCH: paket/indirme adlarında kullanılan kısa ad (arm64 | x64)
# MACH_ARCH:   Mach-O / lipo / java_home -a adı (arm64 | x86_64)
# JAVA_ARCH:   JVM'in os.arch değeri (aarch64 | x86_64)
TARGET_ARCH := $(if $(filter arm64,$(ARCH)),arm64,$(if $(filter x86_64,$(ARCH)),x64,bilinmiyor))
MACH_ARCH   := $(if $(filter arm64,$(TARGET_ARCH)),arm64,x86_64)
JAVA_ARCH   := $(if $(filter arm64,$(TARGET_ARCH)),aarch64,x86_64)
ZULU_ARCH   := $(if $(filter arm64,$(TARGET_ARCH)),aarch64,x64)

ifneq ($(ARCH_GOALS),)
ifeq ($(TARGET_ARCH),bilinmiyor)
$(error Desteklenmeyen mimari: $(ARCH) (yalnızca arm64 ve x86_64))
endif
ifeq ($(ARCH)-$(ARM_HW),x86_64-1)
$(error Donanım Apple Silicon ama terminal Rosetta (x86_64) modunda. Şunu kullanın:  arch -arm64 make $(MAKECMDGOALS))
endif
endif

ZULU11_URL := https://cdn.azul.com/zulu/bin/zulu11.88.17-ca-jdk11.0.31-macosx_$(ZULU_ARCH).tar.gz
ZULU21_URL := https://cdn.azul.com/zulu/bin/zulu21.50.19-ca-jdk21.0.11-macosx_$(ZULU_ARCH).tar.gz

# Önbellek mimariye göre ayrılır; aynı depo hem arm64 hem x64 derleyebilsin.
RUNTIME := $(CACHE)/zulu11-runtime-$(TARGET_ARCH)
ZULU21 := $(CACHE)/zulu21-$(TARGET_ARCH)
# Sistem jpackage'i yalnızca hedefle AYNI mimarideyse kullanılabilir: uygulama
# launcher'ı jpackage'in kendi ikilisinden kopyalanır, mimarisi ondan gelir.
# (Yalnızca derleme hedeflerinde hesaplanır; `make clean/host/uninstall` bunun
#  için JVM başlatmasın.)
JPACKAGE := $(if $(ARCH_GOALS),$(shell $(ROOT)/scripts/find-jpackage.sh "$(JAVA_ARCH)" "$(ZULU21)"),jpackage)

.PHONY: jre
jre: $(RUNTIME)/bin/java jpackage-hazir

$(RUNTIME)/bin/java:
	@mkdir -p $(CACHE)
	@# Mimari eki olmayan eski önbellek (yalnızca arm64 üretilirdi) varsa taşı.
	@if [ "$(TARGET_ARCH)" = "arm64" ] && [ ! -x "$(RUNTIME)/bin/java" ] \
	    && [ -x "$(CACHE)/zulu11-runtime/bin/java" ]; then \
	   echo ">> mevcut arm64 runtime önbelleği taşınıyor"; \
	   mv "$(CACHE)/zulu11-runtime" "$(RUNTIME)"; \
	 fi
	@if [ ! -x "$(RUNTIME)/bin/java" ]; then \
	   echo ">> Zulu 11 $(MACH_ARCH) runtime indiriliyor..."; \
	   curl -fsSL "$(ZULU11_URL)" -o $(CACHE)/zulu11-$(TARGET_ARCH).tar.gz; \
	   rm -rf $(RUNTIME) $(CACHE)/_z11 && mkdir -p $(CACHE)/_z11; \
	   tar -xzf $(CACHE)/zulu11-$(TARGET_ARCH).tar.gz -C $(CACHE)/_z11 --strip-components=1; \
	   if [ -d "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" ]; then \
	     mv "$(CACHE)/_z11/zulu-11.jdk/Contents/Home" $(RUNTIME); \
	   elif [ -d "$(CACHE)/_z11/Contents/Home" ]; then \
	     mv "$(CACHE)/_z11/Contents/Home" $(RUNTIME); \
	   else mv $(CACHE)/_z11 $(RUNTIME); fi; \
	   rm -rf $(CACHE)/_z11 $(CACHE)/zulu11-$(TARGET_ARCH).tar.gz; \
	 fi
	@# İndirilen runtime gerçekten hedef mimaride mi (yanlış URL / bozuk önbellek)
	@if ! lipo -archs "$(RUNTIME)/bin/java" 2>/dev/null | tr ' ' '\n' | grep -qx "$(MACH_ARCH)"; then \
	   echo "HATA: runtime $(MACH_ARCH) değil: $$(lipo -archs $(RUNTIME)/bin/java 2>/dev/null)" >&2; \
	   echo "      Önbelleği silip tekrar deneyin: rm -rf $(RUNTIME)" >&2; exit 1; \
	 fi
	@echo ">> runtime: $(RUNTIME) [$(MACH_ARCH)]"

# JPACKAGE ya sistemdeki uygun mimarideki jpackage'i ya da $(ZULU21) altındaki
# indirilecek olanı gösterir; ikincisi ise şimdi indiriyoruz.
.PHONY: jpackage-hazir
jpackage-hazir:
	@if [ -x "$(JPACKAGE)" ]; then \
	   echo ">> jpackage: $(JPACKAGE)"; \
	 else \
	   echo ">> Zulu 21 $(MACH_ARCH) (jpackage) indiriliyor..."; \
	   mkdir -p $(CACHE); \
	   curl -fsSL "$(ZULU21_URL)" -o $(CACHE)/zulu21-$(TARGET_ARCH).tar.gz; \
	   rm -rf $(ZULU21) $(CACHE)/_z21 && mkdir -p $(CACHE)/_z21; \
	   tar -xzf $(CACHE)/zulu21-$(TARGET_ARCH).tar.gz -C $(CACHE)/_z21 --strip-components=1; \
	   if [ -d "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" ]; then \
	     mv "$(CACHE)/_z21/zulu-21.jdk/Contents/Home" $(ZULU21); \
	   elif [ -d "$(CACHE)/_z21/Contents/Home" ]; then \
	     mv "$(CACHE)/_z21/Contents/Home" $(ZULU21); \
	   else mv $(CACHE)/_z21 $(ZULU21); fi; \
	   rm -rf $(CACHE)/_z21 $(CACHE)/zulu21-$(TARGET_ARCH).tar.gz; \
	   echo ">> jpackage: $(JPACKAGE)"; \
	 fi

.PHONY: prep app
prep: $(RUNTIME)/bin/java
	@JDK="$(RUNTIME)" ./scripts/prep-payload.sh

app: jre prep
	@RUNTIME="$(RUNTIME)" JPACKAGE="$(JPACKAGE)" MACH_ARCH="$(MACH_ARCH)" ./scripts/build-app.sh

.PHONY: dmg run install host uninstall clean
dmg: app
	@rm -f $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot && mkdir -p $(BUILD)/dmgroot
	@cp -R $(BUILD)/$(APPNAME).app $(BUILD)/dmgroot/
	@ln -s /Applications $(BUILD)/dmgroot/Applications
	@hdiutil create -volname "$(APPNAME)" -srcfolder $(BUILD)/dmgroot \
	   -ov -format UDZO $(BUILD)/$(APPNAME).dmg
	@rm -rf $(BUILD)/dmgroot
	@echo ">> dmg: $(BUILD)/$(APPNAME).dmg"

# Kart okunuyor mu, sürücü yükleniyor mu — tarayıcısız hızlı deneme.
run: app
	@./scripts/smoke-test.sh "$(BUILD)/$(APPNAME).app"

# Not: eski sürüm daha önce "sudo" ile kurulmuşsa root'a aittir ve normal
# kullanıcı silemez; bu durumda yönetici izni isteyip devam ediyoruz.
install: app
	@if [ -e "/Applications/$(APPNAME).app" ] && ! rm -rf "/Applications/$(APPNAME).app" 2>/dev/null; then \
	   echo ">> eski sürüm yönetici izniyle kaldırılıyor (şifre isteyebilir)..."; \
	   sudo rm -rf "/Applications/$(APPNAME).app"; \
	 fi
	@if ! cp -R $(BUILD)/$(APPNAME).app /Applications/ 2>/dev/null; then \
	   echo ">> /Applications'a yönetici izniyle kopyalanıyor (şifre isteyebilir)..."; \
	   sudo cp -R $(BUILD)/$(APPNAME).app /Applications/; \
	   sudo chown -R "$$(id -un)":admin "/Applications/$(APPNAME).app"; \
	 fi
	@xattr -dr com.apple.quarantine "/Applications/$(APPNAME).app" 2>/dev/null || true
	@echo ">> kuruldu: /Applications/$(APPNAME).app"
	@$(MAKE) --no-print-directory host

# Tarayıcı kaydı (native messaging host manifest'leri)
host:
	@./scripts/install-host.sh

uninstall:
	@./scripts/install-host.sh --uninstall
	@if [ -e "/Applications/$(APPNAME).app" ] && ! rm -rf "/Applications/$(APPNAME).app" 2>/dev/null; then \
	   echo ">> yönetici izniyle kaldırılıyor (şifre isteyebilir)..."; \
	   sudo rm -rf "/Applications/$(APPNAME).app"; \
	 fi
	@echo ">> kaldırıldı."

clean:
	@rm -rf $(BUILD)
	@echo ">> temizlendi (build/). .jre-cache korunur."
