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

        if (failures > 0) {
            throw new IllegalStateException(failures + " shim dogrulamasi basarisiz");
        }
        System.out.println("  shim calisma zamani denetimi TEMIZ");
    }
}
