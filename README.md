# TNB Teknoloji Elektronik İmza — macOS (Apple Silicon) Portu

TNB KEP (`kep.hs02.kep.tr`) girişinde kullanılan **TNB Teknoloji Elektronik İmza**
uygulamasının Apple Silicon Mac'ler için **resmi olmayan, topluluk** portu.
Üretici yalnızca Windows kurulumu (`TNBTeknolojiImza.exe`) dağıtıyor; bu depo
aynı Java uygulamasını gömülü **arm64 Java 11** runtime ile native bir `.app`
olarak paketler ve Chrome'a *native messaging host* olarak kaydeder.
Rosetta veya ayrı Java kurulumu gerekmez.

## Kurulum (tek komut)

```bash
curl -fsSL https://raw.githubusercontent.com/saidsurucu/tnb-eimza-mac-arm64/main/kur.sh | bash
```

Betik sırayla: Xcode Command Line Tools'u (gerekirse) kurar, depoyu
`~/tnb-eimza-mac-arm64` altına klonlar, arm64 Java 11 runtime'ını indirir,
`TNBTeknolojiImza.app`'i derleyip imzalar, `/Applications`'a kurar ve kurulu tüm
Chromium tabanlı tarayıcılara kaydeder. İnternet gerekir.

Ardından:

1. Chrome eklentisini kurun (kurulu değilse):
   [TNB Teknoloji Elektronik İmza](https://chromewebstore.google.com/detail/ppgjmopocehhllbjblnpdajkkkfghpan)
2. **Chrome'u tamamen kapatıp yeniden açın** — kayıt ancak açılışta okunur.
3. https://kep.hs02.kep.tr adresinden e-imza ile giriş yapın.

## Bu uygulama çift tıklanarak açılmaz

Diğer e-imza portlarından farklı olarak bu bir **native messaging host**'tur:
tarayıcı, eklenti imzalama isteyince uygulamayı kendisi başlatır ve stdin/stdout
üzerinden JSON konuşur. `/Applications` içindeki uygulamaya çift tıklamak
beklenen bir şey yapmaz; akışı **tarayıcıdan** başlatın.

## Zorunlu: arm64 kart sürücüsü (PKCS#11)

Uygulama kartı `libakisp11.dylib` gibi bir PKCS#11 sürücüsü üzerinden okur ve
**arm64** kod olarak çalışır; Intel-only bir sürücü arm64 sürece yüklenemez.
AKİS kartları için TÜBİTAK BİLGEM'den **"Mac OS Arm (Apple Silicon)"** paketini
kurun:

- https://akiskart.bilgem.tubitak.gov.tr/tr/destek/

Doğrulama (`arm64` içermeli):

```bash
lipo -archs /usr/local/lib/libakisp11.dylib
```

Denenen sürücüler ve sıraları için bkz. `patch/MacPkcs11Modules.java`.
Listeyi geçici olarak değiştirmek için `-Dtnb.pkcs11.modules=/yol/surucu.dylib`.

## Teknik özet

Windows sürümü aslında saf bir Java uygulaması (`TNBTeknolojiImza.jar`) — `.exe`
yalnızca NSIS kurucusu. macOS'ta iki şey bozuk:

1. **Native kütüphanede arm64 dilimi yok.** Jar, kart erişimini IAIK PKCS#11
   Wrapper'ın native parçası üzerinden yapar; içindeki `libpkcs11wrapper.jnilib`
   yalnızca `ppc64 / ppc7400 / i386 / x86_64` içerir. arm64 JVM'de
   `UnsatisfiedLinkError` ile düşer.
   → **Çözüm:** IAIK'in native katmanı yerine aynı `iaik.pkcs.pkcs11` API'sini
   **SunPKCS11** (`jdk.crypto.cryptoki`) üzerine oturtan
   [`org.xipki.iaik:sunpkcs11-wrapper`](https://github.com/xipki/pkcs11wrapper/tree/sunpkcs11)
   kullanılıyor — saf Java, arm64 native, Rosetta yok.

2. **macOS modül listesinde AKİS yok.** Orijinal kod macOS'ta yalnızca
   `libeTPkcs11.dylib` ve `libaetpkss.dylib` deniyor; Türkiye'de yaygın olan AKİS
   sürücüsü listede değil — kart takılı olsa bile sertifika listesi boş gelir.
   → **Çözüm:** AKİS dahil genişletilmiş, dosya varlığına göre çözülen liste.

Ek olarak (`patch/Patch.java`):

- `objects.Object` → `objects.PKCS11Object` (yeni wrapper'daki tek ad değişikliği)
- Chrome host'u `argv[1]`'de eklenti kaynağını geçirir; orijinal kod orada
  `"Chrome"` bekler → argüman zorlanıyor
- Loglar ev dizininin köküne değil `~/Library/Logs/TNBTeknolojiImza/` altına

Paketleme: `jpackage` + Zulu 11 arm64 (`--runtime-image`), ASCII executable adı,
ad-hoc `codesign`.

Gerçek AKİS kartıyla sertifika okuma uçtan uca doğrulanmıştır: uygulamaya
Chrome'un çerçeve biçiminde (4 bayt little-endian uzunluk + JSON)
`selectCertificate` isteği verildiğinde `status: 200` ve karttaki nitelikli
elektronik imza sertifikası doğru çerçevelenmiş olarak stdout'a dönüyor.
Aynı denemeyi `make run` ile siz de yapabilirsiniz.

## Elle derleme

```bash
git clone https://github.com/saidsurucu/tnb-eimza-mac-arm64.git
cd tnb-eimza-mac-arm64
make app        # build/TNBTeknolojiImza.app üret
make install    # /Applications'a kur + tarayıcılara kaydet
make host       # yalnızca tarayıcı kaydını yenile
make run        # tarayıcısız duman testi (kart + sürücü kontrolü)
make dmg        # sürükle-bırak disk imajı
make uninstall  # kaydı ve uygulamayı kaldır
```

## Sorun giderme

- **Eklenti "uygulama kurulu değil" diyor:** `make host` çalıştırıp Chrome'u
  tamamen kapatıp açın. Kayıt dosyası:
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/tnbtimzahost.json`
- **Sertifika listesi boş:** Sürücü arm64 mi? `lipo -archs /usr/local/lib/libakisp11.dylib`.
  Sonra `make run` ile hangi modüllerin denendiğine bakın.
- **Kart okunmuyor:** Kart takılı ve okuyucu bağlı mı? `pkcs11-tool --module /usr/local/lib/libakisp11.dylib -L`
- **Gatekeeper "açılamıyor":** Uygulamaya sağ tık → **Aç** (ad-hoc imzalı).
- **Loglar:** `~/Library/Logs/TNBTeknolojiImza/TnbTeknolojiImza.log` ve `.err.log`

## Bilinen sınırlar

- Yalnızca **arm64** (Apple Silicon); Intel Mac desteklenmez.
- **Notarize edilmemiştir** (ad-hoc imza).
- **İmzalama (PIN girişi) ve tarayıcı üzerinden uçtan uca giriş akışı
  doğrulanmamıştır**; doğrulanan adım sertifika okuma/seçmedir.
- Kart tipi: **AKİS**. Diğer token'lar (SafeNet, SafeSign, IDPrime) listeye
  eklendi ama test edilmedi.
- CSP (Windows'a özgü) yolu desteklenmez; yalnızca PKCS#11.
- `app/TNBTeknolojiImza.jar` üreticinin dağıttığı kurucudan çıkarılmıştır;
  bu depo onu **değiştirmeden** saklar, yamalar derleme sırasında `build/`
  altında uygulanır.

## Sorumluluk reddi

Bu depo **resmi değildir**; Türkiye Noterler Birliği, TNB Teknoloji veya TÜBİTAK
tarafından geliştirilmemiş ya da onaylanmamıştır. Yalnızca paketleme ve derleme
betikleri sağlar. TNB / TNB Teknoloji / TÜBİTAK marka ve yazılım hakları
sahiplerine aittir. `sunpkcs11-wrapper` ve IAIK PKCS#11 Wrapper API'si kendi
lisansları altındadır.
