import java.io.File;
import java.util.ArrayList;
import java.util.List;

import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtConstructor;
import javassist.CtField;
import javassist.CtMethod;
import javassist.CtNewMethod;
import javassist.Modifier;
import javassist.expr.ExprEditor;
import javassist.expr.NewExpr;

/**
 * TNBTeknolojiImza.jar'i macOS / Apple Silicon (arm64) icin yamalar.
 *
 * NEDEN:
 *   Orijinal jar kart erisimini IAIK PKCS#11 Wrapper'in native parcasi uzerinden
 *   yapar. Jar'daki libpkcs11wrapper.jnilib yalnizca ppc64 / ppc7400 / i386 /
 *   x86_64 dilimleri icerir; arm64 YOKTUR. Apple Silicon'da arm64 bir JVM bunu
 *   yukleyemez ve uygulama "UnsatisfiedLinkError" ile sertifika listesini hic
 *   dolduramaz. Ikinci sorun: macOS varsayilan PKCS#11 modul listesinde AKIS yok.
 *
 * NASIL:
 *   IAIK'in native katmani yerine ayni iaik.pkcs.pkcs11 API'sini SunPKCS11
 *   (JDK'nin jdk.crypto.cryptoki modulu) uzerine oturtan
 *   org.xipki.iaik:sunpkcs11-wrapper kullanilir. Saf Java oldugu icin arm64'te
 *   native derleme veya Rosetta gerekmez.
 *
 * Yamalar (hedef bulunamazsa build BILEREK patlar; saticinin jar'i degisirse
 * sessizce bozuk paket uretmeyelim):
 *   1) objects.Object -> objects.PKCS11Object  (sunpkcs11-wrapper'daki ad degisikligi)
 *   2) Pkcs11Shell    : native wrapper yolunu yok say (tek argumanli getInstance)
 *   3) copyPkcs11WrapperDll : .jnilib jar'dan cikarildi, sabit isaretci don
 *   4) getDefaultPkcs11Modules : AKIS dahil macOS modul listesi
 *   5) main : tarayici argumanini zorla + loglari ~/Library/Logs altina al
 */
public final class Patch {

    private static final String OLD_OBJECT = "iaik.pkcs.pkcs11.objects.Object";
    private static final String NEW_OBJECT = "iaik.pkcs.pkcs11.objects.PKCS11Object";

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            throw new IllegalArgumentException("kullanim: Patch <acilmis-jar-dizini>");
        }
        String dir = new File(args[0]).getAbsolutePath();

        ClassPool cp = ClassPool.getDefault();
        cp.insertClassPath(dir);

        shim(cp, dir);

        // --- 1) objects.Object -> objects.PKCS11Object -------------------------
        List<String> appClasses = classesUnder(new File(dir, "com"), dir);
        if (appClasses.isEmpty()) {
            throw new IllegalStateException("com/ altinda sinif yok: " + dir);
        }
        for (String cls : appClasses) {
            CtClass ct = cp.get(cls);
            ct.replaceClassName(OLD_OBJECT, NEW_OBJECT);
            ct.writeFile(dir);
            ct.detach();
        }
        say(appClasses.size() + " sinifta " + OLD_OBJECT + " -> " + NEW_OBJECT);

        // --- 2) Pkcs11Shell: native wrapper yolunu yok say ---------------------
        // sunpkcs11-wrapper'da yalnizca Module.getInstance(String) var; iki
        // argumanli (modul, native-wrapper) surumu yok. Alan null olunca
        // Pkcs11Shell zaten tek argumanli dala giriyor.
        CtClass shell = cp.get("com.tnbt.imza.shell.pkcs11.Pkcs11Shell");
        CtConstructor[] ctors = shell.getDeclaredConstructors();
        if (ctors.length == 0) {
            throw new IllegalStateException("Pkcs11Shell yapicisi bulunamadi");
        }
        for (CtConstructor c : ctors) {
            c.insertAfter("this.pkcs11WrapperPath = null;");
        }
        shell.writeFile(dir);
        say("Pkcs11Shell: native wrapper yolu yok sayildi");

        // --- 3/4/5) MainApplet -------------------------------------------------
        CtClass app = cp.get("com.tnbt.imza.applet.MainApplet");

        // 3) .jnilib artik jar'da yok. Bu metot null donerse MainApplet
        //    isPkcs11Supported=false yapip kart okumayi tamamen kapatiyor.
        //    Donen degerin icerigi (2) yuzunden hicbir yerde kullanilmiyor.
        method(app, "copyPkcs11WrapperDll").setBody("{ return \"sunpkcs11\"; }");
        say("MainApplet.copyPkcs11WrapperDll: native .jnilib gerekmiyor");

        // 4) macOS modul listesi (orijinalinde AKIS yok).
        method(app, "getDefaultPkcs11Modules")
                .setBody("{ return com.tnbt.imza.applet.MacPkcs11Modules.list(); }");
        say("MainApplet.getDefaultPkcs11Modules: AKIS + digerleri");

        // 5) main:
        //    a) Chrome, native messaging host'u argv[1]='chrome-extension://<id>/'
        //       ile calistirir. Orijinal kod args[0]'in "chrome" olmasini bekler
        //       (Windows'ta .bat sabit "Chrome" geciyor). Argumani zorluyoruz;
        //       ayrica bos argv'de olusacak ArrayIndexOutOfBounds da kalkiyor.
        //    b) Loglar ev dizininin kokune degil ~/Library/Logs altina yazilsin.
        CtMethod main = method(app, "main");
        main.instrument(new ExprEditor() {
            @Override
            public void edit(NewExpr e) throws javassist.CannotCompileException {
                if ("java.io.File".equals(e.getClassName())) {
                    e.replace("{ $_ = new java.io.File("
                            + "com.tnbt.imza.applet.MacPaths.redirect($1)); }");
                }
            }
        });
        main.insertBefore("{ $1 = new String[]{ \"Chrome\" }; }");
        say("MainApplet.main: tarayici argumani zorlandi + log yolu ~/Library/Logs");

        app.writeFile(dir);
    }

    /**
     * sunpkcs11-wrapper, IAIK API'sinin birebir kopyasi degil. Uygulamanin
     * cagirdigi ama yeni wrapper'da bulunmayan uyeleri buraya ekliyoruz.
     * Eksik liste ApiCheck ile bulundu; en kritigi Mechanism.RSA_PKCS —
     * imzalama tam olarak orada NoSuchFieldError ile duruyordu (sertifika
     * listeleme Mechanism'e hic dokunmadigi icin sorunsuz calisiyordu).
     */
    private static void shim(ClassPool cp, String dir) throws Exception {
        // --- Mechanism: IAIK'te hazir sabitler vardi, burada yalnizca
        //     Mechanism.get(long) var. PKCS#11 CKM_* kodlariyla geri ekliyoruz.
        CtClass mech = cp.get("iaik.pkcs.pkcs11.Mechanism");
        String[][] constants = {
            { "RSA_PKCS_KEY_PAIR_GEN", "0" },   // CKM_RSA_PKCS_KEY_PAIR_GEN
            { "RSA_PKCS",              "1" },   // CKM_RSA_PKCS       <- imzalama
            { "RSA_9796",              "2" },   // CKM_RSA_9796
            { "RSA_X_509",             "3" },   // CKM_RSA_X_509
            { "RSA_PKCS_OAEP",         "9" },   // CKM_RSA_PKCS_OAEP
        };
        StringBuilder init = new StringBuilder("{");
        for (String[] c : constants) {
            // final YAPMA: Javassist derleyicisi <clinit> icinde final alana
            // atamayi reddediyor; uygulama bu alanlari yalnizca okuyor.
            CtField f = new CtField(mech, c[0], mech);
            f.setModifiers(Modifier.PUBLIC | Modifier.STATIC);
            mech.addField(f);
            init.append("iaik.pkcs.pkcs11.Mechanism.").append(c[0])
                .append(" = iaik.pkcs.pkcs11.Mechanism.get(").append(c[1]).append("L);");
        }
        init.append("}");
        mech.makeClassInitializer().insertAfter(init.toString());
        mech.writeFile(dir);
        say("shim: Mechanism.{RSA_PKCS, RSA_X_509, RSA_9796, RSA_PKCS_OAEP,"
                + " RSA_PKCS_KEY_PAIR_GEN} sabitleri eklendi");

        // --- Session: IAIK'te tek argumanli encrypt/decrypt vardi; burada
        //     yalnizca tampon veren 6 argumanli surumler var.
        CtClass session = cp.get("iaik.pkcs.pkcs11.Session");
        for (String op : new String[] { "encrypt", "decrypt" }) {
            session.addMethod(CtNewMethod.make(
                "public byte[] " + op + "(byte[] in)"
                    + " throws iaik.pkcs.pkcs11.TokenException {"
                    // RSA icin cikti anahtar boyutunu asmaz; 512 bayt pay yeter.
                    + "  byte[] buf = new byte[in.length + 512];"
                    + "  int n = this." + op + "(in, 0, in.length, buf, 0, buf.length);"
                    + "  byte[] out = new byte[n];"
                    + "  java.lang.System.arraycopy(buf, 0, out, 0, n);"
                    + "  return out;"
                    + "}", session));
        }
        session.writeFile(dir);
        say("shim: Session.encrypt(byte[]) / Session.decrypt(byte[]) eklendi");

        // --- Functions.toFullHexString(int): hata kodunu
        //     ExceptionMessages.properties anahtar bicimine cevirir
        //     (8 hane, buyuk harf, sifir dolgulu -> "000000A0" = CKR_PIN_INCORRECT).
        CtClass functions = cp.get("iaik.pkcs.pkcs11.wrapper.Functions");
        functions.addMethod(CtNewMethod.make(
            "public static java.lang.String toFullHexString(int value) {"
                + "  java.lang.String s ="
                + "    java.lang.Integer.toHexString(value).toUpperCase();"
                + "  java.lang.StringBuffer b = new java.lang.StringBuffer();"
                + "  for (int i = s.length(); i < 8; i++) { b.append('0'); }"
                + "  b.append(s);"
                + "  return b.toString();"
                + "}", functions));
        functions.writeFile(dir);
        say("shim: Functions.toFullHexString(int) eklendi (hata kodu -> mesaj)");

        // --- Module.getInstance(modul, nativeWrapper): (2) numarali yama
        //     yuzunden artik cagrilmiyor ama sabit havuzunda referans duruyor;
        //     dogrulayici tatmin olsun diye tek argumanliya yonlendiriyoruz.
        CtClass module = cp.get("iaik.pkcs.pkcs11.Module");
        module.addMethod(CtNewMethod.make(
            "public static iaik.pkcs.pkcs11.Module getInstance("
                + "java.lang.String modulePath, java.lang.String wrapperPath)"
                + " throws java.io.IOException {"
                + "  return iaik.pkcs.pkcs11.Module.getInstance(modulePath);"
                + "}", module));
        module.writeFile(dir);
        say("shim: Module.getInstance(String,String) eklendi (olu dal)");

        mech.detach();
        session.detach();
        functions.detach();
        module.detach();
    }

    private static CtMethod method(CtClass ct, String name) throws Exception {
        CtMethod[] all = ct.getDeclaredMethods();
        for (CtMethod m : all) {
            if (m.getName().equals(name)) {
                return m;
            }
        }
        throw new IllegalStateException("yama hedefi bulunamadi: "
                + ct.getName() + "." + name + "  (saticinin jar'i degismis olabilir)");
    }

    private static void say(String s) {
        System.out.println("  yamalandi: " + s);
    }

    /** dir altindaki tum .class dosyalarinin ikili adlarini dondurur. */
    private static List<String> classesUnder(File root, String base) {
        List<String> out = new ArrayList<String>();
        collect(root, base.length() + 1, out);
        return out;
    }

    private static void collect(File f, int prefix, List<String> out) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) {
                for (File k : kids) {
                    collect(k, prefix, out);
                }
            }
        } else if (f.getName().endsWith(".class")) {
            String p = f.getAbsolutePath().substring(prefix);
            out.add(p.substring(0, p.length() - ".class".length())
                    .replace(File.separatorChar, '.'));
        }
    }
}
