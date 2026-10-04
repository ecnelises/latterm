import XCTest
@testable import iTerm2SharedARC

final class ProfileSettingTests: XCTestCase {
    private func preserving(_ keys: [String], body: () throws -> Void) rethrows {
        let defaults = iTermUserDefaults.userDefaults()
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        }
        try body()
    }

    func testFactoryBaselineUsesPresetColorsAndNewProfileUnicode() throws {
        XCTAssertEqual(iTermProfilePreferences.factoryObject(forKey: KEY_UNICODE_VERSION) as? NSNumber, 9)
        XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_UNICODE_VERSION, inProfile: [:]) as? NSNumber, 9)
        let color = try XCTUnwrap(iTermProfilePreferences.factoryObject(forKey: KEY_FOREGROUND_COLOR) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(color["Red Component"] as? Double), 0.0627451, accuracy: 0.00001)
        XCTAssertNotEqual(NSDictionary(dictionary: color), iTermProfilePreferences.defaultObject(forKey: KEY_FOREGROUND_COLOR) as? NSDictionary)
        XCTAssertNotEqual(iTermProfilePreferences.factoryObject(forKey: KEY_FOREGROUND_COLOR + " (Dark)") as? NSDictionary,
                          iTermProfilePreferences.factoryObject(forKey: KEY_FOREGROUND_COLOR + " (Light)") as? NSDictionary)
    }

    func testExplicitFalseZeroAndEmptyValuesWinOverFallbacksWithoutMigration() {
        preserving(["AntiIdleTimerPeriod", "OptionIsMetaForSpecialChars"]) {
            let defaults = iTermUserDefaults.userDefaults()
            defaults.set(123, forKey: "AntiIdleTimerPeriod")
            defaults.set(false, forKey: "OptionIsMetaForSpecialChars")
            let profile: [AnyHashable: Any] = [KEY_IDLE_PERIOD: 0, KEY_TREAT_OPTION_AS_ALT: false, KEY_COMMAND_LINE: ""]
            XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_IDLE_PERIOD, inProfile: profile) as? NSNumber, 0)
            XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_TREAT_OPTION_AS_ALT, inProfile: profile) as? NSNumber, false)
            XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_COMMAND_LINE, inProfile: profile) as? String, "")
            for key in [KEY_IDLE_PERIOD, KEY_TREAT_OPTION_AS_ALT, KEY_COMMAND_LINE] {
                XCTAssertEqual(iTermProfilePreferences.valueSource(forKey: key, inProfile: profile), NSLocalizedString("Saved profile value", comment: ""))
            }
            XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_IDLE_PERIOD, inProfile: [:]) as? NSNumber, 123)
            XCTAssertTrue(iTermProfilePreferences.valueSource(forKey: KEY_IDLE_PERIOD, inProfile: [:]).contains("AntiIdleTimerPeriod"))
            XCTAssertEqual(defaults.object(forKey: "AntiIdleTimerPeriod") as? NSNumber, 123)
            XCTAssertEqual(profile.count, 3)
        }
    }

    func testLegacyAndExpertSourcesKeepFactoryValuesIndependentOfOverrides() throws {
        try preserving(["BadgeTopMargin", "BadgeFont", "BadgeFontIsBold"]) {
            let defaults = iTermUserDefaults.userDefaults()
            defaults.set(87, forKey: "BadgeTopMargin")
            defaults.set("Monaco", forKey: "BadgeFont")
            defaults.set(false, forKey: "BadgeFontIsBold")
            iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
            let legacy: [AnyHashable: Any] = [KEY_USE_HFS_PLUS_MAPPING: true, KEY_SHOW_TIMESTAMPS: 2]
            XCTAssertTrue(iTermProfilePreferences.valueSource(forKey: KEY_UNICODE_NORMALIZATION, inProfile: legacy).contains(KEY_USE_HFS_PLUS_MAPPING))
            XCTAssertTrue(iTermProfilePreferences.valueSource(forKey: KEY_TIMESTAMPS_VISIBLE, inProfile: legacy).contains(KEY_SHOW_TIMESTAMPS))
            XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_BADGE_TOP_MARGIN, inProfile: [:]) as? NSNumber, 87)
            XCTAssertEqual(iTermProfilePreferences.factoryObject(forKey: KEY_BADGE_TOP_MARGIN) as? NSNumber, 10)
            XCTAssertEqual(iTermProfilePreferences.valueSource(forKey: KEY_BADGE_TOP_MARGIN, inProfile: [:]), NSLocalizedString("Expert setting fallback", comment: ""))
            let font = try XCTUnwrap(iTermProfilePreferences.factoryObject(forKey: KEY_BADGE_FONT) as? String)
            XCTAssertNotEqual(font, "Monaco")
            XCTAssertEqual(defaults.object(forKey: "BadgeTopMargin") as? NSNumber, 87)
        }
    }

    func testEntrySearchBindingAndEmptyStringPresentation() {
        let owner = iTermProfilePreferencesBaseViewController(nibName: nil, bundle: nil)
        let info = PreferenceInfo()
        info.key = KEY_COMMAND_LINE
        info.type = .stringTextField
        info.control = NSTextField()
        let document = iTermPreferencesSearchDocument(displayName: "命令 Command", identifier: KEY_COMMAND_LINE, keywordPhrases: [])
        let setting = iTermSetting(info: info, isProfile: true, pathComponents: ["通用", "命令"])
        let entry = ProfileSettingEntry(setting: setting, owner: owner, document: document)
        XCTAssertTrue(entry.matches("通用 command"))
        XCTAssertTrue(entry.matches(KEY_COMMAND_LINE))
        XCTAssertFalse(entry.matches("unrelated"))
        XCTAssertEqual(entry.displayValue(in: [KEY_COMMAND_LINE: ""]), NSLocalizedString("Empty string", comment: ""))
        let bound: [AnyHashable: Any] = [KEY_COMMAND_LINE: "", KEY_BINDINGS: [KEY_COMMAND_LINE: "session.name"]]
        XCTAssertTrue(entry.isDifferent(in: bound))
        XCTAssertEqual(entry.displayValue(in: bound), "session.name")
        XCTAssertEqual(entry.source(in: bound), NSLocalizedString("Expression binding", comment: ""))
        XCTAssertEqual(bound[KEY_COMMAND_LINE] as? String, "")
        info.type = .passwordTextField
        XCTAssertEqual(entry.displayValue(in: bound), NSLocalizedString("Hidden", comment: ""))
    }

    func testUnsetOptionalValuesRemainNilAcrossTheSwiftBridge() {
        XCTAssertNil(iTermProfilePreferences.object(forKey: KEY_SHORTCUT, inProfile: [:]))
        XCTAssertNil(iTermProfilePreferences.object(forKey: "No Such Profile Setting", inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.factoryObject(forKey: KEY_SHORTCUT) as? String, "")
    }
}
