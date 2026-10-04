#!/usr/bin/env python3
"""Record the exact metadata-bearing app without asserting desktop qualification."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import zipfile
from datetime import datetime, timezone


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(*args, required=True):
    result = subprocess.run(args, capture_output=True, text=True)
    if required and result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode})")
    return result.returncode, (result.stdout + result.stderr).strip()


def inventory(root):
    result = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            result.append({"path": relative, "symlink": str(path.readlink())})
        elif path.is_file():
            result.append({"path": relative, "sha256": sha256(path),
                           "mode": oct(path.stat().st_mode & 0o777)})
    return result


def fingerprint(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def verify_archive(app, archive):
    """Compare packaged bytes with this app; do not extract untrusted ZIP paths."""
    expected = inventory(app)
    if archive.suffix.lower() == ".zip":
        with zipfile.ZipFile(archive) as zipped:
            files = [item for item in zipped.infolist() if not item.is_dir()]
            names = [item.filename for item in files]
            prefix = app.name + "/"
            # ditto may include __MACOSX resource-fork bookkeeping outside the app.
            actual = {name[len(prefix):]: name for name in names if name.startswith(prefix)}
            if any(not name.startswith((prefix, "__MACOSX/")) for name in names):
                raise RuntimeError("Archive contains unexpected files outside the selected app")
            if len(names) != len(set(names)) or set(actual) != {entry["path"] for entry in expected}:
                raise RuntimeError("Archive app inventory does not match the selected app")
            for entry in expected:
                member = zipped.getinfo(actual[entry["path"]])
                expected_size = (app / entry["path"]).stat().st_size if "sha256" in entry else len(entry["symlink"].encode())
                if member.file_size != expected_size:
                    raise RuntimeError("Archive member size does not match the selected app")
                unix_mode = member.external_attr >> 16
                expected_type = stat.S_IFREG if "sha256" in entry else stat.S_IFLNK
                if stat.S_IFMT(unix_mode) != expected_type:
                    raise RuntimeError("Archive Unix file type does not match the selected app")
                if "mode" in entry and (member.external_attr >> 16) & 0o777 != int(entry["mode"], 8):
                    raise RuntimeError("Archive file permissions do not match the selected app")
                with zipped.open(actual[entry["path"]]) as stream:
                    digest = hashlib.sha256()
                    read_size = 0
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        read_size += len(chunk)
                        if read_size > expected_size:
                            raise RuntimeError("Archive member exceeded the selected app size budget")
                        digest.update(chunk)
                    if read_size != expected_size:
                        raise RuntimeError("Archive member size does not match the selected app")
                expected_hash = entry.get("sha256") or hashlib.sha256(entry["symlink"].encode()).hexdigest()
                if digest.hexdigest() != expected_hash:
                    raise RuntimeError("Archive app bytes do not match the selected app")
    elif archive.suffix.lower() == ".dmg":
        with tempfile.TemporaryDirectory(prefix="mydock-manifest-") as mountpoint:
            command("hdiutil", "attach", str(archive), "-readonly", "-nobrowse", "-mountpoint", mountpoint)
            try:
                if inventory(Path(mountpoint) / app.name) != expected:
                    raise RuntimeError("DMG app does not match the selected app")
            finally:
                command("hdiutil", "detach", mountpoint)
    else:
        raise RuntimeError("Only ZIP or DMG release archives can be verified")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--qualification", choices=("ci", "release"), required=True)
    parser.add_argument("--archive", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    app = args.app.resolve()
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    verify_archive(app, args.archive.resolve())
    metadata = app / "Contents/Resources/Metadata.appintents"
    if not metadata.is_dir() or not any(p.is_file() for p in metadata.rglob("*")):
        raise RuntimeError("App Intents metadata is missing or empty")
    _, arch_text = command("lipo", "-archs", str(executable))
    architectures = sorted(arch_text.split())
    if architectures != ["arm64", "x86_64"]:
        raise RuntimeError("A universal arm64 + x86_64 artifact is required")
    deployment_targets = {}
    for architecture in architectures:
        _, load_commands = command("otool", "-arch", architecture, "-l", str(executable))
        match = re.search(r"\bminos\s+(\S+)", load_commands) or re.search(r"\bversion\s+(\S+)", load_commands)
        if not match:
            raise RuntimeError(f"Missing deployment target for {architecture}")
        deployment_targets[architecture] = match.group(1)
    signature_result, signature = command("codesign", "-d", "--verbose=4", str(app), required=False)
    signing_class = "unsigned" if signature_result else ("ad-hoc" if "Signature=adhoc" in signature else
        "developer-id" if "Authority=Developer ID Application:" in signature else "other")
    verification, _ = command("codesign", "--verify", "--deep", "--strict", str(app), required=False)
    qualifications = {"metadataPresent": "passed", "universalArchitecture": "passed",
                      "signatureVerification": "passed" if verification == 0 else "not-passed",
                      "nativeAcceptance": "open", "supportedOSRuntimeMatrix": "open",
                      "focusDiscovery": "open", "loginItemAcceptance": "open"}
    if args.qualification == "release":
        if signing_class != "developer-id" or verification:
            raise RuntimeError("Release manifest requires a verified Developer ID signature")
        command("xcrun", "stapler", "validate", str(app))
        command("spctl", "--assess", "--type", "execute", str(app))
        command("xcrun", "stapler", "validate", str(args.archive.resolve()))
        qualifications.update(appStaple="passed", gatekeeperAssessment="passed", archiveStaple="passed")
    else:
        qualifications.update(notarization="not-run", gatekeeperAssessment="not-run")
    source_entries = []
    for directory in ("Sources", "Tests", "Resources", "Tools", "Scripts", "Xcode", "MyDock.xcodeproj"):
        for entry in inventory(root / directory):
            if "__pycache__" not in entry["path"].split("/"):
                source_entries.append({**entry, "path": f"{directory}/{entry['path']}"})
    for name in ("Package.swift", "project.yml", "BuildMyDock.sh", "TestMyDock.sh",
                 "GenerateXcodeProject.sh", "ReleaseMyDock.sh", ".github/workflows/validate.yml"):
        source_entries.append({"path": name, "sha256": sha256(root / name)})
    _, revision = command("git", "-C", str(root), "rev-parse", "HEAD")
    _, status = command("git", "-C", str(root), "status", "--porcelain", "--untracked-files=no")
    toolchain = {}
    for name, arguments in {
        "xcode": ("xcodebuild", "-version"), "swift": ("xcrun", "swift", "--version"),
        "sdkVersion": ("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "sdkBuild": ("xcrun", "--sdk", "macosx", "--show-sdk-build-version"),
    }.items():
        result, value = command(*arguments, required=False)
        toolchain[name] = value if result == 0 else "unavailable"
    bundle_entries = inventory(app)
    manifest = {
        "formatVersion": 1, "recordedAtUTC": datetime.now(timezone.utc).isoformat(),
        "artifactClass": "distribution" if args.qualification == "release" else "xcode-qualification",
        "source": {"revision": revision, "hasTrackedChanges": bool(status),
                   "fingerprintSHA256": fingerprint(source_entries), "files": source_entries},
        "toolchain": toolchain,
        "app": {"name": app.name, "bundleIdentifier": info.get("CFBundleIdentifier"),
                "marketingVersion": info.get("CFBundleShortVersionString"),
                "buildNumber": info.get("CFBundleVersion"), "executableSHA256": sha256(executable),
                "architectures": architectures, "deploymentTargets": deployment_targets,
                "intentMetadataSHA256": fingerprint(inventory(metadata)),
                "signingClass": signing_class, "bundleInventorySHA256": fingerprint(bundle_entries),
                "files": bundle_entries},
        "archive": {"name": args.archive.name, "sha256": sha256(args.archive)},
        "qualification": qualifications,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
