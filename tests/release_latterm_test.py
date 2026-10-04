"""Exercise release failure cleanup with fake build/signing tools, offline."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseCleanupTests(unittest.TestCase):
    def run_failure(self, *, existing_output=False, existing_plist=True, fail_build=False):
        with tempfile.TemporaryDirectory(prefix="latterm-release-test-") as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            (root / "plists").mkdir()
            commands = root / "commands"
            commands.mkdir()
            script = root / "tools/release_latterm.sh"
            shutil.copyfile(ROOT / "tools/release_latterm.sh", script)
            version = root / "version.txt"
            version.write_bytes(b"26.9.2\n")
            plist = root / "plists/iTerm2.plist"
            original_plist = b"existing generated plist\n"
            if existing_plist:
                plist.write_bytes(original_plist)
            if existing_output:
                (root / "Build/Releases/26.10.1").mkdir(parents=True)
            # No real keychain, build, network, or notarization operations run.
            stubs = {
                "security": "echo 'Developer ID Application: Test'\n" if fail_build else "exit 1\n",
                "xcrun": 'test "$1" = notarytool && test "$2" = history\n',
                "make": "printf 'build changed version\\n' > version.txt\n"
                        "printf 'build changed plist\\n' > plists/iTerm2.plist\nexit 7\n",
            }
            for name, body in stubs.items():
                command = commands / name
                command.write_text("#!/bin/bash\n" + body)
                command.chmod(0o755)
            result = subprocess.run(
                ["/bin/bash", str(script), "26.10.1"], cwd=root,
                env={**os.environ, "PATH": f"{commands}:/usr/bin:/bin:/usr/sbin:/sbin"},
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            if existing_output:
                self.assertIn("release output already exists", result.stderr)
            elif fail_build:
                self.assertEqual(result.returncode, 7)
            else:
                self.assertIn("no Developer ID Application identity", result.stderr)
            self.assertEqual(version.read_bytes(), b"26.9.2\n")
            if existing_plist:
                self.assertEqual(plist.read_bytes(), original_plist)
            else:
                self.assertFalse(plist.exists())

    def test_existing_release_preserves_inputs_before_backup(self):
        self.run_failure(existing_output=True)

    def test_signing_preflight_failure_preserves_inputs(self):
        self.run_failure()

    def test_build_failure_restores_existing_inputs(self):
        self.run_failure(fail_build=True)

    def test_build_failure_removes_only_newly_generated_plist(self):
        self.run_failure(fail_build=True, existing_plist=False)


if __name__ == "__main__":
    unittest.main()
