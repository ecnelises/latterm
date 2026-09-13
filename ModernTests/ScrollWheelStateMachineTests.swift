import AppKit
import XCTest
@testable import iTerm2SharedARC

final class ScrollWheelStateMachineTests: XCTestCase {
    private typealias Step = (phase: NSEvent.Phase,
                             momentum: NSEvent.Phase,
                             state: iTermScrollWheelStateMachineState)

    private func checkSequence(_ steps: [Step], file: StaticString = #filePath, line: UInt = #line) {
        let machine = iTermScrollWheelStateMachine()
        XCTAssertEqual(machine.state, .ground, file: file, line: line)
        for (index, step) in steps.enumerated() {
            machine.handle(phase: step.phase, momentumPhase: step.momentum)
            XCTAssertEqual(machine.state, step.state, "Step \(index)", file: file, line: line)
        }
    }

    func testDragThenMomentumAndAnotherGesture() {
        checkSequence([
            (.began, [], .startDrag),
            (.changed, [], .drag),
            (.changed, [], .drag),
            (.ended, [], .ground),
            ([], .began, .ground),
            ([], .changed, .ground),
            ([], .ended, .ground),
            (.began, [], .startDrag)
        ])
    }

    func testTouchAndHoldThenDrag() {
        checkSequence([
            (.mayBegin, [], .touchAndHold),
            (.stationary, [], .touchAndHold),
            (.began, [], .startDrag),
            (.changed, [], .drag),
            (.ended, [], .ground)
        ])
    }

    func testCancelledHoldCanStartAgain() {
        checkSequence([
            (.mayBegin, [], .touchAndHold),
            (.cancelled, [], .ground),
            (.mayBegin, [], .touchAndHold),
            (.began, [], .startDrag)
        ])
    }

    func testDragMayEndBeforeFirstChangedEvent() {
        checkSequence([
            (.began, [], .startDrag),
            (.ended, [], .ground)
        ])
    }

    func testMomentumCanEndDragWithoutEndedEvent() {
        checkSequence([
            (.began, [], .startDrag),
            (.changed, [], .drag),
            ([], .changed, .ground)
        ])
    }

    func testOrdinaryWheelAndOrphanedEventsDoNotStartGesture() {
        checkSequence([
            ([], [], .ground),
            (.changed, [], .ground),
            (.ended, [], .ground),
            ([], .changed, .ground),
            ([], .began, .ground),
            ([], .ended, .ground),
            (.stationary, [], .ground),
            (.cancelled, [], .ground)
        ])
    }

    func testUnexpectedEventsPreserveGestureProgress() {
        checkSequence([
            (.began, [], .startDrag),
            (.cancelled, [], .startDrag),
            ([], [], .startDrag),
            (.changed, [], .drag),
            (.cancelled, [], .drag),
            (.stationary, [], .drag),
            (.mayBegin, [], .drag),
            (.ended, [], .ground)
        ])
    }

    func testNonemptyMomentumDoesNotMatchAnEmptyPhaseRequirement() {
        checkSequence([
            (.began, .began, .ground),
            (.mayBegin, .changed, .ground),
            (.began, [], .startDrag),
            (.changed, .changed, .startDrag),
            (.changed, [], .drag),
            (.ended, .changed, .drag),
            (.stationary, .changed, .drag),
            ([], .changed, .ground)
        ])
    }

    func testCombinedPhasesUseOriginalTransitionPriority() {
        checkSequence([
            ([.began, .mayBegin], [], .startDrag),
            // Changed wins over Ended at the start of a drag.
            ([.changed, .ended], [], .drag),
            // Ended wins over Changed once a drag is underway.
            ([.changed, .ended], [], .ground),
            (.mayBegin, [], .touchAndHold),
            // Began wins over Cancelled during a hold.
            ([.began, .cancelled], [], .startDrag)
        ])
    }

    func testCombinedMomentumFlagsAreMatchedByMembership() {
        checkSequence([
            (.began, [], .startDrag),
            (.changed, [], .drag),
            ([], [.changed, .ended], .ground)
        ])
    }

    func testUnknownFlagsDoNotPreventKnownPhaseMatches() {
        let unknown = NSEvent.Phase(rawValue: 1 << 12)
        checkSequence([
            (unknown, [], .ground),
            (.began, unknown, .ground),
            ([.began, unknown], [], .startDrag),
            (unknown, [], .startDrag),
            ([.changed, unknown], [], .drag),
            ([], [.changed, unknown], .ground)
        ])
    }

    func testEventAdapterAndDiagnostics() throws {
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,
                                           units: .pixel,
                                           wheelCount: 2,
                                           wheel1: 0,
                                           wheel2: 12,
                                           wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        let machine = iTermScrollWheelStateMachine()
        machine.handleEvent(event)
        XCTAssertEqual(machine.state, .ground)
        let summary = iTermScrollWheelStateMachine.shortEventPhasesString(event)
        XCTAssertTrue(summary.contains("phase=None, momentumPhase=None"))
        XCTAssertTrue(summary.contains("scrollingDeltaX="))
    }
}
