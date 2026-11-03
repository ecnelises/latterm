"""Validate Chinese translation resources without starting the app.

Run with: python3 tests/settings_localization_test.py
"""
import collections
import json
from pathlib import Path
import plistlib
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

    def test_all_expert_setting_descriptions_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        source = (ROOT / "sources/Settings/iTermAdvancedSettingsModel.m").read_text()
        source = source.split("#pragma mark Tabs", 1)[1]
        definitions = re.findall(r'^DEFINE_\w+\(\w+,[\s\S]*?(?=^DEFINE_|^#|^\+|\Z)', source, re.M)
        self.assertGreater(len(definitions), 400)
        for definition in definitions:
            match = re.search(r'SECTION_\w+\s*((?:@?"(?:[^"\\]|\\.)*"\s*)+)\);?', definition)
            self.assertIsNotNone(match, definition)
            literals = match.group(1)
            description = "".join(json.loads(value) for value in re.findall(r'"(?:[^"\\]|\\.)*"', literals))
            self.assertIn(description, localized)
            self.assertNotEqual(localized[description], description)
            if re.match(r'DEFINE_(?:COMPUTED_)?INT_ENUM\(', definition):
                for literal in re.findall(r'@("(?:[^"\\]|\\.)*")', definition[:match.start()]):
                    self.assertIn(json.loads(literal), localized)
        for category in re.findall(r'^#define SECTION_\w+ @"(.*): "', source, re.M):
            self.assertIn(category, localized)

    def test_settings_nib_translations_reference_existing_objects(self):
        for name in ("PreferencePanel", "SpecialExceptionsWindowController", "iTermEditSnippetWindowController",
                     "iTermEditKeyActionWindowController"):
            root = ET.parse(ROOT / "sources/Settings" / f"{name}.xib").getroot()
            identifiers = {node.get("id") for node in root.iter()}
            for key in strings(ROOT / "zh-Hans.lproj" / f"{name}.strings"):
                self.assertIn(key.split(".")[0], identifiers, f"{name}: {key}")

    def test_all_main_menu_titles_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/MainMenu.strings")
        root = ET.parse(ROOT / "sources/MainMenu/MainMenu.xib").getroot()
        titles = {f'{node.get("id")}.title': node.get("title")
                  for node in root.iter() if node.get("title")}
        self.assertEqual(set(localized), set(titles))
        unchanged = {"Latterm", "tmux", "ssh", "VT100", "VT200", "VT300", "VT400", "VT500"}
        for key, title in titles.items():
            if title not in unchanged:
                self.assertNotEqual(localized[key], title, key)

    def test_runtime_menu_and_about_translations(self):
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        for name in ("AppKit/iTermApplicationDelegate.m",
                     "AboutWindow/iTermAboutWindowController.m",
                     "ContextMenu/iTermTextViewContextMenuHelper.m",
                     "Settings/Profiles/iTermProfilesMenuController.m",
                     "Toolbelt/ToolProfiles.m", "Toolbelt/ToolNotes.m",
                     "TerminalView/PseudoTerminal.m", "iTermController/iTermController.m"):
            source = (ROOT / "sources" / name).read_text()
            self.assertNotRegex(source, r'NSLocalizedStringFromTableInBundle\([^,]+,\s*@"iTerm"', name)
            keys = re.findall(r'NSLocalizedString\(@("(?:[^"\\]|\\.)*")', source)
            if "ContextMenu" in name:
                # Built-in helper/dictionary/terminal-state titles use dynamic lookups.
                keys += re.findall(r'\badd\(@("(?:[^"\\]|\\.)*")', source)
                keys += re.findall(r'@"title": @("(?:[^"\\]|\\.)*")', source)
                keys += re.findall(r'\{ @("(?:[^"\\]|\\.)*"), @selector', source)
            for literal in keys:
                key = json.loads(literal)
                if key in {"VT100", "VT200", "VT300", "VT400", "VT500"}:
                    continue
                self.assertTrue(key in localized, f"{name}: missing {key}")
        toolbelt = (ROOT / "sources/Toolbelt/iTermToolbeltView.m").read_text()
        for key in re.findall(r'k\w+ToolName = @"([^"]+)"', toolbelt):
            self.assertIn(key, localized)

    def test_about_nib_and_sponsors_heading_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/AboutWindow.strings")
        root = ET.parse(ROOT / "sources/AboutWindow/AboutWindow.xib").getroot()
        for node in root.iter("textFieldCell"):
            if node.get("title"):
                self.assertIn(f'{node.get("id")}.title', localized)
        heading = root.find('.//textView[@id="XqE-kC-hnW"]/attributedString')
        content = "".join(fragment.get("content") or fragment.find("string").text
                          for fragment in heading.findall("fragment"))
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        self.assertIn(content, localized)
        self.assertEqual(re.findall(r'href="[^"]+"', content),
                         re.findall(r'href="[^"]+"', localized[content]))

    def test_permission_prompts_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/InfoPlist.strings")
        for name in ("dev", "release", "beta", "nightly"):
            with (ROOT / "plists" / f"{name}-iTerm2.plist").open("rb") as file:
                info = plistlib.load(file)
            for key, value in info.items():
                if key.endswith("UsageDescription"):
                    self.assertIn(key, localized, name)
                    self.assertNotEqual(localized[key], value)

    def test_main_menu_packaging_does_not_shadow_localized_nibs(self):
        project = strings(ROOT / "iTerm2.xcodeproj/project.pbxproj")["objects"]
        target = next(obj for obj in project.values()
                      if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "iTerm2")
        phases = [project[key] for key in target["buildPhases"]]
        resources = next(phase for phase in phases if phase["isa"] == "PBXResourcesBuildPhase")
        for key in resources["files"]:
            reference = project[project[key]["fileRef"]]
            self.assertNotEqual(reference.get("path"), "MainMenu.xib")
        localization = next(phase for phase in phases
                            if phase.get("name") == "Copy zh-Hans localization")
        for language in ("en", "zh-Hans"):
            for name in ("MainMenu", "AboutWindow"):
                suffix = f"/{language}.lproj/{name}.nib"
                self.assertTrue(any(path.endswith(suffix) for path in localization["outputPaths"]))
        # Localized editor windows need both an English and a Chinese nib.
        for name in ("iTermEditSnippetWindowController", "iTermEditKeyActionWindowController"):
            for language in ("en", "zh-Hans"):
                suffix = f"/{language}.lproj/{name}.nib"
                self.assertTrue(any(path.endswith(suffix) for path in localization["outputPaths"]), suffix)
            self.assertIn(f'--strings-file "${{SRCROOT}}/zh-Hans.lproj/{name}.strings"', localization["shellScript"])
        # Remove the stale root resource on incremental builds as well.
        self.assertIn('rm -rf "${resources_root}/MainMenu.nib"', localization["shellScript"])

    def test_editor_labels_and_validation_messages_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        for name in ("iTermKeyMappingViewController.m", "iTermEditSnippetWindowController.m",
                     "iTermActionsEditingViewController.m", "iTermSnippetsEditingViewController.m",
                     "SpecialExceptionsWindowController.swift", "SettingsSidebarView.swift",
                     "ProfilesGeneralPreferencesViewController.m", "SettingsPage.swift",
                     "SettingsProfilesView.swift", "GeneralPreferencesViewController.m",
                     "SettingsFormView.swift", "ArrangementPreviewView.m", "PointerPrefsController.m",
                     "../Workgroups/iTermWorkgroupDetailViewController.swift",
                     "iTermAdvancedSettingsViewController.m",
                     "SettingDefinition.swift", "ProfileSettingsInspector.swift",
                     "iTermProfilePreferences.m", "ProfilePreferencesViewController.m",
                     "../OpenQuickly/iTermOpenQuicklyCommands.m",
                     "../OpenQuickly/iTermOpenQuicklyModel.m",
                     "iTermPreferencesSearchEngineResultsWindowController.m",
                     "ProfilesWindowPreferencesViewController.m",
                     "ProfilesColorsPreferencesViewController.m", "iTermColorPresets.m",
                     "WindowArrangements.m", "KeysPreferencesViewController.m",
                     "iTermRemotePreferences.m", "iTermEditKeyActionWindowController.m",
                     "../Keyboard/iTermKeyBindingAction.m"):
            source = (ROOT / "sources/Settings" / name).read_text()
            for key in re.findall(r'NSLocalizedString\(@?"((?:[^"\\]|\\.)*)"', source):
                key = json.loads('"' + key + '"')
                self.assertTrue(key in localized, f"{name}: missing {key}")

    def test_workgroup_editor_and_toolbar_strings_are_translated(self):
        localized = strings(ROOT / "zh-Hans.lproj/Localizable.strings")
        paths = sorted((ROOT / "sources/Workgroups").glob("*.swift"))
        paths.append(ROOT / "sources/iTermSessionToolbarView.swift")
        for path in paths:
            source = path.read_text()
            for key in re.findall(r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"', source):
                key = json.loads('"' + key + '"')
                self.assertTrue(key in localized, f"{path.name}: missing {key}")
        # Settings labels in the Workgroups editor must not bypass lookup.
        for name in ("iTermWorkgroupsEditingViewController.swift",
                     "iTermWorkgroupDetailViewController.swift",
                     "iTermWorkgroupSessionDetailViewController.swift"):
            source = (ROOT / "sources/Workgroups" / name).read_text()
            self.assertNotRegex(source, r'labelWithString: "[A-Z]', name)
            self.assertNotRegex(source, r'(?:title|labelText|placeholderString): "[A-Z]', name)
            self.assertNotRegex(source, r'actionName: "[A-Z]', name)


if __name__ == "__main__":
    unittest.main()
