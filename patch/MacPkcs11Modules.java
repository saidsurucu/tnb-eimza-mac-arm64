package com.tnbt.imza.applet;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * macOS icin PKCS#11 modul listesi.
 *
 * Iki sorunu birden cozer:
 *
 * 1) Orijinal jar'in macOS listesi yalnizca {@code libeTPkcs11.dylib} ve
 *    {@code libaetpkss.dylib} icerir; Turkiye'de yaygin olan AKIS (TUBITAK)
 *    surucusu listede YOKTUR. Bu yuzden AKIS karti takili olsa bile sertifika
 *    listesi bos gelir.
 *
 * 2) Orijinal liste cikplak dosya adlari kullanir ({@code "libeTPkcs11.dylib"}).
 *    Native IAIK wrapper bunlari dlopen'in arama yollarindan cozebiliyordu;
 *    yerine kullandigimiz sunpkcs11-wrapper ise once dosyanin VARLIGINI
 *    denetliyor ve bulunmayan her ad icin FileNotFoundException firlatiyor.
 *    Bu hem ise yaramaz hem de her calismada log'u yigin izleriyle doldurur.
 *
 * Bu yuzden burada yalnizca DISKTE GERCEKTEN VAR OLAN mutlak yollar dondurulur;
 * her surucu icin bilinen dizinler taranir ve ilk bulunan kullanilir (ayni
 * surucunun iki yoldan yuklenip sertifikalarin cift gorunmesi de boylece
 * onlenir).
 *
 * {@code -Dtnb.pkcs11.modules=/yol/bir.dylib,/yol/iki.dylib} ile liste tamamen
 * degistirilebilir (sorun giderme icin; varlik denetimi uygulanmaz).
 */
public final class MacPkcs11Modules {

    /** PKCS#11 surucusunun bulunabilecegi dizinler (oncelik sirasiyla). */
    private static final String[] SEARCH_DIRS = {
        "/usr/local/lib",
        "/Library/Java/Extensions",
        System.getProperty("user.home") + "/Library/Java/Extensions",
        "/Library/Frameworks/eToken.framework/Versions/A",
        "/Applications/tokenadmin.app/Contents/Frameworks",
        "/Library/OpenSC/lib",
        "/opt/homebrew/lib",
        "/usr/lib",
    };

    /** Bilinen surucu dosya adlari (denenme sirasiyla). */
    private static final String[] DRIVERS = {
        "libakisp11.dylib",        // AKIS - TUBITAK BILGEM (en yaygin)
        "libeTPkcs11.dylib",       // SafeNet / Aladdin eToken
        "libeToken.dylib",         // eToken framework
        "libaetpkss.dylib",        // A.E.T. SafeSign
        "libIDPrimePKCS11.dylib",  // Thales / Gemalto IDPrime
        "libgtop11dotnet.dylib",   // Gemalto .NET
        "opensc-pkcs11.so",        // OpenSC (genel amacli)
    };

    private MacPkcs11Modules() {
    }

    public static String[] list() {
        String override = System.getProperty("tnb.pkcs11.modules");
        if (override != null && override.trim().length() > 0) {
            List<String> cleaned = new ArrayList<String>();
            String[] parts = override.split(",");
            for (int i = 0; i < parts.length; i++) {
                String p = parts[i].trim();
                if (p.length() > 0) {
                    cleaned.add(p);
                }
            }
            return cleaned.toArray(new String[cleaned.size()]);
        }

        Set<String> found = new LinkedHashSet<String>();
        for (int d = 0; d < DRIVERS.length; d++) {
            for (int s = 0; s < SEARCH_DIRS.length; s++) {
                File candidate = new File(SEARCH_DIRS[s], DRIVERS[d]);
                if (candidate.isFile()) {
                    found.add(candidate.getAbsolutePath());
                    break; // bu surucu icin ilk bulunan yeterli
                }
            }
        }
        return found.toArray(new String[found.size()]);
    }
}
