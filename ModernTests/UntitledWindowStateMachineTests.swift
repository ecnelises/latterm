import XCTest
@testable import iTerm2SharedARC

final class UntitledWindowStateMachineTests: XCTestCase {
    private final class Delegate: NSObject, iTermUntitledWindowStateMachineDelegate {
        var windowRequests = 0

        func untitledWindowStateMachineCreateNewWindow(_ sender: iTermUntitledWindowStateMachine) {
            windowRequests += 1
        }
    }

    func testObjectiveCRuntimeNamesAndDelegateSelectorRemainAvailable() {
        XCTAssertTrue(NSClassFromString("iTermUntitledWindowStateMachine") === iTermUntitledWindowStateMachine.self)
        XCTAssertEqual(NSStringFromProtocol(iTermUntitledWindowStateMachineDelegate.self),
                       "iTermUntitledWindowStateMachineDelegate")
        let delegate = Delegate()
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("untitledWindowStateMachineCreateNewWindow:")))
    }

    func testRequestWaitsForBothStartupCompletionsInEveryOrder() {
        let orders = [
            [0, 1, 2], [0, 2, 1], [1, 0, 2],
            [1, 2, 0], [2, 0, 1], [2, 1, 0]
        ]
        for order in orders {
            let machine = iTermUntitledWindowStateMachine()
            let delegate = Delegate()
            machine.delegate = delegate
            let events = [machine.maybeOpenUntitledFile,
                          machine.didFinishInitialization,
                          machine.didFinishRestoringWindows]
            for (index, event) in order.enumerated() {
                events[event]()
                XCTAssertEqual(delegate.windowRequests, index == 2 ? 1 : 0, "Order: \(order)")
            }
        }
    }

    func testStartupWithoutRequestDoesNotOpenWindow() {
        let machine = iTermUntitledWindowStateMachine()
        let delegate = Delegate()
        machine.delegate = delegate
        machine.didFinishInitialization()
        machine.didFinishRestoringWindows()
        XCTAssertEqual(delegate.windowRequests, 0)
    }

    func testDisablingInitialWindowCancelsPendingRequest() {
        let machine = iTermUntitledWindowStateMachine()
        let delegate = Delegate()
        machine.delegate = delegate
        machine.maybeOpenUntitledFile()
        machine.disableInitialUntitledWindow()
        machine.maybeOpenUntitledFile()
        machine.didFinishInitialization()
        machine.maybeOpenUntitledFile()
        machine.didFinishRestoringWindows()
        XCTAssertEqual(delegate.windowRequests, 0)
        machine.maybeOpenUntitledFile()
        XCTAssertEqual(delegate.windowRequests, 1)
    }

    func testDisabledRequestIsIgnoredWhenRestorationFinishesBeforeInitialization() {
        let machine = iTermUntitledWindowStateMachine()
        let delegate = Delegate()
        machine.delegate = delegate
        machine.disableInitialUntitledWindow()
        machine.didFinishRestoringWindows()
        machine.maybeOpenUntitledFile()
        machine.didFinishInitialization()
        XCTAssertEqual(delegate.windowRequests, 0)
        machine.maybeOpenUntitledFile()
        XCTAssertEqual(delegate.windowRequests, 1)
    }

    func testRestoredWindowsCancelPendingUntitledWindow() {
        let machine = iTermUntitledWindowStateMachine()
        let delegate = Delegate()
        machine.delegate = delegate
        machine.maybeOpenUntitledFile()
        machine.didRestoreSomeWindows()
        machine.didFinishRestoringWindows()
        machine.didFinishInitialization()
        XCTAssertEqual(delegate.windowRequests, 0)
        machine.maybeOpenUntitledFile()
        XCTAssertEqual(delegate.windowRequests, 1)
    }

    func testSubsequentRequestsAndCompletionCallbacksKeepExistingBehavior() {
        let machine = iTermUntitledWindowStateMachine()
        let delegate = Delegate()
        machine.delegate = delegate
        machine.didFinishInitialization()
        machine.didFinishRestoringWindows()
        machine.maybeOpenUntitledFile()
        machine.maybeOpenUntitledFile()
        XCTAssertEqual(delegate.windowRequests, 2)
        // The original coordinator keeps its request latched across callbacks.
        machine.didFinishInitialization()
        machine.didFinishRestoringWindows()
        XCTAssertEqual(delegate.windowRequests, 4)
    }

    func testDelegateIsWeak() {
        let machine = iTermUntitledWindowStateMachine()
        var delegate: Delegate? = Delegate()
        machine.delegate = delegate
        XCTAssertNotNil(machine.delegate)
        delegate = nil
        XCTAssertNil(machine.delegate)
        machine.didFinishInitialization()
        machine.didFinishRestoringWindows()
        machine.maybeOpenUntitledFile()
    }
}
