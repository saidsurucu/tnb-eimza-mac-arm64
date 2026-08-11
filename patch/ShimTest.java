import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Shim'in CALISMA ZAMANINDA cozuldugunu dogrular.
 *
 * ApiCheck statik bir denetim: uyenin var oldugunu soyler ama sinif
 * baslatilirken (&lt;clinit&gt;) patlayip patlamadigini bilemez. Mechanism
 * sabitleri statik baslaticiya enjekte edildigi icin bu fark onemli:
 * orada atilacak bir istisna, kullaniciya yine "Veri imzalanirken bir hata
 * olustu" olarak doner. Bu yuzden yamali jar'a karsi gercekten calistiriyoruz.
 */
public final class ShimTest {

    public static void main(String[] args) throws Exception {
        int failures = 0;

        // 1) Mechanism sabitleri: imzalama yolunun okudugu alan.
        Class<?> mech = Class.forName("iaik.pkcs.pkcs11.Mechanism");
        Method getCode = mech.getMethod("getMechanismCode");
        String[][] expected = {
            { "RSA_PKCS_KEY_PAIR_GEN", "0" },
            { "RSA_PKCS", "1" },
            { "RSA_9796", "2" },
            { "RSA_X_509", "3" },
            { "RSA_PKCS_OAEP", "9" },
        };
        for (String[] e : expected) {
            Field f = mech.getField(e[0]);
            Object value = f.get(null);
            if (value == null) {
                System.out.println("  ✗ Mechanism." + e[0] + " null");
                failures++;
                continue;
            }
            long code = ((Long) getCode.invoke(value)).longValue();
            if (code != Long.parseLong(e[1])) {
                System.out.println("  ✗ Mechanism." + e[0] + " kodu " + code
                        + ", beklenen " + e[1]);
                failures++;
            }
        }

        // 2) Hata kodu -> ExceptionMessages.properties anahtari.
        Class<?> functions = Class.forName("iaik.pkcs.pkcs11.wrapper.Functions");
        Method toFullHex = functions.getMethod("toFullHexString", int.class);
        String hex = (String) toFullHex.invoke(null, Integer.valueOf(0xA0));
        if (!"000000A0".equals(hex)) {
            System.out.println("  ✗ toFullHexString(0xA0) = '" + hex
                    + "', beklenen '000000A0'");
            failures++;
        }
        // Anahtarin gercekten mesaja cozuldugunu de dogrula.
        String msg = java.util.ResourceBundle
                .getBundle("iaik.pkcs.pkcs11.wrapper.ExceptionMessages")
                .getString("0x" + hex).trim();
        if (!"CKR_PIN_INCORRECT".equals(msg)) {
            System.out.println("  ✗ 0x" + hex + " -> '" + msg
                    + "', beklenen 'CKR_PIN_INCORRECT'");
            failures++;
        }

        // 3) Tek argumanli encrypt/decrypt ve iki argumanli getInstance.
        Class<?> session = Class.forName("iaik.pkcs.pkcs11.Session");
        session.getMethod("decrypt", byte[].class);
        session.getMethod("encrypt", byte[].class);
        Class.forName("iaik.pkcs.pkcs11.Module")
             .getMethod("getInstance", String.class, String.class);

        // 4) Uygulamanin imzalama yolunun gectigi sinif gercekten yuklenebiliyor mu.
        Class.forName("com.tnbt.imza.shell.pkcs11.Pkcs11Shell");

        // 5) REGRESYON: deinit -> init dongusu.
        //
        // Uygulama her istekte once deinitShell() (modul basina C_Finalize)
        // sonra initShell() cagiriyor. SunPKCS11 modulu yol basina
        // onbellekledigi icin C_Finalize sonrasi yeniden baslatma SESSIZCE
        // atlaniyordu ve ikinci turdan itibaren her sey
        // CKR_CRYPTOKI_NOT_INITIALIZED veriyordu. Tek turluk selectCertificate
        // calisiyor, cok turlu sign patliyordu — bu yuzden fark edilmesi zor.
        // Module.finalize() islevsizlestirilerek cozuldu; burada dogruluyoruz.
        //
        // Surucu kurulu degilse (CI, kartsiz makine) sessizce atlanir; kart
        // takili olmasi gerekmez, slot sayisi 0 olabilir.
        failures += testDeinitInitCycles();

        if (failures > 0) {
            throw new IllegalStateException(failures + " shim dogrulamasi basarisiz");
        }
        System.out.println("  shim calisma zamani denetimi TEMIZ");
    }

    private static int testDeinitInitCycles() throws Exception {
        Method list = Class.forName("com.tnbt.imza.applet.MacPkcs11Modules")
                .getMethod("list");
        String[] modules = (String[]) list.invoke(null);
        if (modules.length == 0) {
            System.out.println("  (PKCS#11 surucusu yok -> deinit/init dongu"
                    + " testi atlandi)");
            return 0;
        }
        String path = modules[0];

        Class<?> moduleClass = Class.forName("iaik.pkcs.pkcs11.Module");
        Method getInstance = moduleClass.getMethod("getInstance", String.class);
        Method initialize = moduleClass.getMethod("initialize",
                Class.forName("iaik.pkcs.pkcs11.InitializeArgs"));
        Method getSlotList = moduleClass.getMethod("getSlotList", boolean.class);
        Method finalizeModule = moduleClass.getMethod("finalize", Object.class);

        for (int round = 1; round <= 3; round++) {
            Object module = getInstance.invoke(null, path);
            initialize.invoke(module, new Object[] { null });
            try {
                getSlotList.invoke(module, Boolean.TRUE);
            } catch (java.lang.reflect.InvocationTargetException e) {
                System.out.println("  ✗ tur " + round + ": getSlotList basarisiz ("
                        + path + "): " + e.getCause());
                System.out.println("    -> Module.finalize sonrasi yeniden"
                        + " baslatma calismiyor (SunPKCS11 onbellegi)");
                return 1;
            }
            finalizeModule.invoke(module, new Object[] { null });
        }
        return 0;
    }
}
