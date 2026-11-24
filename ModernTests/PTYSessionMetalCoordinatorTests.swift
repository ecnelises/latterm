//
//  PTYSessionMetalCoordinatorTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionMetalCoordinatorTests: XCTestCase {
    func testGlyphMetricsSingleAndDoubleWidthDimensions() {
        let metrics = PTYSessionMetalGlyphMetrics.compute(
            glyphSize: CGSize(width: 10, height: 20),
            scale: 2,
            maxCharacterParts: 5
        )
        XCTAssertNotNil(metrics)
        // radius = (5 / 2) * 2 + 1 = 5; dwMaxParts = 5 * 2 + 1 = 11
        XCTAssertEqual(metrics?.singleWidthPixelSize, CGSize(width: 100, height: 200))
        XCTAssertEqual(metrics?.doubleWidthPixelSize, CGSize(width: 220, height: 440))

        XCTAssertNil(PTYSessionMetalGlyphMetrics.compute(glyphSize: .zero, scale: 2, maxCharacterParts: 5))
        XCTAssertNil(PTYSessionMetalGlyphMetrics.compute(glyphSize: CGSize(width: 10, height: 20), scale: 0, maxCharacterParts: 5))
    }

    func testAsciiGlyphGeometryHandlesNegativeOrigins() {
        let result = PTYSessionMetalGlyphMetrics.asciiGlyphGeometry(
            cellSize: CGSize(width: 8, height: 16),
            boundingRect: CGRect(x: -1.2, y: -1.5, width: 9.0, height: 18.0),
            scale: 2
        )
        // floor(-1.2 * 2) = -3 => asciiOffset.width = 3, extra.width = 3
        // floor(-1.5 * 2) = -3 => extra.height = 3
        // maxX = 7.8, maxY = 16.5 => round(1 + 8) = 9, round(1 + 16.5) = 18
        // + extra * 2 => 15 x 24
        XCTAssertEqual(result.asciiOffset, CGSize(width: 3, height: 0))
        XCTAssertEqual(result.glyphSize, CGSize(width: 15, height: 24))
    }

    func testMetalEligibilityPolicyPrecedence() {
        let base = PTYSessionMetalEligibilityInputs(
            disableInLowPowerMode: true,
            isLowPowerModeEnabled: false,
            machineSupportsMetal: true,
            useMetalPreference: true,
            hasWindow: true,
            hasOnePixelContext: true,
            metalDeviceChanging: false,
            metalViewSizeIsLegal: true,
            hasTextView: true,
            showDropTargets: false,
            usingIntegratedGPU: false,
            windowOccludedFraction: 0.0
        )
        XCTAssertNil(PTYSessionMetalPolicy.evaluate(base))

        var lowPower = base
        lowPower.isLowPowerModeEnabled = true
        lowPower.machineSupportsMetal = false
        // Low power mode check runs before GPU check.
        XCTAssertEqual(PTYSessionMetalPolicy.evaluate(lowPower), .lowerPowerMode)

        var obscuredIntegrated = base
        obscuredIntegrated.usingIntegratedGPU = true
        obscuredIntegrated.windowOccludedFraction = 0.6
        XCTAssertEqual(PTYSessionMetalPolicy.evaluate(obscuredIntegrated), .windowObscured)

        // Discrete GPU ignores occlusion > 0.5.
        var obscuredDiscrete = obscuredIntegrated
        obscuredDiscrete.usingIntegratedGPU = false
        XCTAssertNil(PTYSessionMetalPolicy.evaluate(obscuredDiscrete))
    }

    func testMetalViewSizeLegalityBounds() {
        XCTAssertFalse(PTYSessionMetalPolicy.isViewSizeLegal(.zero))
        XCTAssertTrue(PTYSessionMetalPolicy.isViewSizeLegal(CGSize(width: 800, height: 600)))
        XCTAssertFalse(PTYSessionMetalPolicy.isViewSizeLegal(CGSize(width: 8192, height: 600)))
    }

    func testDisablementTrackerOverlappingOutOfOrderAndClear() {
        var tracker = PTYSessionMetalDisablementTracker()
        XCTAssertFalse(tracker.isDisabled)

        let t1 = tracker.acquireToken()
        let t2 = tracker.acquireToken()
        XCTAssertNotEqual(t1, t2)
        XCTAssertTrue(tracker.isDisabled)
        XCTAssertTrue(tracker.hasMultipleActiveTokens)

        // Out-of-order release leaves t1 active.
        XCTAssertTrue(tracker.release(t2))
        XCTAssertTrue(tracker.isDisabled)
        XCTAssertFalse(tracker.hasMultipleActiveTokens)
        XCTAssertFalse(tracker.release(t2))
        XCTAssertFalse(tracker.release("invalid"))

        XCTAssertTrue(tracker.release(t1))
        XCTAssertFalse(tracker.isDisabled)

        // clearAll invalidates all pending tokens cleanly.
        let t3 = tracker.acquireToken()
        tracker.clearAll()
        XCTAssertFalse(tracker.contains(t3))
        XCTAssertFalse(tracker.isDisabled)
    }
}
