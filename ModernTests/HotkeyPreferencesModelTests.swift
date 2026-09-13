import XCTest
@testable import iTerm2SharedARC

final class HotkeyPreferencesModelTests: XCTestCase {
    private func shortcut(keyCode: UInt = 0,
                          characters: String? = "",
                          ignoringModifiers: String? = "") -> iTermShortcut {
        let shortcut = iTermShortcut()
        shortcut.keyCode = keyCode
        shortcut.characters = characters
        shortcut.charactersIgnoringModifiers = ignoringModifiers
        return shortcut
    }

    func testNewProfileDefaultsAndSerializedKeysRemainUnchanged() {
        let model = iTermHotkeyPreferencesModel()
        XCTAssertNil(model.primaryShortcut)
        XCTAssertNil(model.alternateShortcuts)
        XCTAssertNil(model.alternateShortcutDictionaries)
        let expected: [String: Any] = [
            "Has Hotkey": false,
            "HotKey Activated By Modifier": false,
            "HotKey Modifier Activation": 0,
            "HotKey Key Code": 0,
            "HotKey Characters": "",
            "HotKey Characters Ignoring Modifiers": "",
            "HotKey Modifier Flags": 0,
            "HotKey Window AutoHides": true,
            "HotKey Window Reopens On Activation": false,
            "HotKey Window Animates": true,
            "HotKey Window Floats": false,
            "HotKey Window Dock Click Action": 0,
            "HotKey Alternate Shortcuts": []
        ]
        XCTAssertEqual(model.dictionaryValue as NSDictionary, expected as NSDictionary)
    }

    func testPrimaryShortcutAssignmentIncludesDeadKeysAndKeyCodeOnlyShortcuts() {
        let model = iTermHotkeyPreferencesModel()
        for shortcut in [shortcut(characters: "´"),
                         shortcut(ignoringModifiers: "a"),
                         shortcut(keyCode: 122)] {
            model.primaryShortcut = shortcut
            XCTAssertTrue(model.hotKeyAssigned)
        }
        model.primaryShortcut = shortcut()
        model.primaryShortcut?.hasKeyCode = true
        XCTAssertFalse(model.hotKeyAssigned)
        model.primaryShortcut = nil
        XCTAssertFalse(model.hotKeyAssigned)
    }

    func testModifierOnlyActivationIsAssigned() {
        let model = iTermHotkeyPreferencesModel()
        model.hasModifierActivation = true
        model.modifierActivation = .command
        XCTAssertTrue(model.hotKeyAssigned)
        XCTAssertEqual(model.dictionaryValue[KEY_HOTKEY_MODIFIER_ACTIVATION] as? UInt, 3)
        model.hasModifierActivation = false
        XCTAssertFalse(model.hotKeyAssigned)
    }

    func testAlternateShortcutsCanAssignHotkeyWithoutPrimary() {
        let model = iTermHotkeyPreferencesModel()
        for alternate in [shortcut(characters: "´"),
                          shortcut(ignoringModifiers: "a"),
                          shortcut(keyCode: 122)] {
            model.alternateShortcuts = [shortcut(), alternate]
            XCTAssertTrue(model.hotKeyAssigned)
        }
        model.alternateShortcuts = [shortcut()]
        XCTAssertFalse(model.hotKeyAssigned)
        model.alternateShortcuts = []
        XCTAssertFalse(model.hotKeyAssigned)
    }

    func testConfiguredProfileSerializesWindowOptionsAndShortcut() {
        let model = iTermHotkeyPreferencesModel()
        let primary = shortcut(keyCode: 12, characters: "Q", ignoringModifiers: "q")
        primary.modifiers = [.command, .shift]
        model.primaryShortcut = primary
        model.autoHide = false
        model.animate = false
        model.floats = true
        model.showAutoHiddenWindowOnAppActivation = true
        model.dockPreference = .showIfNoOtherWindowsOpen
        let values = model.dictionaryValue
        XCTAssertEqual(values[KEY_HAS_HOTKEY] as? Bool, true)
        XCTAssertEqual(values[KEY_HOTKEY_KEY_CODE] as? UInt, 12)
        XCTAssertEqual(values[KEY_HOTKEY_CHARACTERS] as? String, "Q")
        XCTAssertEqual(values[KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS] as? String, "q")
        XCTAssertEqual(values[KEY_HOTKEY_MODIFIER_FLAGS] as? UInt, primary.modifiers.rawValue)
        XCTAssertEqual(values[KEY_HOTKEY_AUTOHIDE] as? Bool, false)
        XCTAssertEqual(values[KEY_HOTKEY_ANIMATE] as? Bool, false)
        XCTAssertEqual(values[KEY_HOTKEY_FLOAT] as? Bool, true)
        XCTAssertEqual(values[KEY_HOTKEY_REOPEN_ON_ACTIVATION] as? Bool, true)
        XCTAssertEqual(values[KEY_HOTKEY_DOCK_CLICK_ACTION] as? UInt, 2)
    }

    func testNilShortcutCharactersSerializeAsEmptyStrings() {
        let model = iTermHotkeyPreferencesModel()
        model.primaryShortcut = shortcut(characters: nil, ignoringModifiers: nil)
        XCTAssertFalse(model.hotKeyAssigned)
        XCTAssertEqual(model.dictionaryValue[KEY_HOTKEY_CHARACTERS] as? String, "")
        XCTAssertEqual(model.dictionaryValue[KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS] as? String, "")
    }

    func testAlternateDictionaryConversionPreservesOrderAndSkipsEmptyEntries() throws {
        let model = iTermHotkeyPreferencesModel()
        let first = shortcut(keyCode: 12, characters: "q", ignoringModifiers: "q")
        let second = shortcut(keyCode: 13, characters: "w", ignoringModifiers: "w")
        second.modifiers = .option
        let expected = [first.dictionaryValue!, second.dictionaryValue!]
        model.alternateShortcutDictionaries = [[:], expected[0], [:], expected[1]]
        let alternates = try XCTUnwrap(model.alternateShortcuts)
        XCTAssertEqual(alternates.map { $0.keyCode }, [12, 13])
        XCTAssertEqual(try XCTUnwrap(model.alternateShortcutDictionaries) as NSArray, expected as NSArray)
        XCTAssertEqual(model.dictionaryValue[KEY_HOTKEY_ALTERNATE_SHORTCUTS] as? NSArray, expected as NSArray)
        XCTAssertTrue(model.hotKeyAssigned)
    }

    func testClearingAlternateDictionariesPreservesNilAndEmptyDistinction() {
        let model = iTermHotkeyPreferencesModel()
        model.alternateShortcuts = [shortcut(keyCode: 122)]
        model.alternateShortcutDictionaries = nil
        XCTAssertNil(model.alternateShortcuts)
        XCTAssertNil(model.alternateShortcutDictionaries)
        XCTAssertFalse(model.hotKeyAssigned)
        model.alternateShortcutDictionaries = []
        XCTAssertEqual(model.alternateShortcuts?.count, 0)
        XCTAssertEqual(model.alternateShortcutDictionaries?.count, 0)
    }

    func testShortcutEditsAreReflectedInSubsequentSerialization() {
        let model = iTermHotkeyPreferencesModel()
        let alternate = shortcut()
        model.alternateShortcuts = [alternate]
        XCTAssertFalse(model.hotKeyAssigned)
        alternate.keyCode = 122
        XCTAssertTrue(model.hotKeyAssigned)
        XCTAssertEqual(model.alternateShortcutDictionaries?.first?["keyCode"] as? UInt, 122)
    }

    func testModelReleasesOwnedShortcuts() {
        weak var primary: iTermShortcut?
        weak var alternate: iTermShortcut?
        autoreleasepool {
            let model = iTermHotkeyPreferencesModel()
            model.primaryShortcut = shortcut(keyCode: 12)
            model.alternateShortcuts = [shortcut(keyCode: 13)]
            primary = model.primaryShortcut
            alternate = model.alternateShortcuts?.first
            XCTAssertNotNil(primary)
            XCTAssertNotNil(alternate)
        }
        XCTAssertNil(primary)
        XCTAssertNil(alternate)
    }

    func testObjectiveCRuntimeKVCAndObservationRemainAvailable() {
        XCTAssertTrue(NSClassFromString("iTermHotkeyPreferencesModel") === iTermHotkeyPreferencesModel.self)
        let model = iTermHotkeyPreferencesModel()
        var observed: [Bool] = []
        let observation = model.observe(\.autoHide, options: [.new]) { _, change in
            if let value = change.newValue { observed.append(value) }
        }
        model.setValue(false, forKey: "autoHide")
        XCTAssertEqual(observed, [false])
        XCTAssertEqual(model.value(forKey: "autoHide") as? Bool, false)
        model.setValue(true, forKey: "hasModifierActivation")
        XCTAssertEqual(model.value(forKey: "hotKeyAssigned") as? Bool, true)
        observation.invalidate()
    }
}
