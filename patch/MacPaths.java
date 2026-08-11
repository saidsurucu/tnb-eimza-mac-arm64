package com.tnbt.imza.applet;

import java.io.File;

/**
 * Log dosyalarini macOS'un standart yerine tasir.
 *
 * Orijinal jar loglari {@code ~/TnbTeknolojiImza.log} ve
 * {@code ~/TnbTeknolojiImza.err.log} olarak ev dizininin KOKUNE yazar
 * (Windows aliskanligi). macOS'ta dogru yer {@code ~/Library/Logs/...}.
 */
public final class MacPaths {

    private static final String DIR = "Library/Logs/TNBTeknolojiImza";

    private MacPaths() {
    }

    /**
     * Orijinal kodun urettigi log yolunu ~/Library/Logs altina cevirir.
     * Log disi bir yol gelirse dokunmadan geri dondurur.
     */
    public static String redirect(String originalPath) {
        if (originalPath == null) {
            return null;
        }
        String name = new File(originalPath).getName();
        if (!name.endsWith(".log")) {
            return originalPath;
        }
        File dir = new File(System.getProperty("user.home"), DIR);
        if (!dir.isDirectory() && !dir.mkdirs()) {
            return originalPath; // olusturulamadiysa eski davranisa don
        }
        return new File(dir, name).getAbsolutePath();
    }
}
