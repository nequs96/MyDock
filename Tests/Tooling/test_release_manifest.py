"""Isolated artifact fixtures; no builds, signing, mounts or native changes."""
import importlib.util
import json
import io
import shutil
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
        self.git_status = ""
        self.load_commands = "cmd LC_BUILD_VERSION\n minos 13.0\n sdk 26.4"

    def package(self):
        with zipfile.ZipFile(self.archive, "w") as zipped:
            for path in self.app.rglob("*"):
                if path.is_file():
                    zipped.write(path, path.relative_to(self.root))

    def command(self, *args, required=True):
        if args[0] == "lipo": return 0, self.architectures
        if args[0] == "otool": return 0, self.load_commands
        if args[0] == "codesign":
            if args[1] == "-d": return 0, self.signature
            return (0 if self.signature_verifies else 1), ""
        if args[0] == "git": return 0, "fixture-head" if args[-1] == "HEAD" else self.git_status
        return 0, "fixture toolchain"

    def run_manifest(self, qualification="ci", command=None):
        arguments = ["manifest", "--app", str(self.app), "--archive", str(self.archive),
                     "--output", str(self.output), "--qualification", qualification]
        with patch.object(sys, "argv", arguments), patch.object(manifest, "command", command or self.command):
            manifest.main()

    def dmg_fixture(self, mutate=None):
        """A DMG whose `hdiutil attach` copies the app into the mountpoint; records every hdiutil call."""
        self.archive = self.root / "MyDock.dmg"
        self.archive.write_bytes(b"fixture disk image")
        calls = []
        def command(*args, required=True):
            if args[0] != "hdiutil":
                return self.command(*args, required=required)
            calls.append(tuple(args[:2]))
            if args[1] == "attach":
                mounted = Path(args[args.index("-mountpoint") + 1]) / self.app.name
                shutil.copytree(self.app, mounted, symlinks=True)
                if mutate:
                    mutate(mounted)
            return 0, ""
        return command, calls

    def test_archive_mismatch_refuses_output(self):
        self.package()
        (self.app / "Contents/MacOS/MyDock").write_bytes(b"changed executable")
        with self.assertRaisesRegex(RuntimeError, "bytes do not match"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_member_size_mismatch_refuses_output(self):
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

    def test_zip_stream_shorter_than_declared_size_is_rejected(self):
        self.package()
        original_open = zipfile.ZipFile.open
        def short_open(zipped, name, *args, **kwargs):
            if str(name).endswith("Contents/MacOS/MyDock"):
                return io.BytesIO(b"fixture")
            return original_open(zipped, name, *args, **kwargs)
        with patch.object(zipfile.ZipFile, "open", short_open):
            with self.assertRaisesRegex(RuntimeError, "member size"):
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

    def test_zip_missing_app_file_refuses_output(self):
        self.package()
        (self.app / "Contents/Resources/Added.txt").write_bytes(b"not in the archive")
        with self.assertRaisesRegex(RuntimeError, "inventory does not match"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_zip_macosx_bookkeeping_is_accepted(self):
        self.package()
        with zipfile.ZipFile(self.archive, "a") as zipped:
            zipped.writestr("__MACOSX/MyDock.app/Contents/._Info.plist", b"resource fork")
        self.run_manifest()
        self.assertTrue(self.output.exists())

    def test_other_archive_types_are_refused(self):
        self.archive = self.root / "MyDock.tar"
        self.archive.write_bytes(b"fixture tarball")
        with self.assertRaisesRegex(RuntimeError, "Only ZIP or DMG"):
            self.run_manifest()
        self.assertFalse(self.output.exists())

    def test_dmg_matching_app_is_recorded_and_detached(self):
        command, calls = self.dmg_fixture()
        self.run_manifest(command=command)
        self.assertTrue(self.output.exists())
        self.assertEqual(calls, [("hdiutil", "attach"), ("hdiutil", "detach")])

    def test_dmg_mismatch_refuses_output_and_still_detaches(self):
        command, calls = self.dmg_fixture(lambda app: (app / "Contents/MacOS/MyDock").write_bytes(b"changed executable"))
        with self.assertRaisesRegex(RuntimeError, "DMG app does not match"):
            self.run_manifest(command=command)
        self.assertFalse(self.output.exists())
        self.assertEqual(calls, [("hdiutil", "attach"), ("hdiutil", "detach")])

    def test_missing_deployment_target_refuses_output(self):
        self.package()
        self.load_commands = "cmd LC_BUILD_VERSION\n sdk 26.4"
        with self.assertRaisesRegex(RuntimeError, "Missing deployment target"):
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
        paths = {item["path"] for item in result["source"]["files"]}
        self.assertIn("project.yml", paths)
        self.assertIn("Xcode/MyDock-Info.plist", paths)
        self.assertFalse(result["source"]["hasTrackedChanges"])
        self.assertFalse(result["source"]["hasUntrackedSources"])

    def test_ci_records_untracked_sources(self):
        self.package()
        self.git_status = "?? Sources/MyDock/Untracked.swift\n?? notes.txt"
        self.run_manifest()
        result = json.loads(self.output.read_text())
        self.assertFalse(result["source"]["hasTrackedChanges"])
        self.assertTrue(result["source"]["hasUntrackedSources"])

    def test_release_refuses_untracked_sources_and_tracked_changes(self):
        self.package()
        self.signature = "Authority=Developer ID Application: Fixture"
        for status in ("?? Sources/MyDock/Untracked.swift", " M README.md"):
            self.git_status = status
            with self.assertRaisesRegex(RuntimeError, "clean source tree"):
                self.run_manifest("release")
            self.assertFalse(self.output.exists())

    def test_failing_required_command_reports_its_output(self):
        script = "import sys; sys.stdout.write('x' * 5000); sys.stderr.write('stapler: The staple failed'); sys.exit(3)"
        with self.assertRaises(RuntimeError) as raised:
            manifest.command(sys.executable, "-c", script)
        message = str(raised.exception)
        self.assertIn("failed (3)", message)
        self.assertIn("The staple failed", message)
        self.assertLess(len(message), 2200)
        code, output = manifest.command(sys.executable, "-c", script, required=False)
        self.assertEqual(code, 3)
        self.assertIn("The staple failed", output)


if __name__ == "__main__":
    unittest.main()
