//
//  PTYSessionTmuxBridgeTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionTmuxBridgeTests: XCTestCase {
    func testTTLTrackerHysteresisAndReset() {
        var tracker = PTYSessionTmuxTTLTracker()

        // First sample establishes [9.0, 11.0].
        XCTAssertTrue(tracker.shouldUpdate(ttl: 10.0))
        XCTAssertEqual(tracker.lowerThreshold, 9.0, accuracy: 0.0001)
        XCTAssertEqual(tracker.upperThreshold, 11.0, accuracy: 0.0001)

        // Values strictly inside (9.0, 11.0) are suppressed.
        XCTAssertFalse(tracker.shouldUpdate(ttl: 9.5))
        XCTAssertFalse(tracker.shouldUpdate(ttl: 10.9))

        // Downward boundary equality triggers update and sets [ttl - 1, ttl + 1.5].
        XCTAssertTrue(tracker.shouldUpdate(ttl: 9.0))
        XCTAssertEqual(tracker.lowerThreshold, 8.0, accuracy: 0.0001)
        XCTAssertEqual(tracker.upperThreshold, 10.5, accuracy: 0.0001)

        // Upward boundary equality triggers update and sets [ttl - 1.5, ttl + 1].
        XCTAssertTrue(tracker.shouldUpdate(ttl: 10.5))
        XCTAssertEqual(tracker.lowerThreshold, 9.0, accuracy: 0.0001)
        XCTAssertEqual(tracker.upperThreshold, 11.5, accuracy: 0.0001)

        // Reset restores initial symmetric threshold behavior.
        tracker.reset()
        XCTAssertFalse(tracker.hasThresholds)
        XCTAssertTrue(tracker.shouldUpdate(ttl: 10.0))
        XCTAssertEqual(tracker.lowerThreshold, 9.0, accuracy: 0.0001)
        XCTAssertEqual(tracker.upperThreshold, 11.0, accuracy: 0.0001)
    }

    func testCommandOutputLinesStripsCarriageReturnsAndPreservesEmptyLines() {
        let lines = PTYSessionTmuxSupport.commandOutputLines(from: "line1\r\n\r\nline3\n")
        XCTAssertEqual(lines, ["line1", "", "line3", ""])
    }

    func testPauseWarningMessagePluralizationAndSafeTTLClamping() {
        XCTAssertEqual(
            PTYSessionTmuxSupport.pauseWarningMessage(for: 0.2),
            "This session will pause in about 1 second because it is buffering too much data."
        )
        XCTAssertEqual(
            PTYSessionTmuxSupport.pauseWarningMessage(for: 1.4),
            "This session will pause in about 1 second because it is buffering too much data."
        )
        XCTAssertEqual(
            PTYSessionTmuxSupport.pauseWarningMessage(for: 2.6),
            "This session will pause in about 3 seconds because it is buffering too much data."
        )
        XCTAssertEqual(PTYSessionTmuxSupport.safeRoundedTTL(.nan), Int.max)
        XCTAssertEqual(PTYSessionTmuxSupport.safeRoundedTTL(Double.infinity), Int.max)
    }

    func testScrollbackLineCountCalculation() {
        XCTAssertEqual(
            PTYSessionTmuxSupport.scrollbackLineCount(unlimitedScrollback: true, configuredLines: 500),
            10_000_000
        )
        XCTAssertEqual(
            PTYSessionTmuxSupport.scrollbackLineCount(unlimitedScrollback: false, configuredLines: 2500),
            2500
        )
    }
}
