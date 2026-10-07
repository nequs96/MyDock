"""Static checks that the app's Info.plist has one definition shared by the Xcode and SwiftPM builds."""
from pathlib import Path
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def project_info_properties():
    """Top-level keys and scalar values of the MyDock target's `info.properties` in project.yml.

    Parsed by indentation so the check runs without a YAML package."""
    lines = (ROOT / "project.yml").read_text().splitlines()
    start = next(index for index, line in enumerate(lines) if line == "      path: Xcode/MyDock-Info.plist")
    assert lines[start + 1] == "      properties:", "project.yml info.properties moved"
    properties = {}
    for line in lines[start + 2:]:
        if line.strip() and not line.startswith("        "):
            break
        match = re.fullmatch(r"        ([A-Za-z]+):(?: (.*))?", line)
        if match:
            value = (match.group(2) or "").strip()
            properties[match.group(1)] = value[1:-1] if value[:1] == '"' and value[-1:] == '"' else value
    return properties


class InfoPlistParityTests(unittest.TestCase):
    def setUp(self):
        with (ROOT / "Xcode/MyDock-Info.plist").open("rb") as stream:
            self.plist = plistlib.load(stream)
        self.properties = project_info_properties()

    def test_generated_plist_matches_project_yml(self):
        self.assertIn("NSAppleEventsUsageDescription", self.properties)
        for key, value in self.properties.items():
            self.assertIn(key, self.plist, f"{key} is in project.yml but not Xcode/MyDock-Info.plist; run ./GenerateXcodeProject.sh")
            if isinstance(self.plist[key], str) and value:
                self.assertEqual(self.plist[key], value, f"{key} differs; run ./GenerateXcodeProject.sh")

    def test_every_usage_description_is_declared_in_project_yml(self):
        usage = {key for key in self.plist if key.endswith("UsageDescription")}
        self.assertTrue(usage)
        self.assertEqual(usage, {key for key in self.properties if key.endswith("UsageDescription")})

    def test_build_script_uses_the_generated_plist(self):
        script = (ROOT / "BuildMyDock.sh").read_text()
        self.assertIn("cp Xcode/MyDock-Info.plist", script)
        self.assertNotIn("UsageDescription", script, "BuildMyDock.sh must not define its own Info.plist keys")
        placeholders = set(re.findall(r"\$\(([A-Z_]+)\)", (ROOT / "Xcode/MyDock-Info.plist").read_text()))
        filled = {"DEVELOPMENT_LANGUAGE": "CFBundleDevelopmentRegion", "EXECUTABLE_NAME": "CFBundleExecutable",
                  "PRODUCT_BUNDLE_IDENTIFIER": "CFBundleIdentifier", "PRODUCT_NAME": "CFBundleName",
                  "MARKETING_VERSION": "CFBundleShortVersionString", "CURRENT_PROJECT_VERSION": "CFBundleVersion"}
        self.assertLessEqual(placeholders, set(filled), "BuildMyDock.sh does not fill in a new build setting")
        for key in set(filled.values()) | {"CFBundleDisplayName"}:
            self.assertIn(f"plutil -replace {key} ", script)


if __name__ == "__main__":
    unittest.main()
