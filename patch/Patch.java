import java.io.File;
import java.util.ArrayList;
import java.util.List;

import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtConstructor;
import javassist.CtMethod;
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
