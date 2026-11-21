//
//  DeclarativeConfigTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class DeclarativeConfigTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var savedGlobalKeyMap: [AnyHashable: Any] = [:]
    private var savedPrefs: [String: Any?] = [:]
    private var savedDefaultGuid: String?
    private var createdProfileGuids: [String] = []

    private let trackedPrefKeys: [String] = [
        kPreferenceKeyTabStyle,
        kPreferenceKeyTabPosition,
        kPreferenceKeyStatusBarPosition,
        kPreferenceKeyHideTabBar,
        kPreferenceKeyHideTabNumber,
        kPreferenceKeyTabsHaveCloseButton,
        kPreferenceKeySideMargins,
        kPreferenceKeyTopBottomMargins,
        kPreferenceKeyDimmingAmount,
        kPreferenceKeyQuitWhenAllWindowsClosed,
        kPreferenceKeySelectionCopiesText,
        kPreferenceKeyCopyLastNewline,
        kPreferenceKeyCharactersConsideredPartOfAWordForSelection,
        kPreferenceKeyUseMetal
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = ITAddressBookMgr.sharedInstance()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LattermDeclarativeConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        savedGlobalKeyMap = iTermKeyMappings.globalKeyMap()
        let defaults = iTermUserDefaults.userDefaults()
        for key in trackedPrefKeys {
            savedPrefs[key] = defaults.object(forKey: key)
        }
        savedDefaultGuid = ProfileModel.sharedInstance()?.defaultBookmark()?[KEY_GUID] as? String
        createdProfileGuids = []
    }

    override func tearDownWithError() throws {
        iTermKeyMappings.setGlobalKeyMap(savedGlobalKeyMap)
        let defaults = iTermUserDefaults.userDefaults()
        for (key, value) in savedPrefs {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        if let model = ProfileModel.sharedInstance() {
            for guid in createdProfileGuids where model.bookmark(withGuid: guid) != nil {
                model.removeProfile(withGuid: guid)
            }
            if let savedDefaultGuid, model.bookmark(withGuid: savedDefaultGuid) != nil {
                model.setDefaultByGuid(savedDefaultGuid)
            }
            model.flush()
        }
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        try super.tearDownWithError()
    }

    func testTOMLParserPrimitivesCommentsAndNestedTables() throws {
        let toml = """
        # Top-level comment
        title = "Latterm \\u2728"
        literal_path = 'C:\\raw\\path'
        multiline = \"\"\"
        first line
        second line\"\"\"
        hex_num = 0x1A_2B
        bin_num = 0b1010_0101
        oct_num = 0o755
        opacity = 0.85 # inline comment
        enabled = true
        dotted.alpha.beta = 42

        [appearance]
        theme = "minimal"
        margins = { side = 8, vertical = 6 }

        [[profiles]]
        name = "Developer"

        [profiles.font]
        family = "Menlo"
        size = 13.5

        [[profiles.font.language_rules]]
        script = "zh-Hans"
        family = "PingFang SC"
        scale_percent = 105
        """

        let parsed = try TOMLCodec.parse(toml)
        XCTAssertEqual(parsed.string("title"), "Latterm \u{2728}")
        XCTAssertEqual(parsed.string("literal_path"), #"C:\raw\path"#)
        XCTAssertEqual(parsed.string("multiline"), "first line\nsecond line")
        XCTAssertEqual(parsed.int("hex_num"), 0x1A2B)
        XCTAssertEqual(parsed.int("bin_num"), 0b10100101)
        XCTAssertEqual(parsed.int("oct_num"), 0o755)
        XCTAssertEqual(parsed.double("opacity") ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(parsed.bool("enabled"), true)
        XCTAssertEqual(parsed.table("dotted")?.table("alpha")?.int("beta"), 42)
        XCTAssertEqual(parsed.table("appearance")?.string("theme"), "minimal")
        XCTAssertEqual(parsed.table("appearance")?.table("margins")?.int("side"), 8)

        let profiles = try XCTUnwrap(parsed.tableArray("profiles"))
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].string("name"), "Developer")
        XCTAssertEqual(profiles[0].table("font")?.string("family"), "Menlo")
        XCTAssertEqual(profiles[0].table("font")?.double("size"), 13.5)
        let rules = try XCTUnwrap(profiles[0].table("font")?.tableArray("language_rules"))
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].string("script"), "zh-Hans")
        XCTAssertEqual(rules[0].string("family"), "PingFang SC")
        XCTAssertEqual(rules[0].int("scale_percent"), 105)
    }

    func testTOMLParserSyntaxErrorReportsLineAndColumn() {
        let broken = """
        [appearance]
        theme = "minimal"
        side_margins = 12_
        """
        XCTAssertThrowsError(try TOMLCodec.parse(broken)) { error in
            guard case let TOMLError.syntaxError(line, column, _) = error else {
                XCTFail("Expected TOMLError.syntaxError, got \(error)")
                return
            }
            XCTAssertEqual(line, 3)
            XCTAssertGreaterThan(column, 1)
        }
    }

    func testTOMLEncodeDecodeRoundTrip() throws {
        var original = TOMLTable()
        var appearance = TOMLTable()
        appearance["theme"] = .string("compact")
        appearance["side_margins"] = .integer(10)
        appearance["dim_amount"] = .float(0.25)
        appearance["always_show_tab_bar"] = .boolean(true)
        original["appearance"] = .table(appearance)

        var profile = TOMLTable()
        profile["name"] = .string("Test Profile")
        profile["tags"] = .array([.string("work"), .string("rust")])
        var colors = TOMLTable()
        colors["foreground"] = .string("#d4d4d4")
        colors["ansi"] = .array((0..<16).map { .string(String(format: "#%02x1122", $0 * 16)) })
        profile["colors"] = .table(colors)
        original["profiles"] = .array([.table(profile)])

        let encoded = TOMLCodec.encode(original, headerComment: "Generated test file")
        let reparsed = try TOMLCodec.parse(encoded)
        XCTAssertEqual(reparsed, original)
    }

    func testApplyAndExportDeclarativeConfigRoundTrip() throws {
        let configURL = tempDirectoryURL.appendingPathComponent("config.toml")
        let manager = DeclarativeConfigManager(configURL: configURL, debounceInterval: 0.05)
        let testGuid = "A7230099-DEAD-BEEF-CAFE-000000000001"
        createdProfileGuids.append(testGuid)

        let inputTOML = """
        [appearance]
        theme = "minimal"
        tab_bar_location = "bottom"
        status_bar_location = "bottom"
        always_show_tab_bar = true
        show_tab_numbers = false
        side_margins = 14
        top_bottom_margins = 8
        dim_amount = 0.3

        [behavior]
        quit_when_all_windows_closed = true
        copy_on_select = true
        copy_trailing_newline = false
        word_characters = "/-+._~"
        gpu_rendering = true

        [[keybindings]]
        key = "cmd+shift+k"
        action = "send_text"
        parameter = "clear\\n"

        [[keybindings]]
        key = "opt+left"
        action = "send_escape_sequence"
        parameter = "b"

        [[profiles]]
        name = "TOML Test Profile"
        guid = "\(testGuid)"
        default = true
        tags = ["toml", "dev"]
        command = "/bin/zsh -l"
        working_directory = "reuse"

        [profiles.font]
        family = "Menlo"
        size = 14.0
        ligatures = true
        powerline_glyphs = true
        horizontal_spacing = 1.05
        vertical_spacing = 1.1

        [[profiles.font.language_rules]]
        script = "zh-Hans"
        family = "PingFang SC"
        scale_percent = 105
        baseline_offset = -0.5
        enabled = true

        [profiles.cursor]
        style = "vertical"
        blink = true
        smooth_slide = true

        [profiles.window]
        columns = 132
        rows = 40
        transparency = 0.12
        blur = true
        blur_radius = 18.0
        show_status_bar = true

        [profiles.terminal]
        scrollback_lines = 50000
        unlimited_scrollback = false
        term = "xterm-256color"
        option_as_alt = "esc+"
        right_option_as_alt = "normal"

        [profiles.colors]
        separate_light_dark = true
        foreground = "#cdd6f4"
        background = "#1e1e2e"
        selection = "#585b7080"
        cursor = "#f5e0dc"
        black = "#45475a"
        red = "#f38ba8"

        [profiles.colors.light]
        foreground = "#4c4f69"
        background = "#eff1f5"

        [profiles.colors.dark]
        foreground = "#cdd6f4"
        background = "#1e1e2e"
        """

        try manager.applyTOMLString(inputTOML)

        XCTAssertEqual(iTermPreferences.int(forKey: kPreferenceKeyTabStyle), iTermPreferencesTabStyle.TAB_STYLE_MINIMAL.rawValue)
        XCTAssertEqual(iTermPreferences.int(forKey: kPreferenceKeyTabPosition), PSMTabPosition.bottomTab.rawValue)
        XCTAssertFalse(iTermPreferences.bool(forKey: kPreferenceKeyHideTabBar))
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyHideTabNumber))
        XCTAssertEqual(iTermPreferences.int(forKey: kPreferenceKeySideMargins), 14)
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeyQuitWhenAllWindowsClosed))
        XCTAssertTrue(iTermPreferences.bool(forKey: kPreferenceKeySelectionCopiesText))
        XCTAssertEqual(iTermPreferences.string(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection), "/-+._~")

        let keystrokes = iTermKeyMappings.sortedGlobalKeystrokes()
        XCTAssertEqual(keystrokes.count, 2)
        let cmdShiftK = try DeclarativeConfigManager.parseKeystroke("cmd+shift+k")
        let boundAction = iTermKeyMappings.action(for: cmdShiftK, keyMappings: nil)
        XCTAssertEqual(boundAction?.keyAction, .ACTION_TEXT)
        XCTAssertEqual(boundAction?.parameter, "clear\n")

        let model = try XCTUnwrap(ProfileModel.sharedInstance())
        let storedProfile = try XCTUnwrap(model.bookmark(withGuid: testGuid))
        XCTAssertEqual(model.defaultBookmark()?[KEY_GUID] as? String, testGuid)
        XCTAssertEqual(storedProfile[KEY_NAME] as? String, "TOML Test Profile")
        XCTAssertEqual(storedProfile[KEY_COMMAND_LINE] as? String, "/bin/zsh -l")
        XCTAssertEqual(iTermProfilePreferences.int(forKey: KEY_COLUMNS, inProfile: storedProfile), 132)
        XCTAssertEqual(iTermProfilePreferences.int(forKey: KEY_ROWS, inProfile: storedProfile), 40)
        XCTAssertEqual(iTermProfilePreferences.int(forKey: KEY_CURSOR_TYPE, inProfile: storedProfile), Int32(ITermCursorType.CURSOR_VERTICAL.rawValue))
        XCTAssertTrue(iTermProfilePreferences.bool(forKey: KEY_CURSOR_SMOOTH_SLIDE, inProfile: storedProfile))
        XCTAssertEqual(iTermProfilePreferences.int(forKey: KEY_OPTION_KEY_SENDS, inProfile: storedProfile), iTermOptionKeyBehavior.OPT_ESC.rawValue)

        XCTAssertEqual(DeclarativeConfigManager.formatHexColorDictionary(storedProfile[KEY_FOREGROUND_COLOR]), "#cdd6f4")
        XCTAssertEqual(DeclarativeConfigManager.formatHexColorDictionary(storedProfile[KEY_SELECTION_COLOR]), "#585b7080")
        XCTAssertEqual(DeclarativeConfigManager.formatHexColorDictionary(storedProfile[KEY_ANSI_1_COLOR]), "#f38ba8")
        XCTAssertEqual(
            DeclarativeConfigManager.formatHexColorDictionary(storedProfile[KEY_BACKGROUND_COLOR + COLORS_LIGHT_MODE_SUFFIX]),
            "#eff1f5"
        )

        let fontConfigRaw = try XCTUnwrap(storedProfile[KEY_FONT_CONFIG] as? String)
        let fontConfig = try XCTUnwrap(FontTable.Config(string: fontConfigRaw))
        XCTAssertEqual(fontConfig.languageRules.count, 1)
        XCTAssertEqual(fontConfig.languageRules[0].script, .chineseSimplified)
        XCTAssertEqual(fontConfig.languageRules[0].fontName, "PingFang SC")
        XCTAssertEqual(fontConfig.languageRules[0].scalePercent, 105)

        // Export current settings to config.toml and verify re-parsing succeeds and preserves profile
        try manager.exportCurrentSettings()
        XCTAssertTrue(manager.configFileExists)
        let exportedContent = try String(contentsOf: configURL, encoding: .utf8)
        let reparsed = try TOMLCodec.parse(exportedContent)
        let exportedProfiles = try XCTUnwrap(reparsed.tableArray("profiles"))
        let exportedMatch = try XCTUnwrap(exportedProfiles.first(where: { $0.string("guid") == testGuid }))
        XCTAssertEqual(exportedMatch.table("window")?.int("columns"), 132)
        XCTAssertEqual(exportedMatch.table("colors")?.string("selection"), "#585b7080")
        XCTAssertEqual(exportedMatch.table("colors")?.table("light")?.string("background"), "#eff1f5")
    }

    func testLiveHotReloadOnDirectWriteAndAtomicRename() throws {
        let configURL = tempDirectoryURL.appendingPathComponent("config.toml")
        let manager = DeclarativeConfigManager(configURL: configURL, debounceInterval: 0.04)
        manager.startWatching()
        defer { manager.stopWatching() }

        let firstReload = expectation(description: "Initial file creation triggers hot reload")
        var observerToken: NSObjectProtocol?
        observerToken = NotificationCenter.default.addObserver(
            forName: DeclarativeConfigManager.didChangeNotification,
            object: manager,
            queue: .main
        ) { _ in
            if manager.lastLoadedAt != nil && iTermPreferences.int(forKey: kPreferenceKeySideMargins) == 19 {
                if let observerToken {
                    NotificationCenter.default.removeObserver(observerToken)
                }
                firstReload.fulfill()
            }
        }

        let initialContent = """
        [appearance]
        side_margins = 19
        """
        try Data(initialContent.utf8).write(to: configURL, options: .withoutOverwriting)
        wait(for: [firstReload], timeout: 3.0)
        XCTAssertEqual(iTermPreferences.int(forKey: kPreferenceKeySideMargins), 19)

        // Now simulate Vim/Zed atomic save-by-rename (`write(to:atomically:true)`)
        let secondReload = expectation(description: "Atomic rename save triggers hot reload")
        observerToken = NotificationCenter.default.addObserver(
            forName: DeclarativeConfigManager.didChangeNotification,
            object: manager,
            queue: .main
        ) { _ in
            if iTermPreferences.int(forKey: kPreferenceKeySideMargins) == 27 {
                if let observerToken {
                    NotificationCenter.default.removeObserver(observerToken)
                }
                secondReload.fulfill()
            }
        }

        let updatedContent = """
        [appearance]
        side_margins = 27
        """
        try updatedContent.write(to: configURL, atomically: true, encoding: .utf8)
        wait(for: [secondReload], timeout: 3.0)
        XCTAssertEqual(iTermPreferences.int(forKey: kPreferenceKeySideMargins), 27)
    }

    func testDefaultConfigURLHonorsEnvironmentOverrides() {
        let customPathURL = DeclarativeConfigManager.defaultConfigURL(environment: [
            "LATTERM_CONFIG_PATH": "/tmp/custom-latterm.toml"
        ])
        XCTAssertEqual(customPathURL.path, "/tmp/custom-latterm.toml")

        let xdgURL = DeclarativeConfigManager.defaultConfigURL(environment: [
            "XDG_CONFIG_HOME": "/tmp/xdg-home"
        ])
        XCTAssertTrue(xdgURL.path.hasPrefix("/tmp/xdg-home/latterm"))
        XCTAssertEqual(xdgURL.lastPathComponent, "config.toml")
    }
}
