"""Static check that the README's widget table lists exactly the families in WidgetRegistry.all."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def registry_families():
    source = (ROOT / "Sources/MyDock/Models/DockModels.swift").read_text()
    titles = dict(re.findall(r'case (\w+) = "([^"]+)"', source[source.index("enum WidgetCategory"):source.index("struct WidgetDefinition")]))
    start = source.index("static let all: [WidgetDefinition] = [")
    block = source[start:source.index("\n    ]", start)]
    entries = re.findall(r'\.init\(name: "([^"]+)", symbol: [^,]+, category: \.(\w+)', block)
    assert len(entries) == block.count(".init(name:"), "WidgetRegistry.all changed shape; update this parser"
    families = {}
    for name, category in entries:
        families.setdefault(titles[category], set()).add(name)
    return families


def readme_families():
    text = (ROOT / "README.md").read_text()
    section = text[text.index("### Widgets"):]
    section = section[:section.index("\n### ", 1)]
    families = {}
    for category, names in re.findall(r"^\| ([^|]+?) \| ([^|]+?) \|$", section, re.M):
        if category in ("Category", "---"):
            continue
        families[category] = {name.strip() for name in names.split(",")}
    return families


class ReadmeWidgetTableTests(unittest.TestCase):
    def test_readme_table_matches_registry(self):
        registry = registry_families()
        self.assertGreater(sum(len(names) for names in registry.values()), 30)
        self.assertEqual(readme_families(), registry)


if __name__ == "__main__":
    unittest.main()
