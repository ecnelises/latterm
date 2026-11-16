//
//  CopyModeHandler.swift
//  iTerm2SharedARC
//
//  Migrated from iTermCopyModeHandler.{h,m}.
//

import Cocoa

private enum CopyModeAction: String {
    case none = "None"
    case copySelection = "CopySelection"
    case exitCopyMode = "ExitCopyMode"
    case moveBackwardWord = "MoveBackwardWord"
    case moveBackwardBigWord = "MoveBackwardBigWord"
    case moveDown = "MoveDown"
    case moveForwardWord = "MoveForwardWord"
    case moveForwardBigWord = "MoveForwardBigWord"
    case moveLeft = "MoveLeft"
    case moveRight = "MoveRight"
    case moveToBottomOfVisibleArea = "MoveToBottomOfVisibleArea"
    case moveToEnd = "MoveToEnd"
    case moveToEndOfLine = "MoveToEndOfLine"
    case moveToMiddleOfVisibleArea = "MoveToMiddleOfVisibleArea"
    case moveToStart = "MoveToStart"
    case moveToStartOfIndentation = "MoveToStartOfIndentation"
    case moveToStartOfLine = "MoveToStartOfLine"
    case moveToStartOfNextLine = "MoveToStartOfNextLine"
    case moveToTopOfVisibleArea = "MoveToTopOfVisibleArea"
    case moveUp = "MoveUp"
    case nextMark = "NextMark"
    case pageDown = "PageDown"
    case pageUp = "PageUp"
    case previousMark = "PreviousMark"
    case quit = "Quit"
    case showFindPanel = "ShowFindPanel"
    case swap = "Swap"
    case toggleBoxSelection = "ToggleBoxSelection"
    case toggleCharacterSelection = "ToggleCharacterSelection"
    case toggleLineSelection = "ToggleLineSelection"
    case accrueCount = "AccrueCount"
    case moveToStartOfLineOrAccrue0 = "MoveToStartOfLineOrAccrue0"
    case pageDownHalfScreen = "PageDownHalfScreen"
    case pageUpHalfScreen = "PageUpHalfScreen"
    case scrollUp = "ScrollUp"
    case scrollDown = "ScrollDown"
}

/// Delegate notified by `iTermCopyModeHandler` when copy-mode state or selection changes.
@objc(iTermCopyModeHandlerDelegate)
protocol iTermCopyModeHandlerDelegate: NSObjectProtocol {
    @objc(copyModeHandlerDidChangeEnabledState:)
    func copyModeHandlerDidChangeEnabledState(_ handler: iTermCopyModeHandler)

    @objc(copyModeHandlerRedraw:)
    func copyModeHandlerRedraw(_ handler: iTermCopyModeHandler)

    @objc(copyModeHandlerCreateState:)
    func copyModeHandlerCreateState(_ handler: iTermCopyModeHandler) -> iTermCopyModeStateProtocol

    @objc(copyModeHandler:revealCurrentLineInState:)
    func copyModeHandler(_ handler: iTermCopyModeHandler,
                         revealCurrentLineInState state: iTermCopyModeStateProtocol)

    @objc(copyModeHandlerShowFindPanel:)
    func copyModeHandlerShowFindPanel(_ handler: iTermCopyModeHandler)

    @objc(copyModeHandlerCopySelection:)
    func copyModeHandlerCopySelection(_ handler: iTermCopyModeHandler)
}

/// Translates key events into vim-style Copy Mode navigation and selection actions.
@objc(iTermCopyModeHandler)
final class iTermCopyModeHandler: NSObject {
    @objc weak var delegate: iTermCopyModeHandlerDelegate?
    @objc private(set) var state: iTermCopyModeStateProtocol?

    private var _enabled = false
    private let keyBindingEmulator: iTermNSKeyBindingEmulator
    // 0: Perform action once; "MoveToStartOfLineOrAccrue0" moves to start of line.
    // >= 1: Repeat count; "MoveToStartOfLineOrAccrue0" appends digit 0.
    private var count: Int = 0

    @objc var enabled: Bool {
        get { _enabled }
        set {
            if newValue, let currentEvent = NSApp.currentEvent,
               shouldAutoEnterIgnoringPrefs(currentEvent) {
                // If a keystroke bound to enable copy mode also moves in a selection direction,
                // treat it as auto-entering so the cursor lands on the proper side of the selection.
                handleAutoEnteringEvent(currentEvent)
                return
            }
            setEnabledWithoutCleverness(newValue)
        }
    }

    override init() {
        let userBindingsPath = FileManager.default.applicationSupportDirectoryWithoutCreating()
            .map { ($0 as NSString).appendingPathComponent("CopyModeKeyBindings.dict") }
        let path: String?
        if let userBindingsPath, FileManager.default.fileExists(atPath: userBindingsPath) {
            path = userBindingsPath
        } else {
            path = Bundle(for: iTermCopyModeHandler.self)
                .path(forResource: "iTermCopyModeKeyBindings", ofType: "dict")
        }
        keyBindingEmulator = iTermNSKeyBindingEmulator(file: path, allowedActions: nil)
        super.init()
    }

    @objc(setEnabledWithoutCleverness:)
    func setEnabledWithoutCleverness(_ copyMode: Bool) {
        if copyMode {
            let key = "NoSyncHaveUsedCopyMode"
            let defaults = iTermUserDefaults.userDefaults()
            if defaults.object(forKey: key) == nil {
                educateAboutCopyMode()
            }
            defaults.set(true, forKey: key)
        }

        _enabled = copyMode
        count = 0
        state = copyMode ? delegate?.copyModeHandlerCreateState(self) : nil
        delegate?.copyModeHandlerDidChangeEnabledState(self)
    }

    @objc(wouldHandleEvent:)
    func wouldHandleEvent(_ event: NSEvent) -> Bool {
        // Reserve all keypresses except those with the command modifier.
        action(for: event) != .none || !event.it_modifierFlags.contains(.command)
    }

    @objc(shouldAutoEnterWithEvent:)
    func shouldAutoEnter(with event: NSEvent) -> Bool {
        if enabled {
            return false
        }
        if !iTermPreferences.bool(forKey: kPreferenceKeyEnterCopyModeAutomatically) {
            return false
        }
        return shouldAutoEnterIgnoringPrefs(event)
    }

    @objc(handleAutoEnteringEvent:)
    func handleAutoEnteringEvent(_ event: NSEvent) {
        let direction = autoEnterEventDirection(event)
        it_assert(direction != 0, "handleAutoEnteringEvent called for non-navigating event")
        setEnabledWithoutCleverness(true)
        if direction < 0 {
            state?.swap()
        }
        _ = handleEvent(event)
    }

    @objc(handleAsyncEvent:completion:)
    func handleAsyncEvent(_ event: NSEvent, completion: @escaping (Bool) -> Void) {
        let wasSelecting = state?.selecting ?? false
        guard let preparedAction = prepareToHandleEvent(event) else {
            completion(false)
            return
        }
        guard let action = preparedAction.action else {
            completion(true)
            return
        }

        let iterations = max(1, count)
        count = 0

        func runStep(_ stepIndex: Int) {
            performAsyncAction(action, event: event) { [weak self] _ in
                guard let self else {
                    completion(false)
                    return
                }
                if (self.state?.selecting ?? false) != wasSelecting || self.actionTypicallyMoves(action) {
                    if self.enabled, let state = self.state {
                        self.delegate?.copyModeHandler(self, revealCurrentLineInState: state)
                    }
                    self.delegate?.copyModeHandlerRedraw(self)
                }
                if stepIndex < iterations {
                    runStep(stepIndex + 1)
                } else {
                    completion(true)
                }
            }
        }
        runStep(1)
    }

    @discardableResult
    @objc(handleEvent:)
    func handleEvent(_ event: NSEvent) -> Bool {
        let wasSelecting = state?.selecting ?? false
        guard let prepared = prepareToHandleEvent(event) else {
            return false
        }
        guard let action = prepared.action else {
            return true
        }

        let iterations = max(1, count)
        count = 0
        for _ in 0..<iterations {
            let moved = performAction(action, event: event)
            if moved || (state?.selecting ?? false) != wasSelecting {
                if enabled, let state {
                    delegate?.copyModeHandler(self, revealCurrentLineInState: state)
                }
                delegate?.copyModeHandlerRedraw(self)
            }
        }
        return true
    }

    // MARK: - Private

    private enum PreparedAction {
        case execute(CopyModeAction)
        case countAccrued

        var action: CopyModeAction? {
            switch self {
            case .execute(let action): return action
            case .countAccrued: return nil
            }
        }
    }

    private func prepareToHandleEvent(_ event: NSEvent) -> PreparedAction? {
        delegate?.copyModeHandlerRedraw(self)

        let mappedAction = action(for: event)
        if mappedAction == .none && event.it_modifierFlags.contains(.command) {
            count = 0
            return nil
        }

        if let digit = accruedDigit(for: mappedAction, event: event) {
            count = count * 10 + digit
            return .countAccrued
        }

        return .execute(mappedAction)
    }

    private func actionTypicallyMoves(_ action: CopyModeAction) -> Bool {
        switch action {
        case .none, .exitCopyMode, .copySelection, .showFindPanel,
             .toggleCharacterSelection, .toggleBoxSelection, .toggleLineSelection:
            return false
        default:
            return true
        }
    }

    private func autoEnterEventDirection(_ event: NSEvent) -> Int {
        guard let scalar = event.charactersIgnoringModifiers?.utf16.first else {
            return 0
        }
        switch Int(scalar) {
        case NSPageUpFunctionKey, NSLeftArrowFunctionKey, NSUpArrowFunctionKey, NSHomeFunctionKey:
            return -1
        case NSPageDownFunctionKey, NSDownArrowFunctionKey, NSRightArrowFunctionKey, NSEndFunctionKey:
            return 1
        default:
            return 0
        }
    }

    private func shouldAutoEnterIgnoringPrefs(_ event: NSEvent) -> Bool {
        if event.type != .keyDown {
            return false
        }
        if autoEnterEventDirection(event) == 0 {
            return false
        }
        let relevantMask: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let allowedSets: [NSEvent.ModifierFlags] = [
            [.shift],
            [.shift, .option],
            [.shift, .control],  // CamelCaseWord movement in Xcode
            [.shift, .command],
        ]
        return allowedSets.contains(event.modifierFlags.intersection(relevantMask))
    }

    private func accruedDigit(for action: CopyModeAction, event: NSEvent) -> Int? {
        switch action {
        case .accrueCount:
            guard let scalar = event.characters?.utf16.first else {
                return nil
            }
            return Int(scalar) - Int(Character("0").asciiValue!)
        case .moveToStartOfLineOrAccrue0:
            return count == 0 ? nil : 0
        default:
            return nil
        }
    }

    private func performAsyncAction(_ action: CopyModeAction,
                                    event: NSEvent,
                                    completion: @escaping (Bool) -> Void) {
        if let asyncPerform = state?.performAsynchronously {
            asyncPerform({ [self] in
                _ = self.performAction(action, event: event)
            }, completion)
        } else {
            completion(performAction(action, event: event))
        }
    }

    private func performAction(_ action: CopyModeAction, event: NSEvent) -> Bool {
        switch action {
        case .accrueCount:
            it_assert(false, "AccrueCount should be consumed before performAction")
            return false
        case .pageDownHalfScreen:
            return state?.pageDownHalfScreen() ?? false
        case .pageUpHalfScreen:
            return state?.pageUpHalfScreen() ?? false
        case .scrollUp:
            return state?.scrollUp() ?? false
        case .scrollDown:
            return state?.scrollDown() ?? false
        case .pageUp:
            return state?.pageUp() ?? false
        case .pageDown:
            return state?.pageDown() ?? false
        case .toggleCharacterSelection:
            return toggleSelectionMode(.kiTermSelectionModeCharacter)
        case .exitCopyMode:
            enabled = false
            return false
        case .copySelection:
            delegate?.copyModeHandlerCopySelection(self)
            enabled = false
            return false
        case .toggleBoxSelection:
            return toggleSelectionMode(.kiTermSelectionModeBox)
        case .moveBackwardWord:
            return state?.moveBackwardWord() ?? false
        case .moveBackwardBigWord:
            return state?.moveBackwardBigWord() ?? false
        case .moveForwardWord:
            return state?.moveForwardWord() ?? false
        case .moveForwardBigWord:
            return state?.moveForwardBigWord() ?? false
        case .moveToStartOfIndentation:
            return state?.moveToStartOfIndentation() ?? false
        case .moveToStartOfNextLine:
            return state?.moveToStartOfNextLine() ?? false
        case .quit:
            state?.selecting = false
            enabled = false
            return true
        case .moveToStartOfLine, .moveToStartOfLineOrAccrue0:
            return state?.moveToStartOfLine() ?? false
        case .moveToTopOfVisibleArea:
            return state?.moveToTopOfVisibleArea() ?? false
        case .moveToEnd:
            return state?.moveToEnd() ?? false
        case .moveToBottomOfVisibleArea:
            return state?.moveToBottomOfVisibleArea() ?? false
        case .moveToMiddleOfVisibleArea:
            return state?.moveToMiddleOfVisibleArea() ?? false
        case .toggleLineSelection:
            return toggleSelectionMode(.kiTermSelectionModeLine)
        case .moveToStart:
            return state?.moveToStart() ?? false
        case .moveLeft:
            return state?.moveLeft() ?? false
        case .moveDown:
            return state?.moveDown() ?? false
        case .moveUp:
            return state?.moveUp() ?? false
        case .moveRight:
            return state?.moveRight() ?? false
        case .swap:
            state?.swap()
            return true
        case .showFindPanel:
            delegate?.copyModeHandlerShowFindPanel(self)
            return false
        case .previousMark:
            return state?.previousMark() ?? false
        case .nextMark:
            return state?.nextMark() ?? false
        case .moveToEndOfLine:
            return state?.moveToEndOfLine() ?? false
        case .none:
            return false
        }
    }

    private func toggleSelectionMode(_ selectionMode: iTermSelectionMode) -> Bool {
        guard let state else {
            return false
        }
        state.selecting = !state.selecting
        state.mode = selectionMode
        return false
    }

    private func action(for event: NSEvent) -> CopyModeAction {
        var pointless: ObjCBool = false
        let extraEvents = NSMutableArray()
        var name: NSString?
        let handled = keyBindingEmulator.handlesEvent(
            event,
            pointlessly: &pointless,
            extraEvents: extraEvents,
            action: &name)
        guard handled, let name = name as String? else {
            return .none
        }
        return CopyModeAction(rawValue: name) ?? .none
    }

    private func educateAboutCopyMode() {
        guard let url = URL(string: "https://iterm2.com/documentation-copymode.html") else {
            return
        }
        iTermNotificationController.sharedInstance().postNotification(
            withTitle: "Copy Mode",
            detail: "Copy Mode lets you make a selection with the keyboard. Click to view the manual.",
            url: url)
    }
}
