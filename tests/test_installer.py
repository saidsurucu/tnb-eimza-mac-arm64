"""Installer regression tests; no system drivers, network or builds are used.

Run with: python3 -m unittest discover -s tests -v
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DRIVERS = ("libakisp11.dylib", "libeTPkcs11.dylib", "libaetpkss.dylib")


class InstallerTest(unittest.TestCase):
    def run_installer(self, architecture):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "app").mkdir()
            (root / "assets").mkdir()
            (root / "assets/TNBTeknolojiImza.icns").touch()
            (root / "Makefile").touch()
            (root / "bin").mkdir()
            (root / "drivers").mkdir()

            # Redirect only the three system-driver paths in a temporary copy.
            # All control flow, including set -e and make ordering, is unchanged.
            script = (ROOT / "kur.sh").read_text()
            for driver in DRIVERS:
                script = script.replace(
                    "/usr/local/lib/" + driver, str(root / "drivers" / driver)
                )
            (root / "kur.sh").write_text(script)
            if architecture is not None:
                (root / "drivers" / DRIVERS[0]).touch()

            commands = {
                "id": "echo 501",
                "uname": 'if [ "$1" = -s ]; then echo Darwin; else echo arm64; fi',
                "xcode-select": "exit 0",
                "lipo": 'if [ "$TEST_ARCH" = unreadable ]; then exit 1; fi\n'
                        'echo "$TEST_ARCH"',
                "make": 'echo "$*" >> "$TEST_MAKE_LOG"',
            }
            for name, body in commands.items():
                command = root / "bin" / name
                command.write_text("#!/bin/bash\n" + body + "\n")
                command.chmod(0o755)

            log = root / "make.log"
            env = dict(os.environ, PATH=str(root / "bin") + ":/usr/bin:/bin",
                       HOME=str(root), TEST_ARCH=architecture or "",
                       TEST_MAKE_LOG=str(log))
            result = subprocess.run(
                ["/bin/bash", str(root / "kur.sh")], cwd=root, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls

    def test_intel_driver_stops_before_any_build(self):
        result, calls = self.run_installer("x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertIn("arm64 DEĞİL", result.stdout)
        self.assertIn("Mac OS Arm (Apple Silicon)", result.stdout)
        self.assertIn("https://akiskart.bilgem.tubitak.gov.tr/tr/destek/", result.stdout)
        self.assertIn("kur.sh'i tekrar çalıştırın", result.stdout)
        self.assertNotIn("Bitti.", result.stdout)

    def test_unreadable_driver_stops_before_any_build(self):
        result, calls = self.run_installer("unreadable")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertIn("Mac OS Arm (Apple Silicon)", result.stdout)

    def test_compatible_drivers_continue(self):
        for architecture in ("arm64", "x86_64 arm64"):
            with self.subTest(architecture=architecture):
                result, calls = self.run_installer(architecture)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(calls, ["jre", "app", "install"])
                self.assertLess(result.stdout.index("sürücü hazır"),
                                result.stdout.index("Runtime ve build"))

    def test_no_driver_keeps_warning_and_allows_install(self):
        result, calls = self.run_installer(None)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(calls, ["jre", "app", "install"])
        self.assertIn("Hiçbir PKCS#11 kart sürücüsü bulunamadı", result.stdout)
        self.assertIn("Mac OS Arm (Apple Silicon)", result.stdout)


if __name__ == "__main__":
    unittest.main()
