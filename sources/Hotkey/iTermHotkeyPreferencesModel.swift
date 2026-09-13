import Foundation

// Editable hotkey-window preferences, shared by new-profile and existing-profile UI.
@objc(iTermHotkeyPreferencesModel)
@objcMembers
final class iTermHotkeyPreferencesModel: NSObject {
    dynamic var primaryShortcut: iTermShortcut?
    dynamic var hasModifierActivation = false
    dynamic var modifierActivation: iTermHotKeyModifierActivation = .control
    dynamic var autoHide = true
    dynamic var showAutoHiddenWindowOnAppActivation = false
    dynamic var animate = true
    dynamic var floats = false
    dynamic var alternateShortcuts: [iTermShortcut]?
    dynamic var dockPreference: iTermHotKeyDockPreference = .doNotShow

    dynamic var hotKeyAssigned: Bool {
        (primaryShortcut?.isAssigned ?? false) || hasModifierActivation ||
            (alternateShortcuts?.contains { $0.isAssigned } ?? false)
    }

    dynamic var alternateShortcutDictionaries: [[AnyHashable: Any]]? {
        get { alternateShortcuts?.map { $0.dictionaryValue } }
        set { alternateShortcuts = newValue?.compactMap { iTermShortcut(dictionary: $0) } }
    }

    dynamic var dictionaryValue: [String: Any] {
        [KEY_HAS_HOTKEY: hotKeyAssigned,
         KEY_HOTKEY_ACTIVATE_WITH_MODIFIER: hasModifierActivation,
         KEY_HOTKEY_MODIFIER_ACTIVATION: modifierActivation.rawValue,
         KEY_HOTKEY_KEY_CODE: primaryShortcut?.keyCode ?? 0,
         KEY_HOTKEY_CHARACTERS: primaryShortcut?.characters ?? "",
         KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS: primaryShortcut?.charactersIgnoringModifiers ?? "",
         KEY_HOTKEY_MODIFIER_FLAGS: primaryShortcut?.modifiers.rawValue ?? 0,
         KEY_HOTKEY_AUTOHIDE: autoHide,
         KEY_HOTKEY_REOPEN_ON_ACTIVATION: showAutoHiddenWindowOnAppActivation,
         KEY_HOTKEY_ANIMATE: animate,
         KEY_HOTKEY_FLOAT: floats,
         KEY_HOTKEY_DOCK_CLICK_ACTION: dockPreference.rawValue,
         KEY_HOTKEY_ALTERNATE_SHORTCUTS: alternateShortcutDictionaries ?? []]
    }
}
