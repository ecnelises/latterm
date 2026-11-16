//
//  CopyModeTests.swift
//  ModernTests
//

import Cocoa
import XCTest
@testable import iTerm2SharedARC

private final class MockCopyModeState: NSObject, iTermCopyModeStateProtocol {
    var selecting: Bool = false
    var mode: iTermSelectionMode = .kiTermSelectionModeCharacter

    var actions: [String] = []
    var moveReturnValue = true
    var asyncCalls = 0

    private func record(_ name: String) -> Bool {
        actions.append(name)
        return moveReturnValue
    }

    func moveBackwardWord() -> Bool { record("moveBackwardWord") }
    func moveForwardWord() -> Bool { record("moveForwardWord") }
    func moveBackwardBigWord() -> Bool { record("moveBackwardBigWord") }
    func moveForwardBigWord() -> Bool { record("moveForwardBigWord") }
    func moveLeft() -> Bool { record("moveLeft") }
    func moveRight() -> Bool { record("moveRight") }
    func moveUp() -> Bool { record("moveUp") }
    func moveDown() -> Bool { record("moveDown") }
    func moveToStartOfNextLine() -> Bool { record("moveToStartOfNextLine") }
    func pageUp() -> Bool { record("pageUp") }
    func pageDown() -> Bool { record("pageDown") }
    func pageUpHalfScreen() -> Bool { record("pageUpHalfScreen") }
    func pageDownHalfScreen() -> Bool { record("pageDownHalfScreen") }
    func previousMark() -> Bool { record("previousMark") }
    func nextMark() -> Bool { record("nextMark") }
    func moveToStart() -> Bool { record("moveToStart") }
    func moveToEnd() -> Bool { record("moveToEnd") }
    func moveToStartOfIndentation() -> Bool { record("moveToStartOfIndentation") }
    func moveToBottomOfVisibleArea() -> Bool { record("moveToBottomOfVisibleArea") }
    func moveToMiddleOfVisibleArea() -> Bool { record("moveToMiddleOfVisibleArea") }
    func moveToTopOfVisibleArea() -> Bool { record("moveToTopOfVisibleArea") }
    func moveToStartOfLine() -> Bool { record("moveToStartOfLine") }
    func moveToEndOfLine() -> Bool { record("moveToEndOfLine") }
    func swap() { _ = record("swap") }
    func scrollUp() -> Bool { record("scrollUp") }
    func scrollDown() -> Bool { record("scrollDown") }

    func performAsynchronously(_ block: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        asyncCalls += 1
        DispatchQueue.main.async {
            block()
            completion(self.moveReturnValue)
        }
    }
}

private final class MockModeHandlerDelegate: NSObject,
    iTermCopyModeHandlerDelegate,
    iTermShortcutNavigationModeHandlerDelegate {
    var createdState: MockCopyModeState = MockCopyModeState()
    var didChangeEnabledCount = 0
    var redrawCount = 0
    var revealCount = 0
    var showFindPanelCount = 0
    var copySelectionCount = 0

    var shortcutBeginCount = 0
    var shortcutCompleteCount = 0
    var recordedPrefixes: [String?] = []
    var shortcutActions: [String: (NSEvent) -> Void] = [:]
    var commandPrefixes: Set<String> = []

    func copyModeHandlerDidChangeEnabledState(_ handler: iTermCopyModeHandler) {
        didChangeEnabledCount += 1
    }

    func copyModeHandlerRedraw(_ handler: iTermCopyModeHandler) {
        redrawCount += 1
    }

    func copyModeHandlerCreateState(_ handler: iTermCopyModeHandler) -> iTermCopyModeStateProtocol {
        createdState
    }

    func copyModeHandler(_ handler: iTermCopyModeHandler,
                         revealCurrentLineInState state: iTermCopyModeStateProtocol) {
        revealCount += 1
    }

    func copyModeHandlerShowFindPanel(_ handler: iTermCopyModeHandler) {
        showFindPanelCount += 1
    }

    func copyModeHandlerCopySelection(_ handler: iTermCopyModeHandler) {
        copySelectionCount += 1
    }

    func shortcutNavigationAction(forKeyEquivalent characters: String) -> ((NSEvent) -> Void)? {
        shortcutActions[characters]
    }

    func shortcutNavigationDidComplete() {
        shortcutCompleteCount += 1
    }

    func shortcutNavigationDidBegin() {
        shortcutBeginCount += 1
    }

    func shortcutNavigationCharactersAreCommandPrefix(_ characters: String) -> Bool {
        commandPrefixes.contains(characters)
    }

    func shortcutNavigationDidSetPrefix(_ prefix: String?) {
        recordedPrefixes.append(prefix)
    }
}

final class CopyModeTests: XCTestCase {
    private var previousHaveUsedCopyMode: Any?
    private var previousAutoEnter: Bool = false

    override func setUp() {
        super.setUp()
        let defaults = iTermUserDefaults.userDefaults()
        previousHaveUsedCopyMode = defaults.object(forKey: "NoSyncHaveUsedCopyMode")
        defaults.set(true, forKey: "NoSyncHaveUsedCopyMode")
        previousAutoEnter = iTermPreferences.bool(forKey: kPreferenceKeyEnterCopyModeAutomatically)
    }

    override func tearDown() {
        let defaults = iTermUserDefaults.userDefaults()
        if let previousHaveUsedCopyMode {
            defaults.set(previousHaveUsedCopyMode, forKey: "NoSyncHaveUsedCopyMode")
        } else {
            defaults.removeObject(forKey: "NoSyncHaveUsedCopyMode")
        }
        iTermPreferences.setBool(previousAutoEnter, forKey: kPreferenceKeyEnterCopyModeAutomatically)
        super.tearDown()
    }

    private func makeKeyEvent(characters: String,
                              charactersIgnoringModifiers: String? = nil,
                              modifiers: NSEvent.ModifierFlags = [],
                              keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: keyCode)!
    }

    func testCopyModeStateSwapAndSelectingAnchor() {
        let state = iTermCopyModeState()
        state.coord = VT100GridCoordMake(12, 8)
        XCTAssertFalse(state.selecting)

        state.selecting = true
        XCTAssertEqual(state.start.x, 12)
        XCTAssertEqual(state.start.y, 8)

        // Setting selecting to true again must not overwrite existing anchor.
        state.coord = VT100GridCoordMake(4, 15)
        state.selecting = true
        XCTAssertEqual(state.start.x, 12)
        XCTAssertEqual(state.start.y, 8)

        state.swap()
        XCTAssertEqual(state.coord.x, 12)
        XCTAssertEqual(state.coord.y, 8)
        XCTAssertEqual(state.start.x, 4)
        XCTAssertEqual(state.start.y, 15)
    }

    func testCountPrefixAndZeroBehavior() {
        let delegate = MockModeHandlerDelegate()
        let handler = iTermCopyModeHandler()
        handler.delegate = delegate
        handler.setEnabledWithoutCleverness(true)

        // Leading "0" without an active count moves to start of line.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "0")))
        XCTAssertEqual(delegate.createdState.actions, ["moveToStartOfLine"])

        delegate.createdState.actions.removeAll()

        // "1" then "0" accrues count = 10, then "l" executes moveRight 10 times.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "1")))
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "0")))
        XCTAssertTrue(delegate.createdState.actions.isEmpty)
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "l")))
        XCTAssertEqual(delegate.createdState.actions, Array(repeating: "moveRight", count: 10))
    }

    func testSelectionModesCopyFindAndQuit() {
        let delegate = MockModeHandlerDelegate()
        let handler = iTermCopyModeHandler()
        handler.delegate = delegate
        handler.setEnabledWithoutCleverness(true)

        XCTAssertTrue(handler.enabled)
        XCTAssertEqual(delegate.didChangeEnabledCount, 1)

        // "v" toggles character selection.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "v")))
        XCTAssertTrue(delegate.createdState.selecting)
        XCTAssertEqual(delegate.createdState.mode, .kiTermSelectionModeCharacter)

        // "V" (Shift+V) toggles line mode.
        XCTAssertTrue(handler.handleEvent(
            makeKeyEvent(characters: "V", charactersIgnoringModifiers: "v", modifiers: .shift)))
        XCTAssertFalse(delegate.createdState.selecting)
        XCTAssertEqual(delegate.createdState.mode, .kiTermSelectionModeLine)

        // "/" opens find panel.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "/")))
        XCTAssertEqual(delegate.showFindPanelCount, 1)

        // "y" copies selection and exits copy mode.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "y")))
        XCTAssertEqual(delegate.copySelectionCount, 1)
        XCTAssertFalse(handler.enabled)
        XCTAssertNil(handler.state)
    }

    func testQuitClearsSelectionAndUnboundCommandKeyIsIgnored() {
        let delegate = MockModeHandlerDelegate()
        let handler = iTermCopyModeHandler()
        handler.delegate = delegate
        handler.setEnabledWithoutCleverness(true)

        // Start selection then press "3", then unbound Cmd+K resets count and returns false.
        _ = handler.handleEvent(makeKeyEvent(characters: "v"))
        _ = handler.handleEvent(makeKeyEvent(characters: "3"))
        let cmdK = makeKeyEvent(characters: "k", modifiers: .command)
        XCTAssertFalse(handler.wouldHandleEvent(cmdK))
        XCTAssertFalse(handler.handleEvent(cmdK))

        // Count was reset by Cmd+K, so "h" only moves once.
        _ = handler.handleEvent(makeKeyEvent(characters: "h"))
        XCTAssertEqual(delegate.createdState.actions, ["moveLeft"])

        // "q" disables copy mode and clears selecting.
        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "q")))
        XCTAssertFalse(handler.enabled)
        XCTAssertFalse(delegate.createdState.selecting)
    }

    func testAutoEnterCheckAndBackwardSwap() {
        let delegate = MockModeHandlerDelegate()
        let handler = iTermCopyModeHandler()
        handler.delegate = delegate

        let leftScalar = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let shiftLeft = makeKeyEvent(characters: leftScalar, modifiers: .shift, keyCode: 123)
        let plainLeft = makeKeyEvent(characters: leftScalar, modifiers: [], keyCode: 123)

        iTermPreferences.setBool(false, forKey: kPreferenceKeyEnterCopyModeAutomatically)
        XCTAssertFalse(handler.shouldAutoEnter(with: shiftLeft))

        iTermPreferences.setBool(true, forKey: kPreferenceKeyEnterCopyModeAutomatically)
        XCTAssertTrue(handler.shouldAutoEnter(with: shiftLeft))
        XCTAssertFalse(handler.shouldAutoEnter(with: plainLeft))

        handler.handleAutoEnteringEvent(shiftLeft)
        XCTAssertTrue(handler.enabled)
        XCTAssertEqual(delegate.createdState.actions.first, "swap")
        XCTAssertTrue(delegate.createdState.actions.contains("moveLeft"))
    }

    func testAsyncEventRunsRequestedRepeatCount() {
        let delegate = MockModeHandlerDelegate()
        let handler = iTermCopyModeHandler()
        handler.delegate = delegate
        handler.setEnabledWithoutCleverness(true)

        XCTAssertTrue(handler.handleEvent(makeKeyEvent(characters: "3")))

        let expectation = expectation(description: "async copy mode event finishes")
        var handledResult = false
        handler.handleAsyncEvent(makeKeyEvent(characters: "j")) { handled in
            handledResult = handled
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertTrue(handledResult)
        XCTAssertEqual(delegate.createdState.asyncCalls, 3)
        XCTAssertEqual(delegate.createdState.actions, ["moveDown", "moveDown", "moveDown"])
    }

    func testSessionModeHandlerAndShortcutNavigation() {
        let delegate = MockModeHandlerDelegate()
        var triggered: [String] = []
        delegate.commandPrefixes = ["g"]
        delegate.shortcutActions["ga"] = { _ in triggered.append("ga") }

        let sessionHandler = iTermSessionModeHandler()
        sessionHandler.delegate = delegate
        XCTAssertEqual(sessionHandler.mode, .default)

        sessionHandler.mode = .shortcutNavigation
        XCTAssertEqual(delegate.shortcutBeginCount, 1)

        // Prefix "g" returns partial and keeps shortcut navigation active.
        let gEvent = makeKeyEvent(characters: "g")
        XCTAssertTrue(sessionHandler.handle(gEvent))
        XCTAssertEqual(sessionHandler.mode, .shortcutNavigation)
        XCTAssertEqual(delegate.recordedPrefixes, ["g"])

        // Completing "a" triggers "ga", resets prefix, and exits shortcut navigation.
        let aEvent = makeKeyEvent(characters: "a")
        XCTAssertTrue(sessionHandler.handle(aEvent))
        XCTAssertEqual(triggered, ["ga"])
        XCTAssertEqual(sessionHandler.mode, .default)
        XCTAssertEqual(delegate.shortcutCompleteCount, 1)

        // Switching back to shortcut navigation, Esc exits cleanly.
        sessionHandler.mode = .shortcutNavigation
        let escEvent = makeKeyEvent(characters: "\u{1b}")
        XCTAssertTrue(sessionHandler.wouldHandleEvent(escEvent))
        XCTAssertTrue(sessionHandler.handle(escEvent))
        XCTAssertEqual(sessionHandler.mode, .default)

        // Switching to copy mode activates copyModeHandler and forwards mark navigation.
        sessionHandler.enterCopyModeWithoutCleverness()
        XCTAssertEqual(sessionHandler.mode, .copy)
        XCTAssertTrue(sessionHandler.copyModeHandler.enabled)
        XCTAssertTrue(sessionHandler.previousMark())
        XCTAssertTrue(sessionHandler.nextMark())
        XCTAssertEqual(delegate.createdState.actions, ["previousMark", "nextMark"])
    }
}
