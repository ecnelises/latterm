//
//  DeclarativeConfig.swift
//  Latterm
//

import AppKit
import Carbon.HIToolbox
import CryptoKit
import Foundation

enum DeclarativeConfigError: LocalizedError {
    case invalidValue(field: String, message: String)
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidValue(field, message):
            return String(
                format: NSLocalizedString("Invalid value for ‘%@’: %@",
                                          comment: "Declarative config validation error"),
                field,
                message
            )
        case let .ioError(message):
            return message
        }
    }
}

/// Manages Latterm's Git-friendly declarative TOML configuration (`~/.config/latterm/config.toml`),
/// including bidirectional import/export and `DispatchSource` live hot-reloading.
@objc(iTermDeclarativeConfigManager)
final class DeclarativeConfigManager: NSObject {
    @objc static let didChangeNotificationName = "iTermDeclarativeConfigDidChangeNotification"
    static let didChangeNotification = Notification.Name(didChangeNotificationName)

    @objc static let shared = DeclarativeConfigManager()

    let configURL: URL
    private let debounceInterval: TimeInterval
    private var directoryFD: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileFD: Int32 = -1
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var suppressReloadUntil: Date = .distantPast
    private var isWatching = false

    private(set) var lastLoadedAt: Date?
    private(set) var lastErrorMessage: String?

    @objc override convenience init() {
        self.init(configURL: Self.defaultConfigURL(), debounceInterval: 0.15)
    }

    init(configURL: URL, debounceInterval: TimeInterval = 0.15) {
        self.configURL = configURL
        self.debounceInterval = debounceInterval
        super.init()
    }

    deinit {
        stopWatching()
    }

    // MARK: - Paths & Status

    static func defaultConfigURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["LATTERM_CONFIG_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            let expanded = (explicit as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        let baseConfigDir: String
        if let xdg = environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xdg.isEmpty {
            baseConfigDir = (xdg as NSString).expandingTildeInPath
        } else {
            baseConfigDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        }
        let appFolderName: String
        if let suite = iTermUserDefaults.customSuiteName(), !suite.isEmpty {
            appFolderName = "latterm-\(suite)"
        } else {
            appFolderName = "latterm"
        }
        return URL(fileURLWithPath: baseConfigDir, isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
    }

    @objc var configFilePath: String {
        configURL.path
    }

    @objc var abbreviatedConfigFilePath: String {
        (configURL.path as NSString).abbreviatingWithTildeInPath
    }

    @objc var configFileExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    @objc var statusDescription: String {
        if let lastErrorMessage {
            return String(
                format: NSLocalizedString("Error: %@", comment: "Declarative config error status"),
                lastErrorMessage
            )
        }
        if configFileExists {
            if isWatching {
                return NSLocalizedString("Loaded · Live reload active",
                                         comment: "Declarative config loaded status")
            }
            return NSLocalizedString("Configuration file ready",
                                     comment: "Declarative config ready status")
        }
        return NSLocalizedString("Not created yet — click “Export Current Settings” or “Open Config File” to begin.",
                                 comment: "Declarative config missing status")
    }

    // MARK: - Lifecycle & Hot Reload

    @objc func startIfAppropriate() {
        guard NSClassFromString("XCTestCase") == nil else {
            return
        }
        if configFileExists {
            do {
                try reloadConfig()
            } catch {
                RLog("Failed to load config.toml at startup: \(error.localizedDescription)")
            }
        }
        startWatching()
    }

    func startWatching() {
        stopWatching()
        let directoryURL = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            DLog("Unable to create config directory \(directoryURL.path): \(error)")
            return
        }

        let dirFD = open(directoryURL.path, O_EVTONLY)
        guard dirFD >= 0 else {
            DLog("Unable to open config directory for watching: \(directoryURL.path)")
            return
        }
        directoryFD = dirFD
        let dirSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        dirSource.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        dirSource.setCancelHandler {
            close(dirFD)
        }
        directorySource = dirSource
        dirSource.resume()

        attachFileSourceIfPresent()
        isWatching = true
        postStatusDidChange()
    }

    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let fileSource {
            fileSource.cancel()
            self.fileSource = nil
            fileFD = -1
        }
        if let directorySource {
            directorySource.cancel()
            self.directorySource = nil
            directoryFD = -1
        }
        isWatching = false
    }

    private func attachFileSourceIfPresent() {
        if let fileSource {
            fileSource.cancel()
            self.fileSource = nil
            fileFD = -1
        }
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return
        }
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        fileFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.rename) || flags.contains(.delete) {
                self.attachFileSourceIfPresent()
            }
            self.scheduleDebouncedReload()
        }
        source.setCancelHandler {
            close(fd)
        }
        fileSource = source
        source.resume()
    }

    private func handleFileSystemEvent() {
        attachFileSourceIfPresent()
        scheduleDebouncedReload()
    }

    private func scheduleDebouncedReload() {
        if Date() < suppressReloadUntil {
            return
        }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if Date() < self.suppressReloadUntil {
                return
            }
            if self.configFileExists {
                do {
                    try self.reloadConfig()
                } catch {
                    RLog("Live reload of config.toml failed: \(error.localizedDescription)")
                }
            } else {
                self.lastErrorMessage = nil
                self.postStatusDidChange()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    // MARK: - Objective-C Actions

    @objc(reloadReturningError:)
    func reloadObjC() throws {
        try reloadConfig()
    }

    @objc(exportCurrentSettingsReturningError:)
    func exportCurrentSettingsObjC() throws {
        try exportCurrentSettings()
    }

    @objc(openConfigFileInEditorReturningError:)
    func openConfigFileInEditorObjC() throws {
        if !configFileExists {
            try exportCurrentSettings()
        }
        NSWorkspace.shared.open(configURL)
    }

    @objc func revealConfigFileInFinder() {
        if configFileExists {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            let parentURL = configURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(parentURL)
        }
    }

    // MARK: - Load & Export

    func reloadConfig() throws {
        guard configFileExists else {
            lastErrorMessage = nil
            postStatusDidChange()
            return
        }
        do {
            let contents = try String(contentsOf: configURL, encoding: .utf8)
            try applyTOMLString(contents)
            lastLoadedAt = Date()
            lastErrorMessage = nil
            postStatusDidChange()
        } catch {
            lastErrorMessage = error.localizedDescription
            postStatusDidChange()
            throw error
        }
    }

    func exportCurrentSettings() throws {
        let rendered = renderCurrentSettingsTOML()
        let directoryURL = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        suppressReloadUntil = Date().addingTimeInterval(max(0.4, debounceInterval * 3))
        try rendered.write(to: configURL, atomically: true, encoding: .utf8)
        if isWatching {
            attachFileSourceIfPresent()
        }
        lastLoadedAt = Date()
        lastErrorMessage = nil
        postStatusDidChange()
    }

    func applyTOMLString(_ source: String,
                         profileModel: ProfileModel? = nil) throws {
        let root = try TOMLCodec.parse(source)
        let targetModel = profileModel ?? ProfileModel.sharedInstance()
        guard let targetModel else {
            it_fatalError("ProfileModel.sharedInstance() must be available")
        }

        var changedPrefKeys: [String] = []
        if let appearance = root.table("appearance") {
            try Self.applyAppearance(appearance, changedKeys: &changedPrefKeys)
        }
        if let behavior = root.table("behavior") {
            try Self.applyBehavior(behavior, changedKeys: &changedPrefKeys)
        }
        if root.contains("keybindings") {
            guard let bindings = root.tableArray("keybindings") else {
                throw DeclarativeConfigError.invalidValue(
                    field: "keybindings",
                    message: "Expected an array of tables ([[keybindings]])"
                )
            }
            try Self.applyKeybindings(bindings)
        }
        if root.contains("profiles") {
            guard let profiles = root.tableArray("profiles") else {
                throw DeclarativeConfigError.invalidValue(
                    field: "profiles",
                    message: "Expected an array of tables ([[profiles]])"
                )
            }
            try Self.applyProfiles(profiles, to: targetModel)
        }

        for key in changedPrefKeys {
            NotificationCenter.default.post(
                name: Notification.Name(rawValue: kPreferenceDidChangeFromOtherPanel),
                object: nil,
                userInfo: [kPreferenceDidChangeFromOtherPanelKeyUserInfoKey: key]
            )
        }
        if !changedPrefKeys.isEmpty {
            NotificationCenter.default.post(
                name: .iTermMetalSettingsDidChange,
                object: nil
            )
        }
        NotificationCenter.default.post(
            name: Notification.Name(rawValue: "kRefreshTerminalNotification"),
            object: nil
        )
    }

    func renderCurrentSettingsTOML(profileModel: ProfileModel? = nil) -> String {
        let model = profileModel ?? ProfileModel.sharedInstance()
        var root = TOMLTable()
        root["appearance"] = .table(Self.exportAppearance())
        root["behavior"] = .table(Self.exportBehavior())

        let exportedBindings = Self.exportKeybindings()
        if !exportedBindings.isEmpty {
            root["keybindings"] = .array(exportedBindings.map { .table($0) })
        }

        if let model {
            let exportedProfiles = Self.exportProfiles(from: model)
            if !exportedProfiles.isEmpty {
                root["profiles"] = .array(exportedProfiles.map { .table($0) })
            }
        }

        let header = """
        Latterm Declarative Configuration (config.toml)
        Changes saved to this file are hot-reloaded automatically while Latterm is running.
        Colors use #rrggbb or #rrggbbaa hex notation. Comments (#) are supported everywhere.
        """
        return TOMLCodec.encode(root, headerComment: header)
    }

    private func postStatusDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - [appearance]

    private static func setPref(_ object: Any, forKey key: String, changedKeys: inout [String]) {
        iTermPreferences.setObject(object, forKey: key)
        changedKeys.append(key)
    }

    private static func applyAppearance(_ table: TOMLTable, changedKeys: inout [String]) throws {
        if let theme = table.string("theme") {
            let raw: Int32
            switch theme.lowercased() {
            case "automatic", "system": raw = iTermPreferencesTabStyle.TAB_STYLE_AUTOMATIC.rawValue
            case "minimal": raw = iTermPreferencesTabStyle.TAB_STYLE_MINIMAL.rawValue
            case "compact": raw = iTermPreferencesTabStyle.TAB_STYLE_COMPACT.rawValue
            case "light": raw = iTermPreferencesTabStyle.TAB_STYLE_LIGHT.rawValue
            case "dark": raw = iTermPreferencesTabStyle.TAB_STYLE_DARK.rawValue
            case "light_high_contrast": raw = iTermPreferencesTabStyle.TAB_STYLE_LIGHT_HIGH_CONTRAST.rawValue
            case "dark_high_contrast": raw = iTermPreferencesTabStyle.TAB_STYLE_DARK_HIGH_CONTRAST.rawValue
            default:
                throw DeclarativeConfigError.invalidValue(
                    field: "appearance.theme",
                    message: "Expected automatic, minimal, compact, light, dark, light_high_contrast, or dark_high_contrast"
                )
            }
            setPref(NSNumber(value: raw), forKey: kPreferenceKeyTabStyle, changedKeys: &changedKeys)
        }
        if let tabLoc = table.string("tab_bar_location") {
            let pos: Int32
            switch tabLoc.lowercased() {
            case "top": pos = PSMTabPosition.topTab.rawValue
            case "bottom": pos = PSMTabPosition.bottomTab.rawValue
            case "left": pos = PSMTabPosition.leftTab.rawValue
            default:
                throw DeclarativeConfigError.invalidValue(
                    field: "appearance.tab_bar_location",
                    message: "Expected top, bottom, or left"
                )
            }
            setPref(NSNumber(value: pos), forKey: kPreferenceKeyTabPosition, changedKeys: &changedKeys)
        }
        if let statusLoc = table.string("status_bar_location") {
            let pos: UInt
            switch statusLoc.lowercased() {
            case "top": pos = iTermStatusBarPosition.top.rawValue
            case "bottom": pos = iTermStatusBarPosition.bottom.rawValue
            default:
                throw DeclarativeConfigError.invalidValue(
                    field: "appearance.status_bar_location",
                    message: "Expected top or bottom"
                )
            }
            setPref(NSNumber(value: pos), forKey: kPreferenceKeyStatusBarPosition, changedKeys: &changedKeys)
        }
        if let alwaysShowTabs = table.bool("always_show_tab_bar") {
            setPref(NSNumber(value: !alwaysShowTabs), forKey: kPreferenceKeyHideTabBar, changedKeys: &changedKeys)
        }
        if let showTabNumbers = table.bool("show_tab_numbers") {
            setPref(NSNumber(value: !showTabNumbers), forKey: kPreferenceKeyHideTabNumber, changedKeys: &changedKeys)
        }
        if let showClose = table.bool("show_tab_close_buttons") {
            setPref(NSNumber(value: showClose), forKey: kPreferenceKeyTabsHaveCloseButton, changedKeys: &changedKeys)
        }
        if let stretchTabs = table.bool("stretch_tabs") {
            setPref(NSNumber(value: stretchTabs), forKey: kPreferenceKeyStretchTabsToFillBar, changedKeys: &changedKeys)
        }
        if let hideScrollbars = table.bool("hide_scrollbars") {
            setPref(NSNumber(value: hideScrollbars), forKey: kPreferenceKeyHideScrollbar, changedKeys: &changedKeys)
        }
        if let showPaneTitles = table.bool("show_pane_titles") {
            setPref(NSNumber(value: showPaneTitles), forKey: kPreferenceKeyShowPaneTitles, changedKeys: &changedKeys)
        }
        if let showBorder = table.bool("show_window_border") {
            setPref(NSNumber(value: showBorder), forKey: kPreferenceKeyShowWindowBorder, changedKeys: &changedKeys)
        }
        if let sideMargins = table.int("side_margins") {
            setPref(NSNumber(value: max(0, min(200, sideMargins))), forKey: kPreferenceKeySideMargins, changedKeys: &changedKeys)
        }
        if let verticalMargins = table.int("top_bottom_margins") {
            setPref(NSNumber(value: max(0, min(200, verticalMargins))), forKey: kPreferenceKeyTopBottomMargins, changedKeys: &changedKeys)
        }
        if let dimAmount = table.double("dim_amount") {
            setPref(NSNumber(value: max(0.0, min(1.0, dimAmount))), forKey: kPreferenceKeyDimmingAmount, changedKeys: &changedKeys)
        }
        if let dimPanes = table.bool("dim_inactive_panes") {
            setPref(NSNumber(value: dimPanes), forKey: kPreferenceKeyDimInactiveSplitPanes, changedKeys: &changedKeys)
        }
        if let dimBgWindows = table.bool("dim_background_windows") {
            setPref(NSNumber(value: dimBgWindows), forKey: kPreferenceKeyDimBackgroundWindows, changedKeys: &changedKeys)
        }
        if let dimTextOnly = table.bool("dim_text_only") {
            setPref(NSNumber(value: dimTextOnly), forKey: kPreferenceKeyDimOnlyText, changedKeys: &changedKeys)
        }
    }

    private static func exportAppearance() -> TOMLTable {
        var table = TOMLTable()
        let rawTheme = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        let themeName: String
        switch iTermPreferencesTabStyle(rawValue: rawTheme) {
        case .TAB_STYLE_LIGHT: themeName = "light"
        case .TAB_STYLE_DARK: themeName = "dark"
        case .TAB_STYLE_LIGHT_HIGH_CONTRAST: themeName = "light_high_contrast"
        case .TAB_STYLE_DARK_HIGH_CONTRAST: themeName = "dark_high_contrast"
        case .TAB_STYLE_MINIMAL: themeName = "minimal"
        case .TAB_STYLE_COMPACT: themeName = "compact"
        default: themeName = "automatic"
        }
        table["theme"] = .string(themeName)

        let rawTabPos = iTermPreferences.int(forKey: kPreferenceKeyTabPosition)
        let tabLocation: String
        if rawTabPos == PSMTabPosition.bottomTab.rawValue {
            tabLocation = "bottom"
        } else if rawTabPos == PSMTabPosition.leftTab.rawValue {
            tabLocation = "left"
        } else {
            tabLocation = "top"
        }
        table["tab_bar_location"] = .string(tabLocation)

        let rawStatusPos = iTermPreferences.unsignedInteger(forKey: kPreferenceKeyStatusBarPosition)
        table["status_bar_location"] = .string(rawStatusPos == iTermStatusBarPosition.bottom.rawValue ? "bottom" : "top")
        table["always_show_tab_bar"] = .boolean(!iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))
        table["show_tab_numbers"] = .boolean(!iTermPreferences.bool(forKey: kPreferenceKeyHideTabNumber))
        table["show_tab_close_buttons"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyTabsHaveCloseButton))
        table["stretch_tabs"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyStretchTabsToFillBar))
        table["hide_scrollbars"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyHideScrollbar))
        table["show_pane_titles"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyShowPaneTitles))
        table["show_window_border"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyShowWindowBorder))
        table["side_margins"] = .integer(Int64(iTermPreferences.int(forKey: kPreferenceKeySideMargins)))
        table["top_bottom_margins"] = .integer(Int64(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)))
        table["dim_amount"] = .float(round(iTermPreferences.float(forKey: kPreferenceKeyDimmingAmount) * 1000.0) / 1000.0)
        table["dim_inactive_panes"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyDimInactiveSplitPanes))
        table["dim_background_windows"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyDimBackgroundWindows))
        table["dim_text_only"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyDimOnlyText))
        return table
    }

    // MARK: - [behavior]

    private static func applyBehavior(_ table: TOMLTable, changedKeys: inout [String]) throws {
        if let v = table.bool("quit_when_all_windows_closed") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyQuitWhenAllWindowsClosed, changedKeys: &changedKeys)
        }
        if let v = table.bool("confirm_closing_multiple_sessions") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyConfirmClosingMultipleTabs, changedKeys: &changedKeys)
        }
        if let v = table.bool("confirm_quit") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyPromptOnQuit, changedKeys: &changedKeys)
        }
        if let v = table.bool("copy_on_select") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeySelectionCopiesText, changedKeys: &changedKeys)
        }
        if let v = table.bool("copy_trailing_newline") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyCopyLastNewline, changedKeys: &changedKeys)
        }
        if let v = table.bool("clipboard_access") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyAllowClipboardAccessFromTerminal, changedKeys: &changedKeys)
        }
        if let v = table.string("word_characters") {
            setPref(v, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection, changedKeys: &changedKeys)
        }
        if let v = table.bool("gpu_rendering") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyUseMetal, changedKeys: &changedKeys)
        }
        if let v = table.bool("maximize_throughput") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyMaximizeThroughput, changedKeys: &changedKeys)
        }
        if let v = table.bool("native_fullscreen") {
            setPref(NSNumber(value: v), forKey: kPreferenceKeyLionStyleFullscreen, changedKeys: &changedKeys)
        }
    }

    private static func exportBehavior() -> TOMLTable {
        var table = TOMLTable()
        table["quit_when_all_windows_closed"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyQuitWhenAllWindowsClosed))
        table["confirm_closing_multiple_sessions"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyConfirmClosingMultipleTabs))
        table["confirm_quit"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyPromptOnQuit))
        table["copy_on_select"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeySelectionCopiesText))
        table["copy_trailing_newline"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyCopyLastNewline))
        table["clipboard_access"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyAllowClipboardAccessFromTerminal))
        if let wordChars = iTermPreferences.string(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection) {
            table["word_characters"] = .string(wordChars)
        }
        table["gpu_rendering"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyUseMetal))
        table["maximize_throughput"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyMaximizeThroughput))
        table["native_fullscreen"] = .boolean(iTermPreferences.bool(forKey: kPreferenceKeyLionStyleFullscreen))
        return table
    }

    // MARK: - [[keybindings]]

    private static let actionNamesByCode: [(KEY_ACTION, String)] = [
        (.ACTION_NEXT_SESSION, "next_tab"),
        (.ACTION_PREVIOUS_SESSION, "previous_tab"),
        (.ACTION_NEXT_WINDOW, "next_window"),
        (.ACTION_PREVIOUS_WINDOW, "previous_window"),
        (.ACTION_SCROLL_END, "scroll_to_end"),
        (.ACTION_SCROLL_HOME, "scroll_to_top"),
        (.ACTION_SCROLL_LINE_DOWN, "scroll_line_down"),
        (.ACTION_SCROLL_LINE_UP, "scroll_line_up"),
        (.ACTION_SCROLL_PAGE_DOWN, "scroll_page_down"),
        (.ACTION_SCROLL_PAGE_UP, "scroll_page_up"),
        (.ACTION_ESCAPE_SEQUENCE, "send_escape_sequence"),
        (.ACTION_HEX_CODE, "send_hex"),
        (.ACTION_TEXT, "send_text"),
        (.ACTION_VIM_TEXT, "send_vim_text"),
        (.ACTION_IGNORE, "ignore"),
        (.ACTION_SEND_C_H_BACKSPACE, "send_ctrl_h_backspace"),
        (.ACTION_SEND_C_QM_BACKSPACE, "send_ctrl_question_backspace"),
        (.ACTION_SELECT_PANE_LEFT, "select_pane_left"),
        (.ACTION_SELECT_PANE_RIGHT, "select_pane_right"),
        (.ACTION_SELECT_PANE_ABOVE, "select_pane_above"),
        (.ACTION_SELECT_PANE_BELOW, "select_pane_below"),
        (.ACTION_DO_NOT_REMAP_MODIFIERS, "do_not_remap_modifiers"),
        (.ACTION_TOGGLE_FULLSCREEN, "toggle_fullscreen"),
        (.ACTION_SELECT_MENU_ITEM, "select_menu_item"),
        (.ACTION_NEW_WINDOW_WITH_PROFILE, "new_window_with_profile"),
        (.ACTION_NEW_TAB_WITH_PROFILE, "new_tab_with_profile"),
        (.ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE, "split_horizontally_with_profile"),
        (.ACTION_SPLIT_VERTICALLY_WITH_PROFILE, "split_vertically_with_profile"),
        (.ACTION_NEXT_PANE, "next_pane"),
        (.ACTION_PREVIOUS_PANE, "previous_pane"),
        (.ACTION_NEXT_MRU_TAB, "next_mru_tab"),
        (.ACTION_PREVIOUS_MRU_TAB, "previous_mru_tab"),
        (.ACTION_MOVE_TAB_LEFT, "move_tab_left"),
        (.ACTION_MOVE_TAB_RIGHT, "move_tab_right"),
        (.ACTION_FIND_REGEX, "find_regex"),
        (.ACTION_SET_PROFILE, "set_profile"),
        (.ACTION_LOAD_COLOR_PRESET, "load_color_preset"),
        (.ACTION_TOGGLE_HOTKEY_WINDOW_PINNING, "toggle_hotkey_window_pinning"),
        (.ACTION_UNDO, "undo"),
        (.ACTION_DECREASE_HEIGHT, "decrease_pane_height"),
        (.ACTION_INCREASE_HEIGHT, "increase_pane_height"),
        (.ACTION_DECREASE_WIDTH, "decrease_pane_width"),
        (.ACTION_INCREASE_WIDTH, "increase_pane_width"),
        (.ACTION_SWAP_PANE_LEFT, "swap_pane_left"),
        (.ACTION_SWAP_PANE_RIGHT, "swap_pane_right"),
        (.ACTION_SWAP_PANE_ABOVE, "swap_pane_above"),
        (.ACTION_SWAP_PANE_BELOW, "swap_pane_below"),
        (.FIND_AGAIN_DOWN, "find_next"),
        (.FIND_AGAIN_UP, "find_previous"),
        (.ACTION_TOGGLE_MOUSE_REPORTING, "toggle_mouse_reporting"),
        (.ACTION_INVOKE_SCRIPT_FUNCTION, "invoke_expression"),
        (.ACTION_DUPLICATE_TAB, "duplicate_tab"),
        (.ACTION_MOVE_TO_SPLIT_PANE, "move_tab_to_split_pane"),
        (.ACTION_SEND_SNIPPET, "send_snippet"),
        (.ACTION_COMPOSE, "open_composer"),
        (.ACTION_SEND_TMUX_COMMAND, "send_tmux_command"),
        (.ACTION_SWAP_WITH_NEXT_PANE, "swap_with_next_pane"),
        (.ACTION_SWAP_WITH_PREVIOUS_PANE, "swap_with_previous_pane"),
        (.ACTION_COPY_OR_SEND, "copy_or_send"),
        (.ACTION_PASTE_OR_SEND, "paste_or_send"),
        (.ACTION_ALERT_ON_NEXT_MARK, "alert_on_next_mark"),
        (.ACTION_COPY_INTERPOLATED_STRING, "copy_interpolated_string"),
        (.ACTION_COPY_MODE, "copy_mode"),
        (.ACTION_BYPASS, "bypass_terminal")
    ]

    private static func applyKeybindings(_ items: [TOMLTable]) throws {
        var newGlobalMap: [String: Any] = [:]
        for (idx, entry) in items.enumerated() {
            guard let keySpec = entry.string("key"), !keySpec.isEmpty else {
                throw DeclarativeConfigError.invalidValue(
                    field: "keybindings[\(idx)].key",
                    message: "Missing key chord (for example, 'cmd+shift+d')"
                )
            }
            guard let actionSpec = entry.string("action"), !actionSpec.isEmpty else {
                throw DeclarativeConfigError.invalidValue(
                    field: "keybindings[\(idx)].action",
                    message: "Missing action name"
                )
            }
            let keystroke = try parseKeystroke(keySpec, rawSerialized: entry.string("serialized_key"))
            let actionCode = try parseKeyAction(actionSpec, index: idx)
            let parameter = entry.string("parameter") ?? entry.string("value") ?? ""
            let label = entry.string("label") ?? ""
            let escaping = parseEscaping(entry.string("escaping"), for: actionCode)
            let applyMode = parseApplyMode(entry.string("apply_mode"))

            guard let action = iTermKeyBindingAction.withAction(
                actionCode,
                parameter: parameter,
                label: label,
                escaping: escaping,
                applyMode: applyMode
            ) else {
                throw DeclarativeConfigError.invalidValue(
                    field: "keybindings[\(idx)]",
                    message: "Unable to construct keybinding action '\(actionSpec)'"
                )
            }
            newGlobalMap[keystroke.serialized] = action.dictionaryValue
        }
        iTermKeyMappings.setGlobalKeyMap(newGlobalMap)
    }

    private static func exportKeybindings() -> [TOMLTable] {
        let sorted = iTermKeyMappings.sortedGlobalKeystrokes()
        let rawMap = iTermKeyMappings.globalKeyMap()
        var exported: [TOMLTable] = []
        exported.reserveCapacity(sorted.count)

        for keystroke in sorted {
            guard let dict = keystroke.value(inBindingDictionary: rawMap as? [String: [AnyHashable: Any]] ?? [:]),
                  let action = iTermKeyBindingAction.withDictionary(dict) else {
                continue
            }
            var row = TOMLTable()
            let (humanKey, needsSerializedFallback) = formatKeystroke(keystroke)
            row["key"] = .string(humanKey)
            if needsSerializedFallback {
                row["serialized_key"] = .string(keystroke.serialized)
            }
            row["action"] = .string(formatKeyAction(action.keyAction))
            if !action.parameter.isEmpty {
                row["parameter"] = .string(action.parameter)
            }
            if !action.label.isEmpty {
                row["label"] = .string(action.label)
            }
            if action.keyAction == .ACTION_TEXT && action.escaping != .common {
                row["escaping"] = .string(formatEscaping(action.escaping))
            }
            if action.applyMode != .currentSession {
                row["apply_mode"] = .string(formatApplyMode(action.applyMode))
            }
            exported.append(row)
        }
        return exported
    }

    private static func parseKeyAction(_ name: String, index: Int) throws -> KEY_ACTION {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (code, candidate) in actionNamesByCode where candidate == normalized {
            return code
        }
        if normalized.hasPrefix("action_"),
           let raw = Int32(normalized.dropFirst("action_".count)),
           let code = KEY_ACTION(rawValue: raw) {
            return code
        }
        throw DeclarativeConfigError.invalidValue(
            field: "keybindings[\(index)].action",
            message: "Unknown keybinding action '\(name)'"
        )
    }

    private static func formatKeyAction(_ code: KEY_ACTION) -> String {
        for (candidate, name) in actionNamesByCode where candidate == code {
            return name
        }
        return "action_\(code.rawValue)"
    }

    private static func parseEscaping(_ spec: String?, for action: KEY_ACTION) -> iTermSendTextEscaping {
        guard let spec = spec?.lowercased() else {
            return action == .ACTION_VIM_TEXT ? .vim : .common
        }
        switch spec {
        case "none", "literal": return .none
        case "compatibility": return .compatibility
        case "common": return .common
        case "vim": return .vim
        default: return .common
        }
    }

    private static func formatEscaping(_ escaping: iTermSendTextEscaping) -> String {
        switch escaping {
        case .none: return "none"
        case .compatibility: return "compatibility"
        case .common: return "common"
        case .vim, .vimAndCompatibility: return "vim"
        @unknown default: return "common"
        }
    }

    private static func parseApplyMode(_ spec: String?) -> iTermActionApplyMode {
        switch spec?.lowercased() {
        case "all_sessions": return .allSessions
        case "unfocused_sessions": return .unfocusedSessions
        case "all_in_window": return .allInWindow
        case "all_in_tab": return .allInTab
        case "broadcasting": return .broadcasting
        default: return .currentSession
        }
    }

    private static func formatApplyMode(_ mode: iTermActionApplyMode) -> String {
        switch mode {
        case .currentSession: return "current_session"
        case .allSessions: return "all_sessions"
        case .unfocusedSessions: return "unfocused_sessions"
        case .allInWindow: return "all_in_window"
        case .allInTab: return "all_in_tab"
        case .broadcasting: return "broadcasting"
        @unknown default: return "current_session"
        }
    }

    static func parseKeystroke(_ chord: String, rawSerialized: String? = nil) throws -> iTermKeystroke {
        if let rawSerialized, !rawSerialized.isEmpty {
            let ks = iTermKeystroke(serialized: rawSerialized)
            if ks.isValid {
                return ks
            }
        }
        let trimmed = chord.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix(":") {
            let ks = iTermKeystroke(serialized: trimmed)
            if ks.isValid {
                return ks
            }
        }

        // Split on '+' while preserving a trailing '+' key (e.g., "cmd++")
        var tokens: [String] = []
        var current = ""
        for ch in trimmed {
            if ch == "+" && !current.isEmpty {
                tokens.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        } else if trimmed.hasSuffix("+") {
            tokens.append("+")
        }

        guard let keyPart = tokens.last else {
            throw DeclarativeConfigError.invalidValue(field: "key", message: "Empty key chord")
        }

        var flags: NSEvent.ModifierFlags = []
        for modToken in tokens.dropLast() {
            switch modToken.lowercased() {
            case "cmd", "command", "super", "⌘":
                flags.insert(.command)
            case "opt", "option", "alt", "⌥":
                flags.insert(.option)
            case "ctrl", "control", "⌃":
                flags.insert(.control)
            case "shift", "⇧":
                flags.insert(.shift)
            case "leader":
                flags.insert(NSEvent.ModifierFlags(rawValue: iTermEventModifierFlags.leaderModifierFlag.rawValue))
            case "numpad", "keypad":
                flags.insert(.numericPad)
            default:
                throw DeclarativeConfigError.invalidValue(
                    field: "key",
                    message: "Unknown modifier '\(modToken)' in '\(chord)'"
                )
            }
        }

        let character: UInt16
        switch keyPart.lowercased() {
        case "enter", "return": character = 0x0D
        case "tab": character = 0x09
        case "space": character = 0x20
        case "esc", "escape": character = 0x1B
        case "backspace": character = 0x7F
        case "delete", "forward_delete": character = UInt16(NSDeleteFunctionKey)
        case "insert": character = UInt16(NSInsertFunctionKey)
        case "up": character = UInt16(NSUpArrowFunctionKey)
        case "down": character = UInt16(NSDownArrowFunctionKey)
        case "left": character = UInt16(NSLeftArrowFunctionKey)
        case "right": character = UInt16(NSRightArrowFunctionKey)
        case "home": character = UInt16(NSHomeFunctionKey)
        case "end": character = UInt16(NSEndFunctionKey)
        case "pageup", "page_up": character = UInt16(NSPageUpFunctionKey)
        case "pagedown", "page_down": character = UInt16(NSPageDownFunctionKey)
        case "f1": character = UInt16(NSF1FunctionKey)
        case "f2": character = UInt16(NSF2FunctionKey)
        case "f3": character = UInt16(NSF3FunctionKey)
        case "f4": character = UInt16(NSF4FunctionKey)
        case "f5": character = UInt16(NSF5FunctionKey)
        case "f6": character = UInt16(NSF6FunctionKey)
        case "f7": character = UInt16(NSF7FunctionKey)
        case "f8": character = UInt16(NSF8FunctionKey)
        case "f9": character = UInt16(NSF9FunctionKey)
        case "f10": character = UInt16(NSF10FunctionKey)
        case "f11": character = UInt16(NSF11FunctionKey)
        case "f12": character = UInt16(NSF12FunctionKey)
        case "f13": character = UInt16(NSF13FunctionKey)
        case "f14": character = UInt16(NSF14FunctionKey)
        case "f15": character = UInt16(NSF15FunctionKey)
        case "f16": character = UInt16(NSF16FunctionKey)
        case "f17": character = UInt16(NSF17FunctionKey)
        case "f18": character = UInt16(NSF18FunctionKey)
        case "f19": character = UInt16(NSF19FunctionKey)
        case "f20": character = UInt16(NSF20FunctionKey)
        default:
            let lowered = keyPart.lowercased()
            guard lowered.utf16.count == 1, let codeUnit = lowered.utf16.first else {
                throw DeclarativeConfigError.invalidValue(
                    field: "key",
                    message: "Unrecognized key '\(keyPart)' in '\(chord)'"
                )
            }
            character = codeUnit
        }

        return iTermKeystroke.withCharacter(character, modifierFlags: flags)
    }

    static func formatKeystroke(_ keystroke: iTermKeystroke) -> (String, Bool) {
        var parts: [String] = []
        let mods = keystroke.modifierFlags
        if mods.rawValue & iTermEventModifierFlags.leaderModifierFlag.rawValue != 0 {
            parts.append("leader")
        }
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("opt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }

        let ch = Int(keystroke.character)
        let isArrow = ch >= NSUpArrowFunctionKey && ch <= NSRightArrowFunctionKey
        if mods.contains(.numericPad) && !isArrow {
            parts.append("numpad")
        }

        let keyName: String?
        switch ch {
        case 0x0D, 0x0A, 0x03: keyName = "enter"
        case 0x09, 0x19: keyName = "tab"
        case 0x20: keyName = "space"
        case 0x1B: keyName = "escape"
        case 0x7F, 0x08: keyName = "backspace"
        case NSDeleteFunctionKey: keyName = "delete"
        case NSInsertFunctionKey: keyName = "insert"
        case NSUpArrowFunctionKey: keyName = "up"
        case NSDownArrowFunctionKey: keyName = "down"
        case NSLeftArrowFunctionKey: keyName = "left"
        case NSRightArrowFunctionKey: keyName = "right"
        case NSHomeFunctionKey: keyName = "home"
        case NSEndFunctionKey: keyName = "end"
        case NSPageUpFunctionKey: keyName = "pageup"
        case NSPageDownFunctionKey: keyName = "pagedown"
        case NSF1FunctionKey...NSF20FunctionKey:
            keyName = "f\(ch - NSF1FunctionKey + 1)"
        default:
            if ch > 0x20 && ch < 0x7F, let scalar = UnicodeScalar(ch) {
                keyName = String(scalar).lowercased()
            } else {
                keyName = nil
            }
        }

        guard let keyName else {
            return (keystroke.serialized, true)
        }
        parts.append(keyName)
        return (parts.joined(separator: "+"), keystroke.hasVirtualKeyCode)
    }

    // MARK: - [[profiles]]

    private static let colorFieldMappings: [(tomlKey: String, profileKey: String)] = [
        ("foreground", KEY_FOREGROUND_COLOR),
        ("background", KEY_BACKGROUND_COLOR),
        ("bold", KEY_BOLD_COLOR),
        ("selection", KEY_SELECTION_COLOR),
        ("selected_text", KEY_SELECTED_TEXT_COLOR),
        ("cursor", KEY_CURSOR_COLOR),
        ("cursor_text", KEY_CURSOR_TEXT_COLOR),
        ("link", KEY_LINK_COLOR),
        ("match", KEY_MATCH_COLOR),
        ("cursor_guide", KEY_CURSOR_GUIDE_COLOR),
        ("badge", KEY_BADGE_COLOR),
        ("tab", KEY_TAB_COLOR),
        ("underline", KEY_UNDERLINE_COLOR),
        ("active_pane_border", KEY_ACTIVE_PANE_BORDER_COLOR)
    ]

    private static let ansiProfileKeys: [String] = [
        KEY_ANSI_0_COLOR, KEY_ANSI_1_COLOR, KEY_ANSI_2_COLOR, KEY_ANSI_3_COLOR,
        KEY_ANSI_4_COLOR, KEY_ANSI_5_COLOR, KEY_ANSI_6_COLOR, KEY_ANSI_7_COLOR,
        KEY_ANSI_8_COLOR, KEY_ANSI_9_COLOR, KEY_ANSI_10_COLOR, KEY_ANSI_11_COLOR,
        KEY_ANSI_12_COLOR, KEY_ANSI_13_COLOR, KEY_ANSI_14_COLOR, KEY_ANSI_15_COLOR
    ]

    private static let ansiNamedKeys: [String] = [
        "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        "bright_black", "bright_red", "bright_green", "bright_yellow",
        "bright_blue", "bright_magenta", "bright_cyan", "bright_white"
    ]

    private static func deterministicGUID(forName name: String) -> String {
        let digest = SHA256.hash(data: Data(("latterm.profile." + name).utf8))
        let bytes = Array(digest)
        return String(
            format: "%02X%02X%02X%02X-%02X%02X-5%01X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6] & 0x0F, bytes[7],
            (bytes[8] & 0x3F) | 0x80, bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }

    private static func applyProfiles(_ profileTables: [TOMLTable], to model: ProfileModel) throws {
        var defaultGuidToSelect: String?
        var preparedUpdates: [(guid: String, dict: [String: Any], isNew: Bool)] = []

        for (idx, table) in profileTables.enumerated() {
            let explicitGuid = table.string("guid")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitName = table.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines)

            let existingProfile: [AnyHashable: Any]?
            if let explicitGuid, !explicitGuid.isEmpty, let found = model.bookmark(withGuid: explicitGuid) {
                existingProfile = found
            } else if let explicitName, !explicitName.isEmpty, let found = model.bookmark(withName: explicitName) {
                existingProfile = found
            } else {
                existingProfile = nil
            }

            var mutable: [String: Any]
            let isNew: Bool
            if let existingProfile {
                mutable = existingProfile.reduce(into: [String: Any]()) { acc, pair in
                    if let k = pair.key as? String {
                        acc[k] = pair.value
                    }
                }
                isNew = false
            } else {
                let baseline = model.defaultBookmark() ?? iTermProfilePreferences.defaultValueMap()
                mutable = baseline.reduce(into: [String: Any]()) { acc, pair in
                    if let k = pair.key as? String {
                        acc[k] = pair.value
                    }
                }
                isNew = true
            }

            let resolvedName: String
            if let explicitName, !explicitName.isEmpty {
                resolvedName = explicitName
            } else if let currentName = mutable[KEY_NAME] as? String, !currentName.isEmpty {
                resolvedName = currentName
            } else {
                resolvedName = "Profile \(idx + 1)"
            }
            mutable[KEY_NAME] = resolvedName

            let resolvedGuid: String
            if let explicitGuid, !explicitGuid.isEmpty {
                resolvedGuid = explicitGuid
            } else if !isNew, let currentGuid = mutable[KEY_GUID] as? String, !currentGuid.isEmpty {
                resolvedGuid = currentGuid
            } else {
                resolvedGuid = deterministicGUID(forName: resolvedName)
            }
            mutable[KEY_GUID] = resolvedGuid

            if let tags = table.stringArray("tags") {
                mutable[KEY_TAGS] = tags
            }
            if let command = table.string("command") {
                let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedCommand.isEmpty {
                    mutable[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeLoginShellValue
                } else {
                    mutable[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeCustomValue
                    mutable[KEY_COMMAND_LINE] = command
                }
            }
            if let workingDir = table.string("working_directory") {
                switch workingDir.lowercased() {
                case "home", "~":
                    mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryHomeValue
                case "reuse", "recycle":
                    mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryRecycleValue
                default:
                    mutable[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue
                    mutable[KEY_WORKING_DIRECTORY] = (workingDir as NSString).expandingTildeInPath
                }
            }

            if let fontTable = table.table("font") {
                try applyProfileFont(fontTable, into: &mutable, profileIndex: idx)
            }
            if let cursorTable = table.table("cursor") {
                try applyProfileCursor(cursorTable, into: &mutable, profileIndex: idx)
            }
            if let windowTable = table.table("window") {
                applyProfileWindow(windowTable, into: &mutable)
            }
            if let terminalTable = table.table("terminal") {
                try applyProfileTerminal(terminalTable, into: &mutable, profileIndex: idx)
            }
            if let colorsTable = table.table("colors") {
                try applyProfileColors(colorsTable, into: &mutable, profileIndex: idx)
            }

            if table.bool("default") == true {
                defaultGuidToSelect = resolvedGuid
            }
            preparedUpdates.append((guid: resolvedGuid, dict: mutable, isNew: isNew))
        }

        model.performBlock {
            for update in preparedUpdates {
                if update.isNew && model.bookmark(withGuid: update.guid) == nil {
                    model.addBookmark(update.dict)
                } else {
                    model.setBookmark(update.dict, withGuid: update.guid)
                }
            }
            if let defaultGuidToSelect {
                model.setDefaultByGuid(defaultGuidToSelect)
            }
            model.flush()
        }
        NotificationCenter.default.post(name: Notification.Name(rawValue: kReloadAllProfiles), object: nil)
    }

    private static func applyProfileFont(_ font: TOMLTable,
                                         into profile: inout [String: Any],
                                         profileIndex: Int) throws {
        let currentNormal = (profile[KEY_NORMAL_FONT] as? String) ?? "Menlo-Regular 12"
        let currentNSFont = (currentNormal as NSString).fontValue(withLigaturesEnabled: true)
        let targetFamily = font.string("family") ?? currentNSFont.familyName ?? currentNSFont.fontName
        let targetSize = font.double("size") ?? Double(currentNSFont.pointSize)
        if font.contains("family") || font.contains("size") {
            profile[KEY_NORMAL_FONT] = encodeFontString(familyOrName: targetFamily, size: targetSize)
        }

        if let useNonASCII = font.bool("use_non_ascii") {
            profile[KEY_USE_NONASCII_FONT] = useNonASCII
        }
        if font.contains("non_ascii_family") || font.contains("non_ascii_size") {
            let currentNonASCII = (profile[KEY_NON_ASCII_FONT] as? String) ?? currentNormal
            let baseNonASCII = (currentNonASCII as NSString).fontValue(withLigaturesEnabled: true)
            let family = font.string("non_ascii_family") ?? baseNonASCII.familyName ?? baseNonASCII.fontName
            let size = font.double("non_ascii_size") ?? Double(baseNonASCII.pointSize)
            profile[KEY_NON_ASCII_FONT] = encodeFontString(familyOrName: family, size: size)
            if !font.contains("use_non_ascii") {
                profile[KEY_USE_NONASCII_FONT] = true
            }
        }

        if let ligatures = font.bool("ligatures") {
            profile[KEY_ASCII_LIGATURES] = ligatures
        }
        if let nonAsciiLigatures = font.bool("non_ascii_ligatures") {
            profile[KEY_NON_ASCII_LIGATURES] = nonAsciiLigatures
        }
        if let antiAliased = font.bool("anti_aliased") {
            profile[KEY_ASCII_ANTI_ALIASED] = antiAliased
            profile[KEY_NONASCII_ANTI_ALIASED] = antiAliased
        }
        if let powerline = font.bool("powerline_glyphs") {
            profile[KEY_POWERLINE] = powerline
        }
        if let useBold = font.bool("use_bold_font") {
            profile[KEY_USE_BOLD_FONT] = useBold
        }
        if let useItalic = font.bool("use_italic_font") {
            profile[KEY_USE_ITALIC_FONT] = useItalic
        }
        if let hSpacing = font.double("horizontal_spacing") {
            profile[KEY_HORIZONTAL_SPACING] = max(0.5, min(2.0, hSpacing))
        }
        if let vSpacing = font.double("vertical_spacing") {
            profile[KEY_VERTICAL_SPACING] = max(0.5, min(2.0, vSpacing))
        }

        if font.contains("language_rules") {
            guard let ruleTables = font.tableArray("language_rules") else {
                throw DeclarativeConfigError.invalidValue(
                    field: "profiles[\(profileIndex)].font.language_rules",
                    message: "Expected an array of language rule tables"
                )
            }
            var rules: [FontTable.LanguageRule] = []
            for (rIdx, ruleTable) in ruleTables.enumerated() {
                guard let scriptRaw = ruleTable.string("script"),
                      let script = parseFontScript(scriptRaw) else {
                    throw DeclarativeConfigError.invalidValue(
                        field: "profiles[\(profileIndex)].font.language_rules[\(rIdx)].script",
                        message: "Expected zh-Hans, zh-Hant, ja, ja-Kana, ko, ko-Hang, Cyrl, Grek, Arab, Hebr, Deva, Thai, or Zsym"
                    )
                }
                guard let family = ruleTable.string("family"), !family.isEmpty else {
                    throw DeclarativeConfigError.invalidValue(
                        field: "profiles[\(profileIndex)].font.language_rules[\(rIdx)].family",
                        message: "Font family name is required"
                    )
                }
                let scale = max(50, min(200, ruleTable.int("scale_percent") ?? 100))
                let baseline = CGFloat(max(-20.0, min(20.0, ruleTable.double("baseline_offset") ?? 0.0)))
                let enabled = ruleTable.bool("enabled") ?? true
                rules.append(
                    FontTable.LanguageRule(
                        script: script,
                        fontName: family,
                        scalePercent: scale,
                        baselineOffset: baseline,
                        enabled: enabled
                    )
                )
            }
            let existingEntries = (profile[KEY_FONT_CONFIG] as? String)
                .flatMap { FontTable.Config(string: $0)?.entries } ?? []
            let newConfig = FontTable.Config(entries: existingEntries, languageRules: rules)
            profile[KEY_FONT_CONFIG] = newConfig.isEmpty ? "" : newConfig.stringValue
        }
    }

    private static func parseFontScript(_ raw: String) -> FontLanguageScript? {
        if let exact = FontLanguageScript(rawValue: raw) {
            return exact
        }
        switch raw.lowercased() {
        case "zh-hans", "chinese_simplified", "sc": return .chineseSimplified
        case "zh-hant", "chinese_traditional", "tc": return .chineseTraditional
        case "ja", "japanese": return .japanese
        case "ja-kana", "kana": return .japaneseKana
        case "ko", "korean": return .korean
        case "ko-hang", "hangul": return .koreanHangul
        case "cyrl", "cyrillic": return .cyrillic
        case "grek", "greek": return .greek
        case "arab", "arabic": return .arabic
        case "hebr", "hebrew": return .hebrew
        case "deva", "devanagari": return .devanagari
        case "thai": return .thai
        case "zsym", "symbols", "nerd_font": return .symbolsAndNerdFont
        default: return nil
        }
    }

    static func encodeFontString(familyOrName: String, size: Double) -> String {
        let clampedSize = CGFloat(max(2.0, min(200.0, size)))
        if let exact = NSFont(name: familyOrName, size: clampedSize) {
            return exact.stringValue
        }
        if let byFamily = NSFontManager.shared.font(withFamily: familyOrName,
                                                    traits: [],
                                                    weight: 5,
                                                    size: clampedSize) {
            return byFamily.stringValue
        }
        let compactName = familyOrName.replacingOccurrences(of: " ", with: "")
        let formattedSize = clampedSize.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(clampedSize))
            : String(Double(clampedSize))
        return "\(compactName) \(formattedSize)"
    }

    private static func applyProfileCursor(_ cursor: TOMLTable,
                                           into profile: inout [String: Any],
                                           profileIndex: Int) throws {
        if let style = cursor.string("style") {
            let cursorCode: Int
            switch style.lowercased() {
            case "underline": cursorCode = ITermCursorType.CURSOR_UNDERLINE.rawValue
            case "vertical", "bar", "beam": cursorCode = ITermCursorType.CURSOR_VERTICAL.rawValue
            case "box", "block": cursorCode = ITermCursorType.CURSOR_BOX.rawValue
            default:
                throw DeclarativeConfigError.invalidValue(
                    field: "profiles[\(profileIndex)].cursor.style",
                    message: "Expected box, vertical, or underline"
                )
            }
            profile[KEY_CURSOR_TYPE] = cursorCode
        }
        if let blink = cursor.bool("blink") {
            profile[KEY_BLINKING_CURSOR] = blink
        }
        if let smoothBlink = cursor.bool("smooth_blink") {
            profile[KEY_CURSOR_SMOOTH_BLINK] = smoothBlink
        }
        if let smoothSlide = cursor.bool("smooth_slide") {
            profile[KEY_CURSOR_SMOOTH_SLIDE] = smoothSlide
        }
        if let shadow = cursor.bool("shadow") {
            profile[KEY_CURSOR_SHADOW] = shadow
        }
        if let hideUnfocused = cursor.bool("hide_when_unfocused") {
            profile[KEY_CURSOR_HIDDEN_WITHOUT_FOCUS] = hideUnfocused
        }
    }

    private static func applyProfileWindow(_ window: TOMLTable, into profile: inout [String: Any]) {
        if let cols = window.int("columns") {
            profile[KEY_COLUMNS] = max(10, min(1000, cols))
        }
        if let rows = window.int("rows") {
            profile[KEY_ROWS] = max(2, min(500, rows))
        }
        if let transparency = window.double("transparency") {
            let clamped = max(0.0, min(1.0, transparency))
            profile[KEY_TRANSPARENCY] = clamped
            profile[KEY_INITIAL_USE_TRANSPARENCY] = clamped > 0.0
        }
        if let blur = window.bool("blur") {
            profile[KEY_BLUR] = blur
        }
        if let blurRadius = window.double("blur_radius") {
            profile[KEY_BLUR_RADIUS] = max(0.1, min(64.0, blurRadius))
        }
        if let keepBgOpaque = window.bool("keep_background_opaque") {
            profile[KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR] = keepBgOpaque
        }
        if let showStatusBar = window.bool("show_status_bar") {
            profile[KEY_SHOW_STATUS_BAR] = showStatusBar
        }
    }

    private static func applyProfileTerminal(_ terminal: TOMLTable,
                                             into profile: inout [String: Any],
                                             profileIndex: Int) throws {
        if let scrollback = terminal.int("scrollback_lines") {
            profile[KEY_SCROLLBACK_LINES] = max(0, scrollback)
        }
        if let unlimited = terminal.bool("unlimited_scrollback") {
            profile[KEY_UNLIMITED_SCROLLBACK] = unlimited
        }
        if let term = terminal.string("term"), !term.isEmpty {
            profile[KEY_TERMINAL_TYPE] = term
        }
        if let mouse = terminal.bool("mouse_reporting") {
            profile[KEY_XTERM_MOUSE_REPORTING] = mouse
        }
        if let silenceBell = terminal.bool("silence_bell") {
            profile[KEY_SILENCE_BELL] = silenceBell
        }
        if let visualBell = terminal.bool("visual_bell") {
            profile[KEY_VISUAL_BELL] = visualBell
        }
        if let optMode = terminal.string("option_as_alt") {
            profile[KEY_OPTION_KEY_SENDS] = try parseOptionKeyMode(
                optMode,
                field: "profiles[\(profileIndex)].terminal.option_as_alt"
            )
        }
        if let rightOptMode = terminal.string("right_option_as_alt") {
            profile[KEY_RIGHT_OPTION_KEY_SENDS] = try parseOptionKeyMode(
                rightOptMode,
                field: "profiles[\(profileIndex)].terminal.right_option_as_alt"
            )
        }
    }

    private static func parseOptionKeyMode(_ mode: String, field: String) throws -> Int32 {
        switch mode.lowercased() {
        case "normal", "none": return iTermOptionKeyBehavior.OPT_NORMAL.rawValue
        case "meta": return iTermOptionKeyBehavior.OPT_META.rawValue
        case "esc+", "esc": return iTermOptionKeyBehavior.OPT_ESC.rawValue
        default:
            throw DeclarativeConfigError.invalidValue(field: field, message: "Expected normal, meta, or esc+")
        }
    }

    private static func applyProfileColors(_ colors: TOMLTable,
                                           into profile: inout [String: Any],
                                           profileIndex: Int) throws {
        if let separate = colors.bool("separate_light_dark") {
            profile[KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] = separate
        } else if colors.contains("light") || colors.contains("dark") {
            profile[KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] = true
        }

        try applyColorPalette(colors, suffix: "", into: &profile, fieldPrefix: "profiles[\(profileIndex)].colors")
        if let light = colors.table("light") {
            try applyColorPalette(
                light,
                suffix: COLORS_LIGHT_MODE_SUFFIX,
                into: &profile,
                fieldPrefix: "profiles[\(profileIndex)].colors.light"
            )
        }
        if let dark = colors.table("dark") {
            try applyColorPalette(
                dark,
                suffix: COLORS_DARK_MODE_SUFFIX,
                into: &profile,
                fieldPrefix: "profiles[\(profileIndex)].colors.dark"
            )
        }
    }

    private static func applyColorPalette(_ palette: TOMLTable,
                                          suffix: String,
                                          into profile: inout [String: Any],
                                          fieldPrefix: String) throws {
        for (tomlKey, profileKey) in colorFieldMappings {
            if let hex = palette.string(tomlKey) {
                profile[profileKey + suffix] = try parseHexColorDictionary(
                    hex,
                    field: "\(fieldPrefix).\(tomlKey)"
                )
            }
        }
        if let ansiList = palette.stringArray("ansi") {
            guard ansiList.count == 16 else {
                throw DeclarativeConfigError.invalidValue(
                    field: "\(fieldPrefix).ansi",
                    message: "Expected exactly 16 hex color strings (ANSI 0 through 15)"
                )
            }
            for (i, hex) in ansiList.enumerated() {
                profile[ansiProfileKeys[i] + suffix] = try parseHexColorDictionary(
                    hex,
                    field: "\(fieldPrefix).ansi[\(i)]"
                )
            }
        }
        for (i, namedKey) in ansiNamedKeys.enumerated() {
            if let hex = palette.string(namedKey) {
                profile[ansiProfileKeys[i] + suffix] = try parseHexColorDictionary(
                    hex,
                    field: "\(fieldPrefix).\(namedKey)"
                )
            }
        }

        if let v = palette.bool("use_bold_color") { profile[KEY_USE_BOLD_COLOR + suffix] = v }
        if let v = palette.bool("brighten_bold") { profile[KEY_BRIGHTEN_BOLD_TEXT + suffix] = v }
        if let v = palette.bool("use_selected_text_color") { profile[KEY_USE_SELECTED_TEXT_COLOR + suffix] = v }
        if let v = palette.bool("smart_cursor_color") { profile[KEY_SMART_CURSOR_COLOR + suffix] = v }
        if let v = palette.bool("use_cursor_guide") { profile[KEY_USE_CURSOR_GUIDE + suffix] = v }
        if let v = palette.bool("use_tab_color") { profile[KEY_USE_TAB_COLOR + suffix] = v }
        if let v = palette.bool("use_underline_color") { profile[KEY_USE_UNDERLINE_COLOR + suffix] = v }
        if let v = palette.bool("use_active_pane_border") { profile[KEY_USE_ACTIVE_PANE_BORDER + suffix] = v }
        if let v = palette.double("minimum_contrast") {
            profile[KEY_MINIMUM_CONTRAST + suffix] = max(0.0, min(1.0, v))
        }
        if let v = palette.double("faint_text_alpha") {
            profile[KEY_FAINT_TEXT_ALPHA + suffix] = max(0.0, min(1.0, v))
        }
    }

    static func parseHexColorDictionary(_ rawHex: String, field: String) throws -> [String: Any] {
        var cleaned = rawHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard (cleaned.count == 6 || cleaned.count == 8),
              let parsed = UInt64(cleaned, radix: 16) else {
            throw DeclarativeConfigError.invalidValue(
                field: field,
                message: "Expected #RRGGBB or #RRGGBBAA hex color, got '\(rawHex)'"
            )
        }
        let r, g, b, a: UInt64
        if cleaned.count == 6 {
            r = (parsed >> 16) & 0xFF
            g = (parsed >> 8) & 0xFF
            b = parsed & 0xFF
            a = 255
        } else {
            r = (parsed >> 24) & 0xFF
            g = (parsed >> 16) & 0xFF
            b = (parsed >> 8) & 0xFF
            a = parsed & 0xFF
        }
        return [
            kEncodedColorDictionaryColorSpace: kEncodedColorDictionarySRGBColorSpace,
            kEncodedColorDictionaryRedComponent: Double(r) / 255.0,
            kEncodedColorDictionaryGreenComponent: Double(g) / 255.0,
            kEncodedColorDictionaryBlueComponent: Double(b) / 255.0,
            kEncodedColorDictionaryAlphaComponent: Double(a) / 255.0
        ]
    }

    static func formatHexColorDictionary(_ dictObj: Any?) -> String? {
        guard let dict = dictObj as? [AnyHashable: Any] else {
            return nil
        }
        var srgb = iTermSRGBColor(r: 0, g: 0, b: 0)
        guard iTermSRGBColorFromDictionary(dict, &srgb) else {
            return nil
        }
        let r = max(0, min(255, Int((srgb.r * 255.0).rounded())))
        let g = max(0, min(255, Int((srgb.g * 255.0).rounded())))
        let b = max(0, min(255, Int((srgb.b * 255.0).rounded())))
        let alphaNum = (dict[kEncodedColorDictionaryAlphaComponent] as? NSNumber)?.doubleValue ?? 1.0
        let a = max(0, min(255, Int((alphaNum * 255.0).rounded())))
        if a < 255 {
            return String(format: "#%02x%02x%02x%02x", r, g, b, a)
        }
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    // MARK: - Profile Export

    private static func exportProfiles(from model: ProfileModel) -> [TOMLTable] {
        let defaultGuid = model.defaultBookmark()?[KEY_GUID] as? String
        let allBookmarks = model.bookmarks() ?? []
        var result: [TOMLTable] = []
        result.reserveCapacity(allBookmarks.count)

        for profile in allBookmarks {
            var table = TOMLTable()
            let name = (profile[KEY_NAME] as? String) ?? "Default"
            let guid = (profile[KEY_GUID] as? String) ?? ""
            table["name"] = .string(name)
            if !guid.isEmpty {
                table["guid"] = .string(guid)
                table["default"] = .boolean(guid == defaultGuid)
            }
            if let tags = profile[KEY_TAGS] as? [String], !tags.isEmpty {
                table["tags"] = .array(tags.map { .string($0) })
            }

            let customCmd = iTermProfilePreferences.string(forKey: KEY_CUSTOM_COMMAND, inProfile: profile)
            if customCmd == kProfilePreferenceCommandTypeCustomValue,
               let cmdLine = iTermProfilePreferences.string(forKey: KEY_COMMAND_LINE, inProfile: profile),
               !cmdLine.isEmpty {
                table["command"] = .string(cmdLine)
            } else {
                table["command"] = .string("")
            }

            let dirType = iTermProfilePreferences.string(forKey: KEY_CUSTOM_DIRECTORY, inProfile: profile)
            if dirType == kProfilePreferenceInitialDirectoryRecycleValue {
                table["working_directory"] = .string("reuse")
            } else if dirType == kProfilePreferenceInitialDirectoryCustomValue,
                      let customDir = iTermProfilePreferences.string(forKey: KEY_WORKING_DIRECTORY, inProfile: profile),
                      !customDir.isEmpty {
                table["working_directory"] = .string((customDir as NSString).abbreviatingWithTildeInPath)
            } else {
                table["working_directory"] = .string("home")
            }

            table["font"] = .table(exportProfileFont(profile))
            table["cursor"] = .table(exportProfileCursor(profile))
            table["window"] = .table(exportProfileWindow(profile))
            table["terminal"] = .table(exportProfileTerminal(profile))
            table["colors"] = .table(exportProfileColors(profile))
            result.append(table)
        }
        return result
    }

    private static func exportProfileFont(_ profile: [AnyHashable: Any]) -> TOMLTable {
        var font = TOMLTable()
        let normalStr = iTermProfilePreferences.string(forKey: KEY_NORMAL_FONT, inProfile: profile) ?? "Menlo-Regular 12"
        let normalFont = (normalStr as NSString).fontValue(withLigaturesEnabled: true)
        font["family"] = .string(normalFont.familyName ?? normalFont.fontName)
        font["size"] = .float(Double(normalFont.pointSize))
        font["ligatures"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_ASCII_LIGATURES, inProfile: profile))
        font["anti_aliased"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_ASCII_ANTI_ALIASED, inProfile: profile))
        font["powerline_glyphs"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_POWERLINE, inProfile: profile))
        font["use_bold_font"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_USE_BOLD_FONT, inProfile: profile))
        font["use_italic_font"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_USE_ITALIC_FONT, inProfile: profile))
        font["horizontal_spacing"] = .float(round(iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: profile) * 1000.0) / 1000.0)
        font["vertical_spacing"] = .float(round(iTermProfilePreferences.double(forKey: KEY_VERTICAL_SPACING, inProfile: profile) * 1000.0) / 1000.0)

        let useNonASCII = iTermProfilePreferences.bool(forKey: KEY_USE_NONASCII_FONT, inProfile: profile)
        font["use_non_ascii"] = .boolean(useNonASCII)
        if useNonASCII, let nonASCIIStr = iTermProfilePreferences.string(forKey: KEY_NON_ASCII_FONT, inProfile: profile) {
            let nonASCIIFont = (nonASCIIStr as NSString).fontValue(withLigaturesEnabled: true)
            font["non_ascii_family"] = .string(nonASCIIFont.familyName ?? nonASCIIFont.fontName)
            font["non_ascii_size"] = .float(Double(nonASCIIFont.pointSize))
            font["non_ascii_ligatures"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_NON_ASCII_LIGATURES, inProfile: profile))
        }

        if let fontConfigStr = iTermProfilePreferences.string(forKey: KEY_FONT_CONFIG, inProfile: profile),
           let parsedConfig = FontTable.Config(string: fontConfigStr),
           !parsedConfig.languageRules.isEmpty {
            let rules = parsedConfig.languageRules.map { rule -> TOMLValue in
                var rt = TOMLTable()
                rt["script"] = .string(rule.script.rawValue)
                rt["family"] = .string(rule.fontName)
                rt["scale_percent"] = .integer(Int64(rule.scalePercent))
                rt["baseline_offset"] = .float(Double(rule.baselineOffset))
                rt["enabled"] = .boolean(rule.enabled)
                return .table(rt)
            }
            font["language_rules"] = .array(rules)
        }
        return font
    }

    private static func exportProfileCursor(_ profile: [AnyHashable: Any]) -> TOMLTable {
        var cursor = TOMLTable()
        let rawType = Int(iTermProfilePreferences.int(forKey: KEY_CURSOR_TYPE, inProfile: profile))
        let style: String
        if rawType == ITermCursorType.CURSOR_UNDERLINE.rawValue {
            style = "underline"
        } else if rawType == ITermCursorType.CURSOR_VERTICAL.rawValue {
            style = "vertical"
        } else {
            style = "box"
        }
        cursor["style"] = .string(style)
        cursor["blink"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_BLINKING_CURSOR, inProfile: profile))
        cursor["smooth_blink"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_CURSOR_SMOOTH_BLINK, inProfile: profile))
        cursor["smooth_slide"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_CURSOR_SMOOTH_SLIDE, inProfile: profile))
        cursor["shadow"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_CURSOR_SHADOW, inProfile: profile))
        cursor["hide_when_unfocused"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_CURSOR_HIDDEN_WITHOUT_FOCUS, inProfile: profile))
        return cursor
    }

    private static func exportProfileWindow(_ profile: [AnyHashable: Any]) -> TOMLTable {
        var window = TOMLTable()
        window["columns"] = .integer(Int64(iTermProfilePreferences.int(forKey: KEY_COLUMNS, inProfile: profile)))
        window["rows"] = .integer(Int64(iTermProfilePreferences.int(forKey: KEY_ROWS, inProfile: profile)))
        window["transparency"] = .float(round(iTermProfilePreferences.double(forKey: KEY_TRANSPARENCY, inProfile: profile) * 1000.0) / 1000.0)
        window["blur"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_BLUR, inProfile: profile))
        window["blur_radius"] = .float(round(iTermProfilePreferences.double(forKey: KEY_BLUR_RADIUS, inProfile: profile) * 100.0) / 100.0)
        window["keep_background_opaque"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR, inProfile: profile))
        window["show_status_bar"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_SHOW_STATUS_BAR, inProfile: profile))
        return window
    }

    private static func exportProfileTerminal(_ profile: [AnyHashable: Any]) -> TOMLTable {
        var terminal = TOMLTable()
        terminal["scrollback_lines"] = .integer(Int64(iTermProfilePreferences.int(forKey: KEY_SCROLLBACK_LINES, inProfile: profile)))
        terminal["unlimited_scrollback"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_UNLIMITED_SCROLLBACK, inProfile: profile))
        if let term = iTermProfilePreferences.string(forKey: KEY_TERMINAL_TYPE, inProfile: profile) {
            terminal["term"] = .string(term)
        }
        terminal["mouse_reporting"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_XTERM_MOUSE_REPORTING, inProfile: profile))
        terminal["silence_bell"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_SILENCE_BELL, inProfile: profile))
        terminal["visual_bell"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_VISUAL_BELL, inProfile: profile))
        terminal["option_as_alt"] = .string(formatOptionKeyMode(iTermProfilePreferences.int(forKey: KEY_OPTION_KEY_SENDS, inProfile: profile)))
        terminal["right_option_as_alt"] = .string(formatOptionKeyMode(iTermProfilePreferences.int(forKey: KEY_RIGHT_OPTION_KEY_SENDS, inProfile: profile)))
        return terminal
    }

    private static func formatOptionKeyMode(_ raw: Int32) -> String {
        if raw == iTermOptionKeyBehavior.OPT_META.rawValue { return "meta" }
        if raw == iTermOptionKeyBehavior.OPT_ESC.rawValue { return "esc+" }
        return "normal"
    }

    private static func exportProfileColors(_ profile: [AnyHashable: Any]) -> TOMLTable {
        let separate = iTermProfilePreferences.bool(forKey: KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE, inProfile: profile)
        var colors = exportColorPalette(from: profile, suffix: "")
        colors["separate_light_dark"] = .boolean(separate)
        if separate {
            let light = exportColorPalette(from: profile, suffix: COLORS_LIGHT_MODE_SUFFIX)
            if !light.isEmpty {
                colors["light"] = .table(light)
            }
            let dark = exportColorPalette(from: profile, suffix: COLORS_DARK_MODE_SUFFIX)
            if !dark.isEmpty {
                colors["dark"] = .table(dark)
            }
        }
        return colors
    }

    private static func exportColorPalette(from profile: [AnyHashable: Any], suffix: String) -> TOMLTable {
        var palette = TOMLTable()
        for (tomlKey, profileKey) in colorFieldMappings {
            let dict = iTermProfilePreferences.object(forKey: profileKey + suffix, inProfile: profile)
            if let hex = formatHexColorDictionary(dict) {
                palette[tomlKey] = .string(hex)
            }
        }

        var ansiHex: [TOMLValue] = []
        for ansiKey in ansiProfileKeys {
            let dict = iTermProfilePreferences.object(forKey: ansiKey + suffix, inProfile: profile)
            if let hex = formatHexColorDictionary(dict) {
                ansiHex.append(.string(hex))
            }
        }
        if ansiHex.count == 16 {
            palette["ansi"] = .array(ansiHex)
        }

        palette["use_bold_color"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_USE_BOLD_COLOR + suffix, inProfile: profile))
        palette["brighten_bold"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_BRIGHTEN_BOLD_TEXT + suffix, inProfile: profile))
        palette["use_selected_text_color"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_USE_SELECTED_TEXT_COLOR + suffix, inProfile: profile))
        palette["smart_cursor_color"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_SMART_CURSOR_COLOR + suffix, inProfile: profile))
        palette["use_cursor_guide"] = .boolean(iTermProfilePreferences.bool(forKey: KEY_USE_CURSOR_GUIDE + suffix, inProfile: profile))
        palette["minimum_contrast"] = .float(round(iTermProfilePreferences.double(forKey: KEY_MINIMUM_CONTRAST + suffix, inProfile: profile) * 1000.0) / 1000.0)
        palette["faint_text_alpha"] = .float(round(iTermProfilePreferences.double(forKey: KEY_FAINT_TEXT_ALPHA + suffix, inProfile: profile) * 1000.0) / 1000.0)
        return palette
    }
}
