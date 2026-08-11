package com.tnbt.imza.applet;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

/**
 * macOS icin PKCS#11 modul listesi.
 *
 * Orijinal jar'in macOS listesi yalnizca {@code libeTPkcs11.dylib} ve
 * {@code libaetpkss.dylib} icerir; Turkiye'de yaygin olan AKIS (TUBITAK)
 * surucusu listede YOKTUR. Bu yuzden AKIS karti takili olsa bile sertifika
 * listesi bos gelir.
 *
 * Burada her surucu icin once bilinen mutlak yollar denenir (dosya varsa o
 * kullanilir), hicbiri yoksa cikplak ad birakilir; cikplak adi dyld kendi
 * arama yollarindan cozer. Ayni surucunun iki farkli yolla iki kez
 * yuklenmesi (ve sertifikalarin cift gorunmesi) boylece onlenir.
 *
 * {@code -Dtnb.pkcs11.modules=/yol/bir.dylib,/yol/iki.dylib} ile liste
 * tamamen degistirilebilir (sorun giderme icin).
 */
public final class MacPkcs11Modules {

    /** Her satir bir surucu: once mutlak aday yollar, en sonda cikplak ad. */
    private static final String[][] CANDIDATES = {
        // AKIS - TUBITAK BILGEM (e-imza kartlarinin cogu)
        { "/usr/local/lib/libakisp11.dylib",
          "/Library/Java/Extensions/libakisp11.dylib",
          "libakisp11.dylib" },
        // SafeNet / Aladdin eToken
        { "/usr/local/lib/libeTPkcs11.dylib",
          "/Library/Frameworks/eToken.framework/Versions/A/libeToken.dylib",
          "libeTPkcs11.dylib" },
        // A.E.T. SafeSign
        { "/usr/local/lib/libaetpkss.dylib",
          "/Applications/tokenadmin.app/Contents/Frameworks/libaetpkss.dylib",
          "libaetpkss.dylib" },
        // Gemalto / Thales IDPrime
        { "/usr/local/lib/libgtop11dotnet.dylib",
          "/Library/Frameworks/eToken.framework/Versions/A/libIDPrimePKCS11.dylib" },
        // OpenSC (genel amacli; AKIS disi kartlar icin)
        { "/Library/OpenSC/lib/opensc-pkcs11.so",
          "/usr/local/lib/opensc-pkcs11.so",
          "/opt/homebrew/lib/opensc-pkcs11.so" },
    };

    private MacPkcs11Modules() {
    }

    public static String[] list() {
        String override = System.getProperty("tnb.pkcs11.modules");
        if (override != null && override.trim().length() > 0) {
            String[] parts = override.split(",");
            List<String> cleaned = new ArrayList<String>();
            for (int i = 0; i < parts.length; i++) {
                String p = parts[i].trim();
                if (p.length() > 0) {
                    cleaned.add(p);
                }
            }
            return cleaned.toArray(new String[cleaned.size()]);
        }

        List<String> out = new ArrayList<String>();
        for (int g = 0; g < CANDIDATES.length; g++) {
            String[] group = CANDIDATES[g];
            String bare = null;
            boolean found = false;
            for (int i = 0; i < group.length; i++) {
                String path = group[i];
                if (path.indexOf('/') < 0) {
                    bare = path;
                    continue;
                }
                if (new File(path).isFile()) {
                    out.add(path);
                    found = true;
                    break;
                }
            }
            if (!found && bare != null) {
                out.add(bare);
            }
        }
        return out.toArray(new String[out.size()]);
    }
}
