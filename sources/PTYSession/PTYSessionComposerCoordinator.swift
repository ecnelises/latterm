//
//  PTYSessionComposerCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Carbon.HIToolbox
import Cocoa

/// Layout calculations for the auto-composer and top dropdown composer frames.
struct PTYSessionComposerLayoutCalculator {
    struct AutoComposerInput {
        var previousFrame: NSRect
        var paneSize: NSSize
        var desiredHeight: CGFloat
        var lineHeight: CGFloat
        var cursorY: Int32
        var promptStartY: Int32?
        var totalScrollbackOverflow: Int64
        var numberOfScrollbackLines: Int32
        var screenHeight: Int32
        var verticalMargin: CGFloat
        var titleBarHeight: CGFloat
    }

    struct TopComposerInput {
        var previousFrame: NSRect
        var paneSize: NSSize
        var desiredHeight: CGFloat
        var preferredOffsetFromTop: CGFloat
    }

    static func autoComposerFrame(_ input: AutoComposerInput) -> NSRect {
        let maxWidth = input.paneSize.width - input.previousFrame.origin.x * 2
        var lineAbove = Int(input.cursorY) + 1
        if let promptStartY = input.promptStartY, promptStartY >= 0 {
            let computed = Int64(promptStartY) - input.totalScrollbackOverflow - Int64(input.numberOfScrollbackLines)
            lineAbove = max(1, Int(computed))
        }
        let actualLinesAboveComposer = max(1, Int(input.screenHeight) - lineAbove)
        let desiredLines = Int(ceil(input.desiredHeight / input.lineHeight))
        let linesOfHeight = min(actualLinesAboveComposer, desiredLines)
        let gridOffsetInRows = Int(input.screenHeight) - linesOfHeight
        let height = (CGFloat(linesOfHeight) + 0.5) * input.lineHeight
        let gridOffsetInPoints = CGFloat(gridOffsetInRows) * input.lineHeight
        let top = input.verticalMargin + input.titleBarHeight + gridOffsetInPoints
        let y = max(0, input.paneSize.height - top - height)

        DLog("width=\(maxWidth) actualLinesFree=\(actualLinesAboveComposer) gridOffsetInRows=\(gridOffsetInRows) lineHeight=\(input.lineHeight) titleBarHeight=\(input.titleBarHeight) height=\(height) gridOffsetInPoints=\(gridOffsetInPoints) top=\(top) y=\(y)")
        return NSRect(x: input.previousFrame.origin.x,
                      y: y,
                      width: maxWidth,
                      height: height)
    }

    static func topComposerFrame(_ input: TopComposerInput) -> NSRect {
        let maxWidth = input.paneSize.width - input.previousFrame.origin.x * 2
        let width = max(217, maxWidth)
        // Preserve the existing height semantics: `height` tracks the input desiredHeight
        // even after y is clamped against paneSize.height.
        let height = input.desiredHeight
        var y = max(0, input.paneSize.height - height - input.preferredOffsetFromTop)
        let overage = (y + height) - input.paneSize.height
        if overage > 0 {
            y = max(0, y - overage)
        }
        return NSRect(x: input.previousFrame.origin.x,
                      y: y,
                      width: width,
                      height: height)
    }
}

/// Key equivalent actions handled on behalf of the minimal composer.
enum PTYSessionComposerKeyEquivalentAction: Equatable {
    case none
    case previousMark
    case nextMark
}

/// Pure policy decisions for composer suggestions, key handling, and auto-composer text submission.
struct PTYSessionComposerPolicy {
    static func keyEquivalentAction(modifierFlags: NSEvent.ModifierFlags,
                                    keyCode: UInt16) -> PTYSessionComposerKeyEquivalentAction {
        let mask: NSEvent.ModifierFlags = [.option, .command, .shift, .control]
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        guard modifierFlags.intersection(mask) == cmdShift else {
            return .none
        }
        if keyCode == UInt16(kVK_UpArrow) {
            return .previousMark
        }
        if keyCode == UInt16(kVK_DownArrow) {
            return .nextMark
        }
        return .none
    }

    static func shouldFetchSuggestions(isRemoteHost: Bool,
                                       conductorFraming: Bool,
                                       hasTmuxController: Bool) -> Bool {
        if isRemoteHost {
            return conductorFraming
        }
        if hasTmuxController {
            return false
        }
        return true
    }

    static func shouldHandleKeyBinding(hasAction: Bool,
                                       sendsText: Bool,
                                       isNavigation: Bool) -> Bool {
        guard hasAction else {
            return false
        }
        // Prevent natural text editing presets from interfering with composer navigation.
        return !(sendsText || isNavigation)
    }

    static func preparedAutoComposerCommand(_ command: String,
                                            haveShellProvidedText: Bool) -> String {
        guard haveShellProvidedText else {
            return command
        }
        // Send ^U first to erase shell-provided text before inserting the submitted command.
        return "\u{15}" + command
    }
}

/// Coordinates `iTermComposerManagerDelegate` behavior, file checking, and command submission.
@objc
final class PTYSessionComposerCoordinator: NSObject, iTermComposerManagerDelegate {
    private weak var session: PTYSession?
    private var localFileChecker: LocalFileChecker?

    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - Session Integration Helpers

    @objc
    func haveAutoComposer() -> Bool {
        guard let composerManager = session?.existingComposerManager else {
            return false
        }
        return composerManager.dropDownComposerViewIsVisible && composerManager.isAutoComposer
    }

    @objc(updateLocalFileCheckerWorkingDirectory:)
    func updateLocalFileCheckerWorkingDirectory(_ directory: String) {
        MainActor.assumeIsolated {
            localFileChecker?.workingDirectory = directory
        }
    }

    @objc
    func fileChecker() -> FileChecker {
        return MainActor.assumeIsolated {
            if let conductor = session?.conductor,
               conductor.canCheckFiles,
               let remoteChecker = conductor.fileChecker {
                return remoteChecker
            }
            if let localFileChecker {
                return localFileChecker
            }
            let checker = LocalFileChecker(shell: session?.bestGuessAtUserShell(withPath: true))
            if let dir = session?.lastLocalDirectory {
                checker.workingDirectory = dir
            }
            localFileChecker = checker
            return checker
        }
    }

    @objc(sendCommand:)
    func sendCommand(_ command: String) {
        guard let session else {
            return
        }
        if haveAutoComposer(), let composerManager = session.existingComposerManager {
            let finalCommand = PTYSessionComposerPolicy.preparedAutoComposerCommand(
                command,
                haveShellProvidedText: composerManager.haveShellProvidedText
            )
            if iTermAdvancedSettingsModel.smartLoggingWithAutoComposer() {
                let trimmed = finalCommand.trimmingTrailingCharacters(from: .newlines)
                session.logCookedComposerCommand(trimmed)
            }
            let detectedByTrigger = (composerManager.prefixUserData as? [AnyHashable: Any])?[PTYSessionComposerPrefixUserDataKeyDetectedByTrigger] as? Bool ?? false
            composerManager.setPrefix(nil, userData: nil)
            session.screen.mutateAsynchronously { [weak self] _, mutableState, _ in
                DLog("willSendCommand:\(finalCommand)")
                let grid = mutableState.currentGrid
                let start = VT100GridAbsCoordMake(
                    grid.cursor.x,
                    Int64(grid.cursor.y) + Int64(mutableState.numberOfScrollbackLines) + mutableState.cumulativeScrollbackOverflow
                )
                mutableState.composerWillSendCommand(finalCommand, startingAt: start)
                if detectedByTrigger {
                    mutableState.didSendCommand()
                }
                DispatchQueue.main.async {
                    self?.reallySendCommand(finalCommand)
                }
            }
            DLog("Dismiss composer and request redraw")
            _ = composerManager.dismiss(animated: false)
            session.textview?.requestDelegateRedraw()
            return
        }
        reallySendCommand(command)
    }

    private func reallySendCommand(_ command: String) {
        guard let session else {
            return
        }
        DLog("reallySendCommand: \(command)")
        session.writeTask(command)
        session.screen.userDidPressReturn()
    }

    @objc
    func updateAutoComposerSeparatorVisibility() {
        guard let session,
              let composerManager = session.existingComposerManager else {
            return
        }
        composerManager.isSeparatorVisible = shouldShowAutoComposerSeparator()
        if let backgroundColor = session.screen.colorMap.color(forKey: kColorMapBackground) {
            composerManager.separatorColor = iTermTextDrawingHelper.color(forLineStyleMark: .success,
                                                                          backgroundColor: backgroundColor)
        }
    }

    private func shouldShowAutoComposerSeparator() -> Bool {
        return haveAutoComposer()
    }

    // MARK: - iTermComposerManagerDelegate

    func composerManagerStatusBarViewController(_ composerManager: iTermComposerManager) -> iTermStatusBarViewController? {
        return session?.statusBarViewController
    }

    func composerManagerScope(_ composerManager: iTermComposerManager) -> iTermVariableScope {
        guard let scope = session?.genericScope else {
            return iTermVariableScope()
        }
        return scope
    }

    func composerManagerContainerView(_ composerManager: iTermComposerManager) -> NSView? {
        return session?.view
    }

    func composerManager(_ composerManager: iTermComposerManager, minimalFrameDidChangeTo newFrame: NSRect) {
        session?.textview?.requestDelegateRedraw()
        DLog("Composer frame changed to \(NSStringFromRect(newFrame))")
    }

    func composerManager(_ composerManager: iTermComposerManager,
                         frameForDesiredHeight desiredHeight: CGFloat,
                         previousFrame: NSRect,
                         preferredOffsetFromTop: CGFloat) -> NSRect {
        guard let session, let view = session.view else {
            return previousFrame
        }
        let paneSize = view.frame.size
        if composerManager.isAutoComposer {
            let screen = session.screen
            let mark = screen.lastPromptMark()
            let promptStartY: Int32? = mark.map { Int32(clamping: $0.promptRange.start.y) }
            return PTYSessionComposerLayoutCalculator.autoComposerFrame(
                .init(previousFrame: previousFrame,
                      paneSize: paneSize,
                      desiredHeight: desiredHeight,
                      lineHeight: session.textview?.lineHeight ?? 0,
                      cursorY: screen.currentGrid().cursor.y,
                      promptStartY: promptStartY,
                      totalScrollbackOverflow: screen.totalScrollbackOverflow(),
                      numberOfScrollbackLines: screen.numberOfScrollbackLines(),
                      screenHeight: screen.height(),
                      verticalMargin: CGFloat(iTermPreferences.topBottomMargins()),
                      titleBarHeight: view.showTitle() ? SessionView.titleHeight() : 0)
            )
        }
        return PTYSessionComposerLayoutCalculator.topComposerFrame(
            .init(previousFrame: previousFrame,
                  paneSize: paneSize,
                  desiredHeight: desiredHeight,
                  preferredOffsetFromTop: preferredOffsetFromTop)
        )
    }

    func composerManagerAutoComposerTextDidChange(_ composerManager: iTermComposerManager) {
    }

    func composerManager(_ composerManager: iTermComposerManager, desiredHeightDidChange desiredHeight: CGFloat) {
        DLog("Desired height changed to \(desiredHeight)")
        session?.sync()
    }

    func composerManagerLineHeight(_ composerManager: iTermComposerManager) -> CGFloat {
        return session?.textview?.lineHeight ?? 0
    }

    func composerManagerClear(_ composerManager: iTermComposerManager) {
        session?.screen.mutateAsynchronously { _, mutableState, _ in
            mutableState.clearForComposer()
        }
    }

    func composerManagerOpenHistory(_ composerManager: iTermComposerManager,
                                    prefix: String,
                                    forSearch: Bool) {
    }

    func composerManagerShowCompletions(_ completions: [String]) {
    }

    func composerManagerDidRemoveTemporaryStatusBarComponent(_ composerManager: iTermComposerManager) {
        guard let session else {
            return
        }
        session.pasteHelper?.temporaryRightStatusBarComponentDidBecomeAvailable()
        if let responder = session.mainResponder {
            session.textview?.window?.makeFirstResponder(responder)
        }
    }

    func composerManager(_ composerManager: iTermComposerManager, enqueueCommand command: String) {
        guard let session else {
            return
        }
        if let currentCommand = session.currentCommand, currentCommand.isEmpty {
            // At shell prompt
            sendCommand(command)
            return
        }
        // Send when next mark is received.
        session.enqueueComposerCommand(command)
    }

    func composerManager(_ composerManager: iTermComposerManager, sendCommand command: String) {
        sendCommand(command)
    }

    func composerManagerHandleKeyDown(_ event: NSEvent) -> Bool {
        guard let session else {
            return false
        }
        let keystroke = iTermKeystroke.withEvent(event)
        let action = iTermKeyMappings.action(for: keystroke,
                                             keyMappings: session.profile?[KEY_KEYBOARD_MAP] as? [AnyHashable: Any])
        guard let action,
              PTYSessionComposerPolicy.shouldHandleKeyBinding(
                hasAction: true,
                sendsText: action.sendsText,
                isNavigation: keystroke.isNavigation
              ) else {
            return false
        }
        DLog("PTYSession keyDown action=\(action)")
        session.perform(action, event: event)
        DLog("Special handler: KEY BINDING ACTION")
        return true
    }

    func composerManagerNextResponder() -> NSResponder? {
        return session?.textview
    }

    func composerManager(_ composerManager: iTermComposerManager, forwardMenuItem menuItem: NSMenuItem) {
        session?.forwardComposerMenuItem(menuItem)
    }

    func composerManager(_ composerManager: iTermComposerManager, preferredOffsetFromTopDidChange offset: CGFloat) {
        guard let session else {
            return
        }
        if session.isDivorced {
            guard let originalProfile = session.originalProfile,
                  let model = ProfileModel.sharedInstance(),
                  let guid = originalProfile[KEY_GUID] as? String,
                  model.bookmark(withGuid: guid) != nil else {
                return
            }
            iTermProfilePreferences.setObject(NSNumber(value: offset),
                                              forKey: KEY_COMPOSER_TOP_OFFSET,
                                              inProfile: originalProfile,
                                              model: model)
            return
        }
        if let profile = session.profile {
            iTermProfilePreferences.setObject(NSNumber(value: offset),
                                              forKey: KEY_COMPOSER_TOP_OFFSET,
                                              inProfile: profile,
                                              model: session.profileModel())
        }
    }

    func composerManagerShouldForwardCopy(_ composerManager: iTermComposerManager) -> Bool {
        guard haveAutoComposer() else {
            return false
        }
        return session?.textview?.canCopy ?? false
    }

    func composerManager(_ composerManager: iTermComposerManager,
                         syntaxHighlighterFor attributedString: NSMutableAttributedString) -> (any SyntaxHighlighting)? {
        guard let session,
              let textview = session.textview else {
            return nil
        }
        return MainActor.assumeIsolated { () -> iTermSyntaxHighlighter? in
            iTermSyntaxHighlighter(attributedString,
                                   colorMap: session.screen.colorMap,
                                   fontTable: textview.fontTable,
                                   fileChecker: fileChecker())
        }
    }

    func composerManagerDidBecomeFirstResponder(_ composerManager: iTermComposerManager) {
        DLog("composerManagerDidBecomeFirstResponder")
    }

    func composerManagerShouldFetchSuggestions(_ composerManager: iTermComposerManager,
                                               forHost remoteHost: (any VT100RemoteHostReading)?,
                                               tmuxController: TmuxController?) -> Bool {
        let framing = MainActor.assumeIsolated { session?.conductor?.framing ?? false }
        return PTYSessionComposerPolicy.shouldFetchSuggestions(
            isRemoteHost: remoteHost?.isRemoteHost ?? false,
            conductorFraming: framing,
            hasTmuxController: tmuxController != nil
        )
    }

    func composerManager(_ composerManager: iTermComposerManager,
                         valueOfEnvironmentVariable name: String) -> String? {
        guard let conductor = session?.conductor else {
            return nil
        }
        return MainActor.assumeIsolated {
            conductor.framing ? conductor.environmentVariables[name] : nil
        }
    }

    func composerManager(_ composerManager: iTermComposerManager,
                         fetchSuggestions request: SuggestionRequest,
                         byUserRequest: Bool) {
        guard let session else {
            return
        }
        if let conductor = session.conductor {
            let handledByConductor = MainActor.assumeIsolated { () -> Bool in
                guard conductor.framing else {
                    return false
                }
                conductor.fetchSuggestions(request, suggestionOnly: byUserRequest)
                return true
            }
            if handledByConductor {
                return
            }
        }
        session.findSlowCompletions(withPrefix: request.prefix,
                                    inDirectories: request.directories,
                                    workingDirectory: request.workingDirectory,
                                    maxCount: request.limit,
                                    executable: request.executable) { completions in
            let fileItems = completions.map { filename in
                CompletionItem(value: filename,
                               detail: request.prefix + filename,
                               kind: .file)
            }
            request.completion(!byUserRequest, fileItems)
        }
    }

    func composerManager(_ composerManager: iTermComposerManager,
                         sendToAdvancedPaste command: String) {
        session?.openAdvancedPaste(withText: command, escaping: .none)
    }

    func composerManager(_ composerManager: iTermComposerManager, sendControl control: String) {
        session?.writeTask(control)
    }

    func composerManager(_ composerManager: iTermComposerManager, wantsKeyEquivalent event: NSEvent) -> Bool {
        switch PTYSessionComposerPolicy.keyEquivalentAction(modifierFlags: event.modifierFlags,
                                                            keyCode: event.keyCode) {
        case .previousMark:
            session?.delegate?.realParentWindow()?.previousMark(nil)
            return true
        case .nextMark:
            session?.delegate?.realParentWindow()?.nextMark(nil)
            return true
        case .none:
            return false
        }
    }

    func composerManager(_ composerManager: iTermComposerManager, performFindPanelAction sender: Any) {
        session?.textview?.performFindPanelAction(sender)
    }

    func composerManagerWillDismissMinimalView(_ composerManager: iTermComposerManager) {
        if let responder = session?.mainResponder {
            session?.textview?.window?.makeFirstResponder(responder)
        }
        composerManager.isSeparatorVisible = false
    }

    func composerManagerDidDisplayMinimalView(_ composerManager: iTermComposerManager) {
        updateAutoComposerSeparatorVisibility()
    }

    func composerManagerDidDismissMinimalView(_ composerManager: iTermComposerManager) {
        session?.view?.composerHeight = 0
        MainActor.assumeIsolated {
            localFileChecker?.reset()
            session?.conductor?.fileChecker?.reset()
        }
    }

    func composerManagerAppearance(_ composerManager: iTermComposerManager) -> NSAppearance? {
        let color = session?.screen.colorMap.color(forKey: kColorMapBackground)
        if color?.isDark == true {
            return NSAppearance(named: .darkAqua)
        }
        return NSAppearance(named: .aqua)
    }

    func composerManagerRemoteHost(_ composerManager: iTermComposerManager) -> (any VT100RemoteHostReading)? {
        return session?.currentHost
    }

    func composerManagerWorkingDirectory(_ composerManager: iTermComposerManager) -> String? {
        return session?.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String
    }

    func composerManagerShell(_ composerManager: iTermComposerManager) -> String {
        return session?.bestGuessAtUserShell(withPath: false) ?? ""
    }

    func composerManagerUName(_ composerManager: iTermComposerManager) -> String {
        return session?.bestGuessAtUName() ?? ""
    }

    func composerManagerTmuxController(_ composerManager: iTermComposerManager) -> TmuxController? {
        guard let session, session.isTmuxClient else {
            return nil
        }
        return session.tmuxController
    }

    func composerManagerFont(_ composerManager: iTermComposerManager) -> NSFont? {
        return session?.textview?.fontTable.asciiFont.font
    }

    func composerManagerTextColor(_ composerManager: iTermComposerManager) -> NSColor? {
        return session?.textview?.colorMap.color(forKey: kColorMapForeground)
    }

    func composerManagerCursorColor(_ composerManager: iTermComposerManager) -> NSColor? {
        return session?.textview?.colorMap.color(forKey: kColorMapCursor)
    }
}
