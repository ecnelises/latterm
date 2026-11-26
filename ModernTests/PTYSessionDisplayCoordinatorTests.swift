import XCTest
@testable import iTerm2SharedARC

final class PTYSessionDisplayCoordinatorTests: XCTestCase {
    func testCadencePolicyUseAdaptiveFrameRateTruthTable() {
        XCTAssertTrue(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: true,
            maximizeThroughput: true,
            softAlternateScreenMode: false,
            disableAdaptiveInInteractiveApps: true,
            defaultUseAdaptiveFrameRate: false
        ))
        XCTAssertFalse(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: true,
            maximizeThroughput: true,
            softAlternateScreenMode: true,
            disableAdaptiveInInteractiveApps: false,
            defaultUseAdaptiveFrameRate: true
        ))
        XCTAssertFalse(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: true,
            maximizeThroughput: false,
            softAlternateScreenMode: false,
            disableAdaptiveInInteractiveApps: false,
            defaultUseAdaptiveFrameRate: true
        ))
        XCTAssertFalse(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: false,
            maximizeThroughput: false,
            softAlternateScreenMode: true,
            disableAdaptiveInInteractiveApps: true,
            defaultUseAdaptiveFrameRate: true
        ))
        XCTAssertTrue(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: false,
            maximizeThroughput: false,
            softAlternateScreenMode: false,
            disableAdaptiveInInteractiveApps: true,
            defaultUseAdaptiveFrameRate: true
        ))
    }

    func testCadencePolicySlowFrameRateAndLowPowerCap() {
        XCTAssertEqual(PTYSessionCadencePolicy.slowFrameRate(useMetal: true, metalSlowFrameRate: 15, legacySlowFrameRate: 5), 15)
        XCTAssertEqual(PTYSessionCadencePolicy.slowFrameRate(useMetal: false, metalSlowFrameRate: 15, legacySlowFrameRate: 5), 5)
        XCTAssertEqual(PTYSessionCadencePolicy.metalMaxFrameRate(lowPowerMode: true, lowPowerModeFrameRate: 24), 24)
        XCTAssertEqual(PTYSessionCadencePolicy.metalMaxFrameRate(lowPowerMode: false, lowPowerModeFrameRate: 24), 0)
    }

    func testMarksMinimapPolicy() {
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.successMark))
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.otherMark))
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.errorMark))
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.manualMark))
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.annotation))
        XCTAssertTrue(PTYSessionMarksMinimapPolicy.tracksObjectType(.unknown))
        XCTAssertFalse(PTYSessionMarksMinimapPolicy.tracksObjectType(.porthole))

        XCTAssertTrue(PTYSessionMarksMinimapPolicy.shouldUpdateMarks(showLocationsInScrollbar: true, showMarksInScrollbar: true))
        XCTAssertFalse(PTYSessionMarksMinimapPolicy.shouldUpdateMarks(showLocationsInScrollbar: true, showMarksInScrollbar: false))
        XCTAssertFalse(PTYSessionMarksMinimapPolicy.shouldUpdateMarks(showLocationsInScrollbar: false, showMarksInScrollbar: true))
    }

    func testFilterUpdateQueueOrderingDrainAndDiscard() {
        var queue = PTYSessionFilterUpdateQueue()
        let first = ScreenCharArray.emptyLine(ofLength: 10)
        let second = ScreenCharArray.emptyLine(ofLength: 20)

        XCTAssertTrue(queue.enqueueAppend(first))
        XCTAssertFalse(queue.enqueueAppend(second))
        queue.enqueueRemoveLastLine()
        XCTAssertEqual(queue.count, 3)

        let drained = queue.drain()
        XCTAssertEqual(drained.count, 3)
        XCTAssertEqual(queue.count, 0)

        if case .append(let sca) = drained[0] {
            XCTAssertEqual(sca.length, 10)
        } else {
            XCTFail("Expected first item to be append")
        }
        if case .append(let sca) = drained[1] {
            XCTAssertEqual(sca.length, 20)
        } else {
            XCTFail("Expected second item to be append")
        }
        if case .removeLastLine = drained[2] {
            // Expected
        } else {
            XCTFail("Expected third item to be removeLastLine")
        }

        XCTAssertTrue(queue.enqueueAppend(first))
        queue.discardAll()
        XCTAssertEqual(queue.count, 0)
    }
}
