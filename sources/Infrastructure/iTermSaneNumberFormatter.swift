import Foundation

// Allows intermediate edits while leaving final number parsing to NumberFormatter.
@objc(iTermSaneNumberFormatter)
final class iTermSaneNumberFormatter: NumberFormatter, @unchecked Sendable {
    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        true
    }

    override func editingString(for object: Any) -> String? {
        if let number = object as? NSNumber {
            return number.stringValue
        }
        if let string = object as? String {
            return string
        }
        return super.editingString(for: object)
    }
}
