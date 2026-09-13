import XCTest
@testable import iTerm2SharedARC

final class SaneNumberFormatterTests: XCTestCase {
    func testIntermediateEditsAreAllowedWithoutReplacingTextOrError() {
        let formatter = iTermSaneNumberFormatter()
        for input in ["", "-", "+", ".", "1.", "1e-", "1,", "not yet a number"] {
            var replacement: NSString? = "unchanged replacement"
            var error: NSString? = "unchanged error"
            XCTAssertTrue(formatter.isPartialStringValid(input,
                                                        newEditingString: &replacement,
                                                        errorDescription: &error), input)
            XCTAssertEqual(replacement, "unchanged replacement")
            XCTAssertEqual(error, "unchanged error")
        }
        XCTAssertTrue(formatter.isPartialStringValid("-", newEditingString: nil, errorDescription: nil))
    }

    func testEditingIntegersPreservesFullPrecisionAndBooleanValues() {
        let formatter = iTermSaneNumberFormatter()
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: Int64.min)), "-9223372036854775808")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: UInt64.max)), "18446744073709551615")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 0)), "0")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: true)), "1")
    }

    func testEditingNumbersBypassesDisplayRoundingAndGrouping() {
        let formatter = iTermSaneNumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = NSDecimalNumber(string: "1234.56789")
        XCTAssertEqual(formatter.string(from: number), "1,234.57")
        XCTAssertEqual(formatter.editingString(for: number), "1234.56789")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: -1.5)), "-1.5")
    }

    func testExistingTextIsPreservedVerbatim() {
        let formatter = iTermSaneNumberFormatter()
        for text in ["", "00012", "  -1.20 ", "1,25", "未完成"] {
            XCTAssertEqual(formatter.editingString(for: text), text)
            XCTAssertEqual(formatter.editingString(for: text as NSString), text)
        }
    }

    func testOtherObjectsUseFoundationFallback() {
        let formatter = iTermSaneNumberFormatter()
        let baseline = NumberFormatter()
        let object = NSObject()
        XCTAssertEqual(formatter.editingString(for: object), baseline.editingString(for: object))
    }

    func testFinalParsingStillUsesNumberFormatterRules() {
        let formatter = iTermSaneNumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        XCTAssertEqual(formatter.number(from: "1234.5"), NSNumber(value: 1234.5))
        XCTAssertNil(formatter.number(from: "not a number"))
        XCTAssertNil(formatter.number(from: "-"))
    }

    func testArchivePreservesRuntimeClassAndFormatterConfiguration() throws {
        XCTAssertTrue(NSClassFromString("iTermSaneNumberFormatter") === iTermSaneNumberFormatter.self)
        let formatter = iTermSaneNumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        // NumberFormatter supports NSCoding, not NSSecureCoding, as did the old subclass.
        let data = try NSKeyedArchiver.archivedData(withRootObject: formatter, requiringSecureCoding: false)
        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = false
        defer { decoder.finishDecoding() }
        let decoded = try XCTUnwrap(decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
                                    as? iTermSaneNumberFormatter)
        XCTAssertEqual(decoded.minimumFractionDigits, 2)
        XCTAssertEqual(decoded.maximumFractionDigits, 2)
        XCTAssertEqual(decoded.numberStyle, .decimal)
        XCTAssertEqual(decoded.string(from: NSNumber(value: 1.5)), "1.50")
        XCTAssertEqual(decoded.editingString(for: NSNumber(value: 1.5)), "1.5")
        XCTAssertTrue(decoded.isPartialStringValid("-", newEditingString: nil, errorDescription: nil))
    }
}
