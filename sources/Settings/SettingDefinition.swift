import Foundation

/// Adapts the existing macro definitions without duplicating their preference
/// keys or defaults. Editors and search share this presentation and validation.
@objc(iTermSettingDefinition)
@objcMembers
final class SettingDefinition: NSObject {
    static let all: [SettingDefinition] = {
        var result: [SettingDefinition] = []
        iTermAdvancedSettingsModel.enumerateDictionaries { dictionary in
            guard let dictionary else { return }
            result.append(SettingDefinition(dictionary: dictionary))
        }
        it_assert(Set(result.map(\.identifier)).count == result.count, "Setting identifiers must be unique")
        return result.sorted { $0.sourceDescription < $1.sourceDescription }
    }()
    private static let byIdentifier = Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })

    static func definition(forIdentifier identifier: String) -> SettingDefinition? { byIdentifier[identifier] }

    let dictionary: [AnyHashable: Any]
    let identifier: String
    let valueType: Int
    let factoryValue: Any
    let sourceDescription: String
    let category: String
    let localizedDescription: String
    let options: [String]
    private let resetKeys: [String]

    private init(dictionary: [AnyHashable: Any]) {
        self.dictionary = dictionary
        identifier = dictionary[kAdvancedSettingIdentifier] as! String
        valueType = (dictionary[kAdvancedSettingType] as! NSNumber).intValue
        factoryValue = dictionary[kAdvancedSettingDefaultValue]!
        let description = dictionary[kAdvancedSettingDescription] as! String
        sourceDescription = description
        let separator = description.range(of: ": ")
        let rawCategory = separator.map { String(description[..<$0.lowerBound]) } ?? "Advanced"
        category = NSLocalizedString(rawCategory, comment: "Advanced setting category")
        let body = separator.map { String(description[$0.upperBound...]) } ?? description
        localizedDescription = Self.localizeDescription(body)
        options = (dictionary[kAdvancedSettingOptions] as? [String] ?? []).map {
            NSLocalizedString($0, comment: "Advanced setting option")
        }
        resetKeys = dictionary[kAdvancedSettingResetKeys] as? [String] ?? []
        super.init()
    }

    private static func localizeDescription(_ text: String) -> String {
        let localized = NSLocalizedString(text, comment: "Advanced setting description")
        if localized != text { return localized }
        return text.components(separatedBy: "\n").map {
            NSLocalizedString($0, comment: "Advanced setting description")
        }.joined(separator: "\n")
    }

    var title: String { localizedDescription.components(separatedBy: "\n").first ?? localizedDescription }
    var searchText: String { [identifier, sourceDescription, category, localizedDescription].joined(separator: " ") }
    var currentValue: Any { iTermAdvancedSettingsModel.value(forSetting: dictionary)! }
    var isSecure: Bool { dictionary[kAdvancedSettingSetter] != nil }
    var isModified: Bool {
        if let lhs = currentValue as? NSNumber, let rhs = factoryValue as? NSNumber {
            if lhs.doubleValue == rhs.doubleValue { return false }
            if !lhs.doubleValue.isFinite || !rhs.doubleValue.isFinite { return true }
            return abs(lhs.doubleValue - rhs.doubleValue) > 0.0001
        }
        return !(currentValue as AnyObject).isEqual(factoryValue)
    }
    var canReset: Bool {
        if isSecure { return isModified }
        return ([identifier] + resetKeys).contains { iTermUserDefaults.userDefaults().object(forKey: $0) != nil }
    }
    var valueOrigin: String {
        if isSecure { return NSLocalizedString("Protected preference", comment: "Setting value origin") }
        let defaults = iTermUserDefaults.userDefaults()
        if let value = defaults.object(forKey: identifier) {
            // An invalid computed enum falls back to the legacy keys too.
            let index = (value as? NSNumber)?.intValue ?? (value as? NSString)?.integerValue ?? -1
            if resetKeys.isEmpty || options.indices.contains(index) {
                return NSLocalizedString("Saved preference", comment: "Setting value origin")
            }
        }
        if resetKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
            return NSLocalizedString("Legacy preference", comment: "Setting value origin")
        }
        return NSLocalizedString("Factory default", comment: "Setting value origin")
    }
    var displayValue: String { display(currentValue) }
    var defaultDisplayValue: String { display(factoryValue) }
    private func display(_ value: Any) -> String {
        if value is NSNull { return NSLocalizedString("Unspecified", comment: "Advanced setting value") }
        if let number = value as? NSNumber {
            if valueType == Int(kiTermAdvancedSettingTypeBoolean.rawValue) ||
                valueType == Int(kiTermAdvancedSettingTypeOptionalBoolean.rawValue) {
                return number.boolValue ? NSLocalizedString("Yes", comment: "Advanced setting value") :
                    NSLocalizedString("No", comment: "Advanced setting value")
            }
            if valueType == Int(kiTermAdvancedSettingTypeIntEnum.rawValue), options.indices.contains(number.intValue) {
                return options[number.intValue]
            }
        }
        return String(describing: value)
    }

    /// Reject incomplete, nonfinite, overflowing, and out-of-choice values
    /// before writing. Arbitrary strings remain valid, including empty strings.
    func parsedValue(forText text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch valueType {
        case Int(kiTermAdvancedSettingTypeString.rawValue): return text
        case Int(kiTermAdvancedSettingTypeFloat.rawValue):
            guard let value = Double(trimmed), value.isFinite else { return nil }
            return NSNumber(value: value)
        case Int(kiTermAdvancedSettingTypeInteger.rawValue):
            guard let value = Int32(trimmed) else { return nil }
            return NSNumber(value: value)
        default: return nil
        }
    }
    func writeText(_ text: String) -> Bool {
        guard let value = parsedValue(forText: text) else { return false }
        return writeValue(value)
    }
    func writeValue(_ value: Any) -> Bool {
        switch valueType {
        case Int(kiTermAdvancedSettingTypeString.rawValue):
            guard value is String else { return false }
        case Int(kiTermAdvancedSettingTypeOptionalBoolean.rawValue) where value is NSNull:
            break
        default:
            guard let number = value as? NSNumber, number.doubleValue.isFinite else { return false }
            switch valueType {
            case Int(kiTermAdvancedSettingTypeBoolean.rawValue), Int(kiTermAdvancedSettingTypeOptionalBoolean.rawValue):
                guard number.doubleValue == 0 || number.doubleValue == 1 else { return false }
            case Int(kiTermAdvancedSettingTypeInteger.rawValue):
                guard number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max),
                      number.doubleValue.rounded() == number.doubleValue else { return false }
            case Int(kiTermAdvancedSettingTypeIntEnum.rawValue):
                guard number.doubleValue >= 0, number.doubleValue < Double(options.count),
                      number.doubleValue.rounded() == number.doubleValue else { return false }
            case Int(kiTermAdvancedSettingTypeFloat.rawValue): break
            default: return false
            }
        }
        return iTermAdvancedSettingsModel.writeValue(value, forSetting: dictionary)
    }
    func reset() -> Bool { iTermAdvancedSettingsModel.resetSetting(dictionary) }
}
