"""Isolated artifact fixtures; no builds, signing, mounts or native changes."""
import importlib.util
import json
import io
import stat
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("manifest", ROOT / "Scripts/WriteReleaseManifest.py")
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)


class ReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / "MyDock.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/Resources/Metadata.appintents").mkdir(parents=True)
        (self.app / "Contents/MacOS/MyDock").write_bytes(b"fixture executable")
        (self.app / "Contents/Resources/Metadata.appintents/extract.actionsdata").write_bytes(b"fixture metadata")
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "MyDock", "CFBundleIdentifier": "fixture.mydock",
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1"}))
        self.archive = self.root / "MyDock.zip"
        self.output = self.root / "manifest.json"
        self.architectures = "arm64 x86_64"
        self.signature = "Signature=adhoc"
        self.signature_verifies = True

    def package(self):
        with zipfile.ZipFile(self.archive, "w") as zipped:
            for path in self.app.rglob("*"):
                if path.is_file():
                    zipped.write(path, path.relative_to(self.root))

    def command(self, *args, required=True):
        if args[0] == "lipo": return 0, self.architectures
        if args[0] == "otool": return 0, "cmd LC_BUILD_VERSION\n minos 13.0\n sdk 26.4"
        if args[0] == "codesign":
            if args[1] == "-d": return 0, self.signature
            return (0 if self.signature_verifies else 1), ""
        if args[0] == "git": return 0, "fixture-head" if args[-1] == "HEAD" else ""
        return 0, "fixture toolchain"

    def run_manifest(self, qualification="ci"):
        arguments = ["manifest", "--app", str(self.app), "--archive", str(self.archive),
                     "--output", str(self.output), "--qualification", qualification]
        with patch.object(sys, "argv", arguments), patch.object(manifest, "command", self.command):
            manifest.main()

    def test_archive_mismatch_refuses_output(self):
        self.package()
        (self.app / "Contents/MacOS/MyDock").write_bytes(b"changed executable")
        with self.assertRaisesRegex(RuntimeError, "bytes do not match"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_member_size_budget_rejects_oversized_content(self):
        self.package()
        path = self.app / "Contents/MacOS/MyDock"
        path.write_bytes(b"x")
        with self.assertRaisesRegex(RuntimeError, "member size"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_executable_permissions_must_match(self):
        path = self.app / "Contents/MacOS/MyDock"
        path.chmod(0o755)
        self.package()
        path.chmod(0o644)
        with self.assertRaisesRegex(RuntimeError, "permissions"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_stream_budget_rejects_bytes_beyond_declared_size(self):
        self.package()
        original_open = zipfile.ZipFile.open
        def oversized_open(zipped, name, *args, **kwargs):
            if str(name).endswith("Contents/MacOS/MyDock"):
                return io.BytesIO(b"fixture executable" + b"excess")
            return original_open(zipped, name, *args, **kwargs)
        with patch.object(zipfile.ZipFile, "open", oversized_open):
            with self.assertRaisesRegex(RuntimeError, "size budget"):
                self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_rejects_symlink_disguised_as_regular_file(self):
        self.package()
        rewritten = self.root / "rewritten.zip"
        with zipfile.ZipFile(self.archive) as source, zipfile.ZipFile(rewritten, "w") as target:
            for member in source.infolist():
                data = source.read(member)
                if member.filename.endswith("Contents/MacOS/MyDock"):
                    member.external_attr = (stat.S_IFLNK | 0o644) << 16
                target.writestr(member, data)
        rewritten.replace(self.archive)
        with self.assertRaisesRegex(RuntimeError, "file type"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_rejects_unexpected_payload_outside_app(self):
        self.package()
        with zipfile.ZipFile(self.archive, "a") as zipped:
            zipped.writestr("unexpected.txt", b"outside selected app")
        with self.assertRaisesRegex(RuntimeError, "unexpected files"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_missing_metadata_refuses_output(self):
        (self.app / "Contents/Resources/Metadata.appintents/extract.actionsdata").unlink()
        self.package()
        with self.assertRaisesRegex(RuntimeError, "missing or empty"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_wrong_architecture_refuses_output(self):
        self.package()
        self.architectures = "arm64"
        with self.assertRaisesRegex(RuntimeError, "universal"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_release_rejects_ad_hoc_and_invalid_signatures(self):
        self.package()
        with self.assertRaisesRegex(RuntimeError, "Developer ID"):
            self.run_manifest("release")
        self.signature = "Authority=Developer ID Application: Fixture"
        self.signature_verifies = False
        with self.assertRaisesRegex(RuntimeError, "Developer ID"):
            self.run_manifest("release")
        self.assertFalse(self.output.exists())

    def test_ci_records_exact_bytes_and_keeps_native_qualification_open(self):
        self.package()
        self.run_manifest()
        result = json.loads(self.output.read_text())
        self.assertEqual(result["archive"]["sha256"], manifest.sha256(self.archive))
        self.assertEqual(result["app"]["executableSHA256"], manifest.sha256(self.app / "Contents/MacOS/MyDock"))
        self.assertEqual(result["app"]["deploymentTargets"], {"arm64": "13.0", "x86_64": "13.0"})
        self.assertEqual(result["app"]["signingClass"], "ad-hoc")
        for key in ("nativeAcceptance", "supportedOSRuntimeMatrix", "focusDiscovery", "loginItemAcceptance"):
            self.assertEqual(result["qualification"][key], "open")
        self.assertEqual(result["qualification"]["notarization"], "not-run")
        self.assertIn("MyDock.xcodeproj/project.pbxproj", {item["path"] for item in result["source"]["files"]})


if __name__ == "__main__":
    unittest.main()
