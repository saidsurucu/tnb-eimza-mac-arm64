import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import javassist.ClassPool;
import javassist.CtClass;
import javassist.bytecode.ClassFile;
import javassist.bytecode.ConstPool;

/**
 * Uygulama siniflarinin cagirdigi HER iaik.* uyesinin (metot/alan), yerine
 * konan sunpkcs11-wrapper'da GERCEKTEN var oldugunu dogrular.
 *
 * Neden gerekli: sunpkcs11-wrapper, IAIK API'sinin birebir kopyasi degil.
 * Sinif adlari ayni olsa da bazi imzalar farkli — orn. IAIK'te
 * {@code Session.decrypt(byte[])} varken burada yalnizca
 * {@code Session.decrypt(byte[],int,int,byte[],int,int)} var. Bu tur bir fark
 * derleme sirasinda GORULMEZ; ancak kullanici o ozelligi calistirdiginda
 * NoSuchMethodError olarak patlar. Sertifika listeleme calisip imzalama
 * patlarsa sebebi tam olarak budur.
 *
 * Bu yuzden yamali jar'i paketlemeden once tum cagri yerleri statik olarak
 * denetlenir ve eksik varsa derleme BILEREK durur.
 */
public final class ApiCheck {

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            throw new IllegalArgumentException("kullanim: ApiCheck <acilmis-jar-dizini>");
        }
        File root = new File(args[0]).getAbsoluteFile();

        ClassPool cp = ClassPool.getDefault();
        cp.insertClassPath(root.getAbsolutePath());

        List<File> appClasses = new ArrayList<File>();
        collect(new File(root, "com"), appClasses);
        if (appClasses.isEmpty()) {
            throw new IllegalStateException("com/ altinda sinif yok: " + root);
        }

        Set<String> missing = new LinkedHashSet<String>();
        int checked = 0;

        for (File f : appClasses) {
            ClassFile cf;
            DataInputStream in = new DataInputStream(new FileInputStream(f));
            try {
                cf = new ClassFile(in);
            } finally {
                in.close();
            }
            ConstPool pool = cf.getConstPool();

            for (int i = 1; i < pool.getSize(); i++) {
                int tag;
                try {
                    tag = pool.getTag(i);
                } catch (RuntimeException e) {
                    continue; // long/double sonrasi kullanilmayan yuva
                }

                String owner;
                String name;
                String desc;
                boolean isField = false;

                if (tag == ConstPool.CONST_Methodref) {
                    owner = pool.getMethodrefClassName(i);
                    name = pool.getMethodrefName(i);
                    desc = pool.getMethodrefType(i);
                } else if (tag == ConstPool.CONST_InterfaceMethodref) {
                    owner = pool.getInterfaceMethodrefClassName(i);
                    name = pool.getInterfaceMethodrefName(i);
                    desc = pool.getInterfaceMethodrefType(i);
                } else if (tag == ConstPool.CONST_Fieldref) {
                    owner = pool.getFieldrefClassName(i);
                    name = pool.getFieldrefName(i);
                    desc = pool.getFieldrefType(i);
                    isField = true;
                } else {
                    continue;
                }

                if (owner == null || !owner.startsWith("iaik.")) {
                    continue;
                }
                checked++;

                CtClass target;
                try {
                    target = cp.get(owner);
                } catch (javassist.NotFoundException e) {
                    missing.add("SINIF YOK   " + owner
                            + "   (kullanan: " + cf.getName() + ")");
                    continue;
                }

                try {
                    if (isField) {
                        target.getField(name, desc);
                    } else if ("<init>".equals(name)) {
                        target.getConstructor(desc);
                    } else {
                        target.getMethod(name, desc);
                    }
                } catch (javassist.NotFoundException e) {
                    missing.add("UYE YOK     " + owner + "." + name + desc
                            + "   (kullanan: " + cf.getName() + ")");
                }
            }
        }

        System.out.println("  API denetimi: " + appClasses.size() + " sinif, "
                + checked + " iaik referansi");

        if (!missing.isEmpty()) {
            System.out.println();
            System.out.println("  sunpkcs11-wrapper'da KARSILIGI OLMAYAN cagrilar:");
            for (String m : missing) {
                System.out.println("    " + m);
            }
            System.out.println();
            throw new IllegalStateException(missing.size()
                    + " uyumsuz cagri var — bunlar calisma zamaninda"
                    + " NoSuchMethodError verir; koprü (shim) yazilmali.");
        }
        System.out.println("  API denetimi TEMIZ (uyumsuz cagri yok)");
    }

    private static void collect(File f, List<File> out) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) {
                for (File k : kids) {
                    collect(k, out);
                }
            }
        } else if (f.getName().endsWith(".class")) {
            out.add(f);
        }
    }
}
