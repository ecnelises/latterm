"""Validate Settings translation resources without starting the app.

Run with: python3 tests/settings_localization_test.py
"""
import collections
import json
from pathlib import Path
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def strings(path):
    return json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(path)
    ]))


class SettingsLocalizationTests(unittest.TestCase):
    def test_strings_have_no_duplicate_keys_or_changed_format_arguments(self):
        for path in (ROOT / "zh-Hans.lproj").glob("*.strings"):
            with self.subTest(resource=path.name):
                keys = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', path.read_text(), re.M)
                self.assertEqual(len(keys), len(set(keys)))
                for key, value in strings(path).items():
                    if path.name != "Localizable.strings":
                        continue
                    # Ignore literal percentages and compare formatter types.
                    pattern = r'%(?:\d+\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(?:ll|l|z)?[@diufgGs]'
                    original = collections.Counter(re.findall(pattern, key))
                    translated = collections.Counter(re.findall(pattern, value))
                    self.assertEqual(original, translated, key)

    def test_settings_nib_translations_reference_existing_objects(self):
        for name in ("PreferencePanel", "SpecialExceptionsWindowController", "iTermEditSnippetWindowController"):
            root = ET.parse(ROOT / "sources/Settings" / f"{name}.xib").getroot()
            identifiers = {node.get("id") for node in root.iter()}
            for key in strings(ROOT / "zh-Hans.lproj" / f"{name}.strings"):
                self.assertIn(key.split(".")[0], identifiers, f"{name}: {key}")

    def test_editor_labels_and_validation_messages_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        for name in ("iTermKeyMappingViewController.m", "iTermEditSnippetWindowController.m",
                     "iTermActionsEditingViewController.m", "iTermSnippetsEditingViewController.m",
                     "SpecialExceptionsWindowController.swift", "SettingsSidebarView.swift",
                     "ProfilesGeneralPreferencesViewController.m", "SettingsPage.swift",
                     "SettingsProfilesView.swift", "GeneralPreferencesViewController.m",
                     "iTermPreferencesSearchEngineResultsWindowController.m"):
            source = (ROOT / "sources/Settings" / name).read_text()
            for key in re.findall(r'NSLocalizedString\(@?"((?:[^"\\]|\\.)*)"', source):
                key = json.loads('"' + key + '"')
                self.assertTrue(key in localized, f"{name}: missing {key}")


if __name__ == "__main__":
    unittest.main()
