import Foundation

@objc(iTermAdditionalHotKeyObjectValue)
@objcMembers
final class iTermAdditionalHotKeyObjectValue: NSObject {
    dynamic var shortcut: iTermShortcut?
    dynamic var descriptorsInUseByOtherProfiles: [NSDictionary]?

    @objc(objectValueWithShortcut:inUseDescriptors:)
    static func objectValue(with shortcut: iTermShortcut?,
                            inUseDescriptors descriptors: [NSDictionary]?) -> iTermAdditionalHotKeyObjectValue {
        let value = iTermAdditionalHotKeyObjectValue()
        value.shortcut = shortcut
        value.descriptorsInUseByOtherProfiles = descriptors
        return value
    }

    dynamic var isDuplicate: Bool {
        guard let descriptor = shortcut?.descriptor else { return false }
        return descriptorsInUseByOtherProfiles?.contains { $0.isEqual(descriptor) } ?? false
    }
}
