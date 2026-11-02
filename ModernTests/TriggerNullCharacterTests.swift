//
//  TriggerNullCharacterTests.swift
//  iTerm2
//
//  Created by George Nachman on 3/31/26.
//

import XCTest
@testable import iTerm2SharedARC

final class TriggerNullCharacterTests: XCTestCase {

    /// Verify "\0" is a single null character, not an empty string.
    func testNullStringLiteralHasLengthOne() {
        let s = "\0" as NSString
        XCTAssertEqual(s.length, 1)
        XCTAssertEqual(s.character(at: 0), 0)
    }

    /// Verify stringByReplacingOccurrencesOfString handles embedded nulls.
    func testReplacingNullsWithSpaces() {
        // Build a string with embedded nulls: "\0Do\0you"
        let chars: [unichar] = [0, 0x44, 0x6F, 0, 0x79, 0x6F, 0x75]  // \0Do\0you
        let s = NSString(characters: chars, length: chars.count)
        XCTAssertEqual(s.length, 7)
        let replaced = s.replacingOccurrences(of: "\0", with: " ")
        XCTAssertEqual(replaced, " Do you")
    }

    /// Build an iTermStringLine from screen_char_t with null cells (simulating
    /// CUF-skipped positions) and verify the regex matches after null→space replacement.
    func testRegexMatchesStringLineWithNullsReplacedBySpaces() {
        // Simulate: \0Do\0you\0want\0to\0proceed?
        let text: [unichar] = Array(
            "\0Do\0you\0want\0to\0proceed?".unicodeScalars.map { UInt16($0.value) }
        )
        var screenChars = text.map { code -> screen_char_t in
            var c = screen_char_t()
            c.code = code
            return c
        }

        let stringLine = screenChars.withUnsafeMutableBufferPointer { buf in
            iTermStringLine(screenChars: buf.baseAddress!, length: Int(buf.count))!
        }

        // The raw string should contain nulls, not spaces.
        XCTAssertTrue(stringLine.stringValue.contains("\0"))
        XCTAssertFalse(stringLine.stringValue.contains(" "))

        // After replacing nulls with spaces, the regex should match.
        let cleaned = (stringLine.stringValue as NSString).replacingOccurrences(of: "\0", with: " ")
        let regex = try! NSRegularExpression(pattern: "Do you want to proceed")
        let matches = regex.numberOfMatches(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length))
        XCTAssertEqual(matches, 1)
    }

    /// Verify the regex does NOT match without the null→space replacement.
    func testRegexDoesNotMatchWithNulls() {
        let chars: [unichar] = Array(
            "\0Do\0you\0want\0to\0proceed?".unicodeScalars.map { UInt16($0.value) }
        )
        let s = NSString(characters: chars, length: chars.count) as String
        let regex = try! NSRegularExpression(pattern: "Do you want to proceed")
        let matches = regex.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        XCTAssertEqual(matches, 0, "Regex should not match when nulls are present instead of spaces")
    }
}

final class TriggerUntrustedDictTests: XCTestCase {
    private func notificationTriggerDict(regex: Any?) -> [String: Any] {
        var dict: [String: Any] = [
            "action": "AlertTrigger",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.eventNotificationPosted.rawValue)
        ]
        if let regex {
            dict["regex"] = regex
        }
        return dict
    }

    // An event trigger does not use its regex, so omitting it must not stop it from loading
    // or firing.
    func testEventTriggerWithoutRegexLoadsAndFires() {
        let evaluator = EventTriggerEvaluator(sessionDescription: "test")
        var fired: [[String]] = []
        evaluator.fireTriggerHandler = { _, captures, _ in
            fired.append(captures)
        }
        evaluator.loadFromProfileArray([notificationTriggerDict(regex: nil)])
        XCTAssertTrue(evaluator.hasNotificationPostedTrigger)
        evaluator.notificationPosted(messages: ["Hello"])
        XCTAssertEqual(fired, [["Hello"]])
    }

    // A regex trigger with no regex is treated like one saved from Settings with an empty
    // regex field, which is stored as "".
    func testRegexTriggerWithoutRegexGetsEmptyRegex() {
        let dict: [String: Any] = [
            "action": "AlertTrigger",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.regex.rawValue)
        ]
        guard let trigger = Trigger(fromUntrustedDict: dict) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(trigger.regex, "")
        XCTAssertEqual(trigger.dictionaryValue()["regex"] as? String, "")
    }

    // A regex of the wrong type is untrusted input and must be treated the same as a missing one.
    func testNonStringRegexGetsEmptyRegex() {
        guard let trigger = Trigger(fromUntrustedDict: notificationTriggerDict(regex: NSNumber(value: 5))) else {
            XCTFail("trigger should load")
            return
        }
        XCTAssertEqual(trigger.regex, "")
    }
}
