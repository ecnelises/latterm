import XCTest
@testable import iTerm2SharedARC

final class PTYSessionObjectMethodsCoordinatorTests: XCTestCase {
    func testAnnotationRangeValidatorAcceptsValidSingleAndMultiLineRanges() {
        XCTAssertTrue(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 0, endX: 0, endY: 0, maxY: 10))
        XCTAssertTrue(PTYSessionAnnotationRangeValidator.isValid(startX: 5, startY: 2, endX: 12, endY: 2, maxY: 10))
        XCTAssertTrue(PTYSessionAnnotationRangeValidator.isValid(startX: 20, startY: 2, endX: 1, endY: 5, maxY: 10))
        XCTAssertTrue(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 10, endX: 4, endY: 10, maxY: 10))
    }

    func testAnnotationRangeValidatorRejectsReversedNegativeAndOutOfBoundsRanges() {
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 10, startY: 3, endX: 5, endY: 3, maxY: 10))
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 5, endX: 10, endY: 4, maxY: 10))
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: -1, endX: 5, endY: 2, maxY: 10))
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 1, endX: 5, endY: -1, maxY: 10))
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 11, endX: 5, endY: 11, maxY: 10))
        XCTAssertFalse(PTYSessionAnnotationRangeValidator.isValid(startX: 0, startY: 2, endX: 5, endY: 11, maxY: 10))
    }

    func testObjectMethodsPolicyErrorsAndTimeOffsetPayload() {
        let rangeError = PTYSessionObjectMethodsPolicy.invalidAnnotationRangeError()
        XCTAssertEqual(rangeError.domain, "com.iterm2.add-annotation-command")
        XCTAssertEqual(rangeError.code, 0)
        XCTAssertEqual(rangeError.localizedDescription, "Invalid range")

        let notTmuxError = PTYSessionObjectMethodsPolicy.notTmuxSessionError()
        XCTAssertEqual(notTmuxError.domain, "com.iterm2.tmux-command")
        XCTAssertEqual(notTmuxError.code, 0)
        XCTAssertEqual(notTmuxError.localizedDescription, "Not a tmux integration session")

        let tmuxFailedError = PTYSessionObjectMethodsPolicy.tmuxCommandFailedError()
        XCTAssertEqual(tmuxFailedError.domain, "com.iterm2.tmux-command")
        XCTAssertEqual(tmuxFailedError.code, 1)
        XCTAssertEqual(tmuxFailedError.localizedDescription, "tmux error")

        let payload = PTYSessionObjectMethodsPolicy.timeOffsetPayload(offset: 28800, timeZone: "CST")
        XCTAssertEqual(payload["offset"] as? TimeInterval, 28800)
        XCTAssertEqual(payload["tz"] as? String, "CST")

        let nilTzPayload = PTYSessionObjectMethodsPolicy.timeOffsetPayload(offset: 0, timeZone: nil)
        XCTAssertEqual(nilTzPayload["tz"] as? String, "")
    }
}
