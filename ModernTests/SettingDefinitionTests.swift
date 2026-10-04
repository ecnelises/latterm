import XCTest
@testable import iTerm2SharedARC

final class SettingDefinitionTests: XCTestCase {
    private func preserving(_ keys: [String], body: () throws -> Void) rethrows {
        let defaults = iTermUserDefaults.userDefaults()
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try body()
    }

    func testDefinitionsHaveUniqueKeysAndShareSearchMetadata() {
        XCTAssertGreaterThan(SettingDefinition.all.count, 400)
        XCTAssertEqual(Set(SettingDefinition.all.map(\.identifier)).count, SettingDefinition.all.count)
        for definition in SettingDefinition.all {
            XCTAssertTrue(SettingDefinition.definition(forIdentifier: definition.identifier) === definition)
            XCTAssertFalse(definition.title.isEmpty)
            XCTAssertFalse(definition.category.isEmpty)
            XCTAssertTrue(definition.searchText.contains(definition.identifier))
            if definition.valueType == Int(kiTermAdvancedSettingTypeIntEnum.rawValue) {
                XCTAssertTrue(definition.options.indices.contains((definition.factoryValue as! NSNumber).intValue))
            }
        }
        XCTAssertNil(SettingDefinition.definition(forIdentifier: "NoSuchSetting"))
    }

    func testValidationRejectsIncompleteNonfiniteAndOverflowingValues() throws {
        try preserving(["MinTabWidth", "TabAutoShowHoldTime", "AlternateMouseScrollStringForUp", "UseUnevenTabs"]) {
            let integer = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "MinTabWidth"))
            XCTAssertTrue(integer.writeText("72"))
            for text in ["", "-", "4.5", "nan", "2147483648", "-2147483649"] {
                XCTAssertFalse(integer.writeText(text), text)
                XCTAssertEqual(integer.currentValue as? NSNumber, 72)
            }
            XCTAssertFalse(integer.writeValue(Double.infinity))
            XCTAssertFalse(integer.writeValue(4.5))
            XCTAssertTrue(integer.writeText(" 2147483647 "))
            XCTAssertEqual(integer.currentValue as? NSNumber, NSNumber(value: Int32.max))
            XCTAssertTrue(integer.writeText("-2147483648"))
            XCTAssertEqual(integer.currentValue as? NSNumber, NSNumber(value: Int32.min))
            let floating = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "TabAutoShowHoldTime"))
            XCTAssertTrue(floating.writeText("1.25"))
            for text in ["", "nan", "inf", "1e999", "12px"] {
                XCTAssertFalse(floating.writeText(text))
                XCTAssertEqual(floating.currentValue as? NSNumber, 1.25)
            }
            let string = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "AlternateMouseScrollStringForUp"))
            XCTAssertTrue(string.writeText(""))
            XCTAssertEqual(string.currentValue as? String, "")
            XCTAssertFalse(string.writeValue(5))
            let boolean = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "UseUnevenTabs"))
            XCTAssertFalse(boolean.writeValue(2))
            XCTAssertFalse(boolean.writeValue(NSNull()))
        }
    }

    func testResetRemovesSavedDefaultAndRestoresFactorySource() throws {
        try preserving(["MinTabWidth"]) {
            let defaults = iTermUserDefaults.userDefaults()
            let definition = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "MinTabWidth"))
            XCTAssertTrue(definition.reset())
            XCTAssertFalse(definition.canReset)
            XCTAssertFalse(definition.isModified)
            XCTAssertEqual(definition.valueOrigin, NSLocalizedString("Factory default", comment: ""))
            XCTAssertNil(defaults.object(forKey: definition.identifier)) // Reading does not migrate/write.
            XCTAssertTrue(definition.writeValue(definition.factoryValue))
            XCTAssertTrue(definition.canReset) // Explicitly saving the default is still an override.
            XCTAssertFalse(definition.isModified)
            XCTAssertEqual(definition.valueOrigin, NSLocalizedString("Saved preference", comment: ""))
            XCTAssertTrue(definition.reset())
            XCTAssertNil(defaults.object(forKey: definition.identifier))
        }
    }

    func testOptionalSettingKeepsUnspecifiedDistinctFromFalse() throws {
        try preserving(["PreventEscapeSequenceFromClearingHistory"]) {
            let defaults = iTermUserDefaults.userDefaults()
            let definition = try XCTUnwrap(SettingDefinition.definition(forIdentifier: "PreventEscapeSequenceFromClearingHistory"))
            XCTAssertTrue(definition.writeValue(false))
            XCTAssertEqual(definition.currentValue as? NSNumber, NSNumber(value: false))
            XCTAssertTrue(definition.isModified)
            XCTAssertTrue(definition.writeValue(NSNull()))
            XCTAssertTrue(definition.currentValue is NSNull)
            XCTAssertFalse(definition.isModified)
            XCTAssertFalse(definition.canReset)
            XCTAssertNil(defaults.object(forKey: definition.identifier))
            XCTAssertTrue(definition.writeValue(true))
            XCTAssertTrue(definition.reset())
            XCTAssertTrue(definition.currentValue is NSNull)
        }
    }

    func testComputedResetClearsLegacyOverridesAndValidatesChoices() throws {
        let keys = ["NewInstanceOpenStyle", "OpenFileInNewWindows", "OpenFileInSplitPanes", "OpenFileInVerticalSplitPane"]
        try preserving(keys) {
            let defaults = iTermUserDefaults.userDefaults()
            let definition = try XCTUnwrap(SettingDefinition.definition(forIdentifier: keys[0]))
            defaults.set(-1, forKey: keys[0])
            for key in keys.dropFirst() { defaults.set(true, forKey: key) }
            XCTAssertEqual(definition.currentValue as? NSNumber, 0) // New window.
            XCTAssertEqual(definition.valueOrigin, NSLocalizedString("Legacy preference", comment: ""))
            for invalid in [-1, 4, 0.5, Double.infinity, "0"] as [Any] {
                XCTAssertFalse(definition.writeValue(invalid))
                XCTAssertEqual(defaults.object(forKey: keys[0]) as? NSNumber, -1)
            }
            XCTAssertTrue(definition.writeValue(definition.factoryValue))
            XCTAssertTrue(definition.canReset)
            XCTAssertFalse(definition.isModified)
            XCTAssertEqual(definition.valueOrigin, NSLocalizedString("Saved preference", comment: ""))
            XCTAssertTrue(definition.reset())
            for key in keys { XCTAssertNil(defaults.object(forKey: key)) }
            XCTAssertEqual(iTermAdvancedSettingsModel.newInstanceOpenStyle(), (definition.factoryValue as! NSNumber).int32Value)
            XCTAssertFalse(definition.canReset)
            XCTAssertEqual(definition.valueOrigin, NSLocalizedString("Factory default", comment: ""))
        }
    }
}
