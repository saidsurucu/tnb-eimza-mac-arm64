# TNB Teknoloji Elektronik İmza — macOS Portu (Apple Silicon + Intel)

TNB KEP (`kep.hs02.kep.tr`) girişinde kullanılan **TNB Teknoloji Elektronik İmza**
uygulamasının Mac'ler için **resmi olmayan, topluluk** portu.
Üretici yalnızca Windows kurulumu (`TNBTeknolojiImza.exe`) dağıtıyor; bu depo
aynı Java uygulamasını gömülü **Java 11** runtime ile native bir `.app` olarak
paketler ve Chrome'a *native messaging host* olarak kaydeder. Rosetta veya ayrı
Java kurulumu gerekmez.

Desteklenen makineler:

| Mac | Uygulama mimarisi | macOS |
|---|---|---|
| Apple Silicon (M1/M2/M3/M4) | `arm64` | 11+ (13+ önerilir) |
| Intel | `x86_64` | **13 (Ventura)** ve üstü |

Paket, **derlendiği makinenin mimarisinde** üretilir: Intel bir Mac'te
çalıştırılan kurulum Intel (`x86_64`) bir `.app`, Apple Silicon'da arm64 bir
`.app` üretir. Rosetta gerekmez; her iki mimaride de uygulama native çalışır.

Apple Silicon bir Mac'te, gerçek AKİS kartı ve PIN ile **`kep.hs02.kep.tr`
girişi uçtan uca çalıştığı doğrulanmıştır.** Intel yolu aynı kod yolunu
kullanır (yamalar saf Java'dır, mimariden bağımsızdır) ancak gerçek Intel
donanımda uçtan uca **test edilmemiştir** — bkz. "Bilinen sınırlar".

## Kurulum (tek komut)

```bash
curl -fsSL https://raw.githubusercontent.com/saidsurucu/tnb-eimza-mac-arm64/main/kur.sh | bash
```

Betik sırayla: Xcode Command Line Tools'u (gerekirse) kurar, depoyu
`~/tnb-eimza-mac-arm64` altına klonlar, makinenin mimarisine uygun Java 11
runtime'ını indirir, `TNBTeknolojiImza.app`'i derleyip imzalar, `/Applications`'a
kurar ve kurulu tüm Chromium tabanlı tarayıcılara kaydeder. İnternet gerekir.

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

## Zorunlu: uygulamayla aynı mimaride kart sürücüsü (PKCS#11)

Uygulama kartı `libakisp11.dylib` gibi bir PKCS#11 sürücüsü üzerinden okur ve
sürücüyü **kendi sürecine** yükler. macOS farklı mimarideki bir kütüphaneyi
sürece yükleyemez ("incompatible architecture"): arm64 uygulamaya Intel-only,
Intel uygulamaya arm64-only bir sürücü yüklenmez ve sertifika listesi boş kalır.
Bu yüzden sürücünün mimarisi Mac'inize uymalıdır.

AKİS kartları için TÜBİTAK BİLGEM'den doğru paketi kurun:

| Mac | TÜBİTAK paketi |
|---|---|
| Apple Silicon | **"Mac OS Arm (Apple Silicon)"** |
| Intel | **"Mac OS"** (Intel sürümü) |

- https://akiskart.bilgem.tubitak.gov.tr/tr/destek/

Doğrulama — çıktı Mac'inizin mimarisini (`arm64` ya da `x86_64`) içermeli:

```bash
uname -m                                       # Mac'inizin mimarisi
lipo -archs /usr/local/lib/libakisp11.dylib    # sürücünün mimarisi
```

`kur.sh` bu denetimi kurulum sonunda kendisi de yapar ve uyumsuzluğu bildirir.

Bilinen sürücü adları bilinen dizinlerde taranır ve **yalnızca diskte gerçekten
var olan** yollar denenir; liste ve arama dizinleri için bkz.
`patch/MacPkcs11Modules.java`. Listeyi geçici olarak değiştirmek için
`-Dtnb.pkcs11.modules=/yol/surucu.dylib`.

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
   kullanılıyor — saf Java, her iki mimaride native, Rosetta yok.
   Not: bu `.jnilib`'in `x86_64` dilimi var, yani Intel Mac'te teorik olarak
   yüklenebilirdi; yine de **her iki mimaride de** saf-Java wrapper'a geçiyoruz
   — tek kod yolu, aynı davranış, aynı denetimler (ayrıca eski `.jnilib` 32-bit
   dönemden kalma ve JDK 11'de test edilmemiş).

2. **macOS modül listesinde AKİS yok.** Orijinal kod macOS'ta yalnızca
   `libeTPkcs11.dylib` ve `libaetpkss.dylib` deniyor; Türkiye'de yaygın olan AKİS
   sürücüsü listede değil — kart takılı olsa bile sertifika listesi boş gelir.
   → **Çözüm:** AKİS dahil genişletilmiş, dosya varlığına göre çözülen liste.

`sunpkcs11-wrapper` IAIK API'sinin birebir kopyası değil; uygulamanın çağırdığı
bazı üyeler orada yok. Bunlar `patch/Patch.java` içindeki **shim** ile geri
ekleniyor — en kritiği `Mechanism.RSA_PKCS`: sertifika listeleme `Mechanism`'e
hiç dokunmadığı için sorunsuz çalışıyor, ama **imzalama** tam olarak orada
`NoSuchFieldError` ile duruyordu. Eklenenler:

| Üye | Neden gerekli |
|---|---|
| `Mechanism.RSA_PKCS` (ve `RSA_X_509`, `RSA_9796`, `RSA_PKCS_OAEP`, `RSA_PKCS_KEY_PAIR_GEN`) | imzalama mekanizması |
| `Session.decrypt(byte[])` / `encrypt(byte[])` | şifreli KEP içeriği |
| `Functions.toFullHexString(int)` | PKCS#11 hata kodu → okunabilir mesaj (örn. `CKR_PIN_INCORRECT`) |
| `Module.getInstance(String,String)` | ölü dal; yalnızca doğrulayıcı için |

Bir de davranış farkı var: **`Module.finalize()` işlevsizleştirildi.** Uygulama
her istekte önce `deinitShell()` (modül başına `C_Finalize`) sonra `initShell()`
çağırıyor. SunPKCS11 ise modülü *yol başına önbelleklediği* ve `C_Initialize`'ı
yalnızca örneği ilk kez oluştururken çağırdığı için, `C_Finalize` sonrası
yeniden başlatma sessizce atlanıyor ve ikinci turdan itibaren her çağrı
`CKR_CRYPTOKI_NOT_INITIALIZED` veriyordu. Tek turluk `selectCertificate`
çalışıp çok turlu `sign` patladığı için fark edilmesi zordu. Host süreci tek
istek işleyip çıktığından `C_Finalize`'ı hiç çağırmamak zararsız; oturumlar
(logout + closeSession) kapatılmaya devam ediyor.

Bu tür bir eksik **derleme sırasında görünmez**, ancak kullanıcı o özelliği
çalıştırınca patlar. Bu yüzden derleme hattında iki zorunlu denetim var:

- `patch/ApiCheck.java` — uygulamanın çağırdığı **her** `iaik.*` üyesini sabit
  havuzundan çıkarıp yeni wrapper'da var mı diye bakar (125 referans).
- `patch/ShimTest.java` — shim'i yamalı jar'a karşı gerçekten çalıştırır
  (statik denetim `<clinit>` hatasını yakalayamaz) ve `deinit → init`
  döngüsünü 3 tur koşturarak yukarıdaki `C_Finalize` regresyonunu yakalar.

Diğer yamalar:

- `objects.Object` → `objects.PKCS11Object` (yeni wrapper'daki ad değişikliği)
- Chrome host'u `argv[1]`'de eklenti kaynağını geçirir; orijinal kod orada
  `"Chrome"` bekler → argüman zorlanıyor
- Loglar ev dizininin köküne değil `~/Library/Logs/TNBTeknolojiImza/` altına

Paketleme: `jpackage` + Zulu 11 (`--runtime-image`), ASCII executable adı,
ad-hoc `codesign`. Runtime, kabuğun mimarisine göre `aarch64` veya `x64` olarak
indirilir ve `.jre-cache/zulu11-runtime-<mimari>` altında ayrı ayrı önbelleklenir.

Mimari seçimi derleme hattında üç yerde denetlenir — sessiz bir uyumsuzluk
kullanıcıya "sertifika listesi boş" olarak yansıyacağı için:

- `Makefile` — indirilen runtime gerçekten hedef mimaride mi (`lipo -archs`).
- `scripts/find-jpackage.sh` — sistemde bulunan `jpackage` yalnızca hedefle
  **aynı mimarideyse** kullanılır. `.app`'in launcher ikilisi (`jpackageapplauncher`)
  jpackage'in kendi JDK'sinden kopyalanır; Intel bir jpackage arm64 paket (veya
  tersi) üretemez. Uygun değilse doğru mimaride Zulu 21 indirilir.
- `scripts/build-app.sh` — üretilen `.app`'in launcher'ı beklenen mimaride mi,
  `Info.plist`'e `LSMinimumSystemVersion` (Intel: `13.0`, arm64: `11.0`) yazılır.

**Durum: çalışıyor.** Gerçek AKİS kartı ve PIN ile, Chrome üzerinden
`kep.hs02.kep.tr` girişi Apple Silicon bir Mac'te uçtan uca doğrulandı —
sertifika seçimi, PIN girişi ve imzalama dahil. Intel yolu aynı yamaları ve
aynı denetimleri kullanır; farkı yalnızca indirilen runtime/jpackage
mimarisidir.

Kart takılıyken `make run` ile tarayıcısız hızlı bir kontrol de
yapabilirsiniz: uygulamaya Chrome'un çerçeve biçiminde (4 bayt little-endian
uzunluk + JSON) `selectCertificate` isteği verilir; `status: 200` ve karttaki
nitelikli sertifika doğru çerçevelenmiş olarak dönmelidir.

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
- **Sertifika listesi boş:** Sürücü ile uygulama aynı mimaride mi?
  `uname -m` ile `lipo -archs /usr/local/lib/libakisp11.dylib` çıktısı
  uyuşmalı. Sonra `make run` ile hangi modüllerin denendiğine bakın; farklı
  mimari varsa duman testi "incompatible architecture" diyerek sürücülerin
  mimarilerini listeler.
- **Kart okunmuyor:** Kart takılı ve okuyucu bağlı mı? `pkcs11-tool --module /usr/local/lib/libakisp11.dylib -L`
- **Gatekeeper "açılamıyor":** Uygulamaya sağ tık → **Aç** (ad-hoc imzalı).
- **Intel Mac'te "macOS 13 için hazırlandı" uyarısı:** macOS 12 ve altında
  kurulum yine denenir, ancak derleme için indirilen Zulu 21 (jpackage) eski
  macOS sürümlerinde çalışmayabilir. Desteklenen hedef macOS 13+.
- **"Donanım Apple Silicon ama kabuk Rosetta modunda" diyor:** Terminal x86_64
  modunda açılmıştır (`uname -m` → `x86_64`). `kur.sh` bunu kendisi algılayıp
  arm64'e geçer; doğrudan `make` çalıştırıyorsanız başına `arch -arm64` ekleyin.
  Kalıcı çözüm: Finder → Uygulamalar → Yardımcı Programlar → Terminal →
  **Bilgi Al** → "Rosetta kullanarak aç" işaretini kaldırın. (Gerçek Intel
  Mac'lerde bu uyarı çıkmaz; orada x86_64 zaten doğru hedeftir.)
- **`Permission denied` / `make[1]: *** [host] Error 1`:** Kurulum daha önce
  `sudo` ile çalıştırılmış olabilir; tarayıcı kaydı klasörü root'a ait kalır.
  `kur.sh` bunu artık kendisi onarır (gerekirse bir kez şifre sorar). Kurulumu
  **`sudo` ile başlatmayın**; `./kur.sh` yeterlidir.
- **"Veri imzalanırken bir hata oluştu. … java konsoluna bakınız":** Uygulamanın
  kastettiği "java konsolu" bu portta şu iki dosyadır:
  ```bash
  tail -100 ~/Library/Logs/TNBTeknolojiImza/TnbTeknolojiImza.err.log
  tail -100 ~/Library/Logs/TNBTeknolojiImza/TnbTeknolojiImza.log
  ```

## Bilinen sınırlar

- **Intel (`x86_64`) yolu gerçek donanımda test edilmedi.** Yamalar saf Java
  olduğu için mimariden bağımsızdır ve derleme hattı mimariyi üç ayrı yerde
  denetler; yine de uçtan uca doğrulama yalnızca Apple Silicon'da yapıldı.
  Intel'de hedeflenen ve önerilen sürüm **macOS 13 (Ventura)**.
- Üretilen `.app` **evrensel (universal) değildir**; derlendiği makinenin
  mimarisini taşır. Bir Mac'te derleyip diğerine kopyalamayın — her makinede
  `kur.sh`/`make install` çalıştırın.
- **Notarize edilmemiştir** (ad-hoc imza).
- Kart tipi: **AKİS** (doğrulanan). Diğer token'lar (SafeNet, SafeSign,
  IDPrime, OpenSC) sürücü listesine eklendi ama donanım olmadığı için test
  edilmedi.
- **Şifre çözme (`decrypt`) test edilmedi.** Şifreli KEP içeriği için gereken
  `Session.decrypt(byte[])` shim ile eklendi ve API denetiminden geçiyor, ancak
  gerçek şifreli bir iletiyle denenmedi.
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
