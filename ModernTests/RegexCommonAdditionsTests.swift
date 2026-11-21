//
//  RegexCommonAdditionsTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class RegexCommonAdditionsTests: XCTestCase {
    func testIsMatchedAndRangeOfRegex() {
        let hex = "0A 1f FF\n" as NSString
        XCTAssertTrue(hex.isMatched(byRegex: #"^[0-9A-Fa-f\s]+$"#))
        XCTAssertFalse(("0G 1f" as NSString).isMatched(byRegex: #"^[0-9A-Fa-f\s]+$"#))

        let sample = "error at foo.swift:42:17" as NSString
        XCTAssertEqual(sample.matching(#":(\d+):(\d+)"#), ":42:17")
        XCTAssertEqual(sample.matching(#":(\d+):(\d+)"#, capture: 1), "42")
        XCTAssertEqual(sample.matching(#":(\d+):(\d+)"#, capture: 2), "17")
        XCTAssertNil(sample.matching(#":(\d+):(\d+)"#, capture: 3))
    }

    func testCaptureComponentsPreservesOptionalUnmatchedGroups() {
        let layoutWithPane = "132x40,0,0,7" as NSString
        let capsWithPane = layoutWithPane.captureComponentsMatched(
            byRegex: #"([0-9]+)x([0-9]+),([0-9]+),([0-9]+),?([0-9]+)?"#
        )
        XCTAssertEqual(capsWithPane, ["132x40,0,0,7", "132", "40", "0", "0", "7"])

        let layoutWithoutPane = "132x40,0,0" as NSString
        let capsWithoutPane = layoutWithoutPane.captureComponentsMatched(
            byRegex: #"([0-9]+)x([0-9]+),([0-9]+),([0-9]+),?([0-9]+)?"#
        )
        XCTAssertEqual(capsWithoutPane, ["132x40,0,0", "132", "40", "0", "0", ""])

        let unmatched = layoutWithoutPane.captureComponentsMatched(byRegex: #"^%window-add @(\d+)$"#)
        XCTAssertEqual(unmatched, [])
    }

    func testReplacingAndSplittingSemantics() {
        let escaped = #"path\ with\ \(spaces\)"# as NSString
        let unescaped = escaped.replacingOccurrences(ofRegex: #"\\([ \(\[\]\\\)])"#, with: "$1")
        XCTAssertEqual(unescaped, "path with (spaces)")

        let singleLineWithTrailingNewline = "ls -la\n" as NSString
        XCTAssertEqual(
            singleLineWithTrailingNewline.components(separatedByRegex: #"(?:\r\n)|(?:\r)|(?:\n)"#),
            ["ls -la"]
        )

        let multiLine = "echo 1\r\n\necho 2\n" as NSString
        XCTAssertEqual(
            multiLine.components(separatedByRegex: #"(?:\r\n)|(?:\r)|(?:\n)"#),
            ["echo 1", "", "echo 2"]
        )

        let ctrl = "a\u{0003}b\u{007f}c" as NSString
        XCTAssertEqual(ctrl.replacingControlCharactersWithCaretLetter(), "a^Cb^?c")
    }
}
