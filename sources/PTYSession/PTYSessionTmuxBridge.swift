//
//  PTYSessionTmuxBridge.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa

private let PTYSessionTmuxPausedAnnouncementIdentifier = "tmuxPaused"
private let PTYSessionTmuxAutoBurialKey = "NoSyncAutoBurialReveal"
private let PTYSessionTmuxAlreadyAttachedIdentifier = "AlreadyAttachedToTmuxSession"
private let PTYSessionTmuxHungIdentifier = "NoSyncTmuxHung"

struct PTYSessionTmuxTTLTracker: Equatable {
    private(set) var hasThresholds = false
    private(set) var lowerThreshold: TimeInterval = 0
    private(set) var upperThreshold: TimeInterval = 0

    mutating func shouldUpdate(ttl: TimeInterval) -> Bool {
        if hasThresholds {
            if ttl > lowerThreshold && ttl < upperThreshold {
                return false
            }
            if ttl <= lowerThreshold {
                lowerThreshold = ttl - 1
                upperThreshold = ttl + 1.5
            } else {
                lowerThreshold = ttl - 1.5
                upperThreshold = ttl + 1
            }
        } else {
            lowerThreshold = ttl - 1
            upperThreshold = ttl + 1
            hasThresholds = true
        }
        return true
    }

    mutating func reset() {
        hasThresholds = false
        lowerThreshold = 0
        upperThreshold = 0
    }
}

enum PTYSessionTmuxSupport {
    static let unlimitedScrollbackLineCount = 10 * 1000 * 1000

    static func commandOutputLines(from response: String) -> [String] {
        return response.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: "\r", with: "")
        }
    }

    static func safeRoundedTTL(_ ttl: TimeInterval) -> Int {
        let rounded = ttl.rounded()
        if rounded.isNaN || rounded >= Double(Int.max) {
            return Int.max
        }
        return max(1, Int(rounded))
    }

    static func pauseWarningMessage(for ttl: TimeInterval) -> String {
        let safeTTL = safeRoundedTTL(ttl)
        let suffix = safeTTL == 1 ? "" : "s"
        return "This session will pause in about \(safeTTL) second\(suffix) because it is buffering too much data."
    }

    static func scrollbackLineCount(unlimitedScrollback: Bool, configuredLines: Int) -> Int {
        if unlimitedScrollback {
            // 10M is close enough to infinity to be indistinguishable.
            return unlimitedScrollbackLineCount
        }
        return configuredLines
    }
}

@objc
final class PTYSessionTmuxState: NSObject {
    @objc var haveKickedOffTmux = false
    @objc var hideAfterTmuxWindowOpens = false
    @objc var tmuxSecureLogging = false
    @objc var tmuxWindowClosingByClientRequest = false
    var ttlTracker = PTYSessionTmuxTTLTracker()
}

extension PTYSession {
    private static let tmuxReadTaskQueue = DispatchQueue(label: "com.iterm2.tmuxReadTask")

    // MARK: - TmuxGatewayDelegate Bridge

    @objc(swift_tmuxOwningSessionGUID)
    func swift_tmuxOwningSessionGUID() -> String {
        return guid
    }

    @objc(swift_tmuxDidOpenInitialWindows)
    func swift_tmuxDidOpenInitialWindows() {
        guard swiftState.tmuxState.hideAfterTmuxWindowOpens else {
            return
        }
        swiftState.tmuxState.hideAfterTmuxWindowOpens = false
        hide()

        let userDefaults = iTermUserDefaults.userDefaults()
        if !userDefaults.bool(forKey: PTYSessionTmuxAutoBurialKey) {
            iTermNotificationController.sharedInstance().notify(
                NSLocalizedString("Session Buried", comment: "User notification"),
                withDescription: NSLocalizedString(
                    "It can be restored by detaching from tmux, or from the Session > Buried Sessions menu.",
                    comment: "User notification"
                )
            )
            userDefaults.set(true, forKey: PTYSessionTmuxAutoBurialKey)
        }
    }

    @objc(swift_tmuxUpdateLayoutForWindow:layout:visibleLayout:zoomed:only:)
    func swift_tmuxUpdateLayout(forWindow windowId: Int32,
                                layout: String,
                                visibleLayout: String,
                                zoomed: NSNumber?,
                                only: Bool) -> Bool {
        DLog("tmuxUpdateLayoutForWindow:\(windowId) layout:\(layout) zoomed:\(String(describing: zoomed)) only:\(only)")
        guard let controller = tmuxController else {
            return false
        }
        guard let tab = controller.window(windowId) else {
            DLog("* NO TAB, DO NOTHING")
            controller.didLearnLayout(layout, forWindow: windowId)
            return false
        }
        let result = controller.setLayoutIn(
            tab,
            toLayout: layout,
            visibleLayout: visibleLayout,
            zoomed: zoomed
        )
        // Do this after the opener for any new panes has registered them.
        controller.didLearnLayout(layout, forWindow: windowId)
        if result && only {
            controller.adjustWindowSizeIfNeeded(for: [tab])
        }
        return result
    }

    @objc(swift_tmuxWindowAddedWithId:)
    func swift_tmuxWindowAdded(withId windowId: Int32) {
        guard let controller = tmuxController else {
            return
        }
        if controller.window(windowId) == nil {
            let tmuxWindow = delegate?.tmuxWindow() ?? -1
            controller.openWindow(
                withId: windowId,
                intentional: false,
                profile: controller.profile(forWindow: tmuxWindow)
            )
        }
        controller.windowsChanged()
    }

    @objc(swift_tmuxWindowClosedWithId:)
    func swift_tmuxWindowClosed(withId windowId: Int32) {
        guard let controller = tmuxController else {
            return
        }
        if let tab = controller.window(windowId) {
            tab.realParentWindow()?.remove(tab)
        }
        controller.windowsChanged()
    }

    @objc(swift_tmuxWindowRenamedWithId:to:)
    func swift_tmuxWindowRenamed(withId windowId: Int32, to newName: String) {
        let representativeSession = tmuxController?.sessions(inWindow: windowId)?.first
        representativeSession?.delegate?.sessionDidChangeTmuxWindowName(to: newName)
        tmuxController?.windowWasRenamed(withId: windowId, to: newName)
    }

    @objc(swift_tmuxInitialCommandDidCompleteSuccessfully)
    func swift_tmuxInitialCommandDidCompleteSuccessfully() {
        // This kicks off a chain reaction that leads to windows being opened.
        if !swiftState.tmuxState.haveKickedOffTmux {
            // In tmux 1.9+ this happens before `tmuxSessionsChanged`.
            swift_kickOffTmux(forRestoration: false)
        }
    }

    // When guessVersion finishes, if you have called openWindowsInitial, then windows will actually get
    // opened. Initial window opening is always blocked on establishing the server version.
    @objc(swift_kickOffTmuxForRestoration:)
    func swift_kickOffTmux(forRestoration restoration: Bool) {
        if restoration {
            sessionTmuxGateway?.enableWritesAfterDelay()
        }
        swiftState.tmuxState.haveKickedOffTmux = true
        // This must be first. See the note in -startTmuxMode:.
        tmuxController?.sendPhonyCommand()
        tmuxController?.ping()
        tmuxController?.validateOptions()
        tmuxController?.checkForUTF8()
        tmuxController?.loadDefaultTerminal()
        tmuxController?.loadKeyBindings()
        tmuxController?.exitCopyMode()
        tmuxController?.guessVersion()  // NOTE: This kicks off more stuff that depends on knowing the version number.
    }

    @objc(swift_tmuxInitialCommandDidFailWithError:)
    func swift_tmuxInitialCommandDidFail(withError error: String) {
        swift_printTmuxMessage("tmux failed with error: “\(error)”")
    }

    @objc(swift_tmuxPrintLine:)
    func swift_tmuxPrintLine(_ line: String) {
        DLog("\(line)")
        screen.mutateAsynchronously { _, mutableState, _ in
            mutableState.appendString(atCursor: line)
            mutableState.appendCarriageReturnLineFeed()
        }
    }

    @objc(swift_tmuxGatewayDidTimeOutDuringInitialization:)
    func swift_tmuxGatewayDidTimeOut(duringInitialization: Bool) {
        if duringInitialization {
            // "Reveal Setting" is a one-time navigation action and shouldn't be remembered.
            let warning = iTermWarning()
            warning.title = "It's taking a long time for tmux to respond. If this is a old or funky system it might expect newline rather than carriage return to end commands. You can adjust the line terminator used by tmux integration in Settings."
            warning.actionLabels = ["OK", "Reveal Setting"]
            warning.identifier = PTYSessionTmuxHungIdentifier
            warning.warningType = .kiTermWarningTypePermanentlySilenceable
            warning.heading = "Slow tmux Response"
            warning.doNotRememberLabels = ["Reveal Setting"]
            let selection = warning.runModal()
            if selection == .kiTermWarningSelection1 {
                revealProfileSetting(withKey: KEY_TMUX_NEWLINE)
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Force Detach?"
        alert.informativeText = "Tmux is not responding. Would you like to force detach?"
        alert.addButton(withTitle: "Detach")
        alert.addButton(withTitle: "Cancel")
        let button: NSApplication.ModalResponse
        if let window = view?.window {
            button = alert.runSheetModal(for: window)
        } else {
            button = alert.runModal()
        }
        if button == .alertFirstButtonReturn {
            sessionTmuxGateway?.forceDetach()
        }
    }

    @objc(swift_tmuxActiveWindowPaneDidChangeInWindow:toWindowPane:)
    func swift_tmuxActiveWindowPaneDidChange(inWindow windowID: Int32, toWindowPane paneID: Int32) {
        tmuxController?.activeWindowPaneDidChange(inWindow: windowID, toWindowPane: paneID)
    }

    @objc(swift_tmuxSessionWindowDidChangeTo:)
    func swift_tmuxSessionWindowDidChange(to windowID: Int32) {
        tmuxController?.activeWindowDidChange(to: windowID)
    }

    @objc(swift_tmuxGatewayShouldForceDetach)
    func swift_tmuxGatewayShouldForceDetach() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Force Detach?"
        alert.informativeText = "A previous detach request has not yet been honored. Force detach?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let button: NSApplication.ModalResponse
        if let window = view?.window {
            button = alert.runSheetModal(for: window)
        } else {
            button = alert.runModal()
        }
        return button == .alertFirstButtonReturn
    }

    @objc(swift_tmuxGatewayWindow)
    func swift_tmuxGatewayWindow() -> (NSWindowController & iTermWindowController)? {
        return delegate?.realParentWindow()
    }

    @objc(swift_tmuxHostDisconnected:)
    func swift_tmuxHostDisconnected(_ dcsID: String) {
        swiftState.tmuxState.hideAfterTmuxWindowOpens = false

        if iTermPreferences.bool(forKey: kPreferenceKeyAutoHideTmuxClientSession),
           let buried = iTermBuriedSessions.sharedInstance()?.buriedSessions(),
           buried.contains(self) {
            // Do this before detaching because it may be the only tab in a hotkey window. If all the
            // tabs close the window is destroyed and it breaks the reference from iTermProfileHotkey.
            // See issue 7384.
            iTermBuriedSessions.sharedInstance()?.restore(self)
        }

        tmuxController?.detach()
        // Autorelease the gateway in ObjC because it called this function so we can't free it immediately.
        tearDownTmuxGatewayConnection()
        screen.mutateAsynchronously { terminal, mutableState, _ in
            mutableState.appendString(atCursor: "Detached")
            mutableState.appendCarriageReturnLineFeed()
            terminal?.parser?.forceUnhookDCS(dcsID)
        }
        setSessionTmuxMode(TMUX_NONE)
        genericScope.setValue(nil, forVariableNamed: iTermVariableKeySessionTmuxClientName)
        genericScope.setValue(nil, forVariableNamed: iTermVariableKeySessionTmuxPaneTitle)
        // Take the gateway decoration off now rather than a main-queue turn later.
        nameController.formattingDescriptorDidChange()
    }

    @objc(swift_tmuxCannotSendCharactersInSupplementaryPlanes:windowPane:)
    func swift_tmuxCannotSendCharactersInSupplementaryPlanes(_ string: String, windowPane: Int32) {
        let targetSession = tmuxController?.session(forWindowPane: windowPane)
        targetSession?.naggingController.tmuxSupplementaryPlaneError(forCharacter: string)
    }

    @objc(swift_tmuxSetSecureLogging:)
    func swift_tmuxSetSecureLogging(_ secureLogging: Bool) {
        swiftState.tmuxState.tmuxSecureLogging = secureLogging
    }

    @objc(swift_tmuxServerMayOmitEndGuardBeforeExit:)
    func swift_tmuxServerMayOmitEndGuardBeforeExit(_ mayOmit: Bool) {
        DLog("\(self): tmux server may omit end guard before exit: \(mayOmit)")
        screen.mutateAsynchronously { terminal, _, _ in
            terminal?.parser?.setTmuxServerMayOmitEndGuardBeforeExit(mayOmit)
        }
    }

    @objc(swift_tmuxWriteString:)
    func swift_tmuxWrite(_ string: String) {
        if exited {
            return
        }
        if swiftState.tmuxState.tmuxSecureLogging {
            DLog("Write to tmux.")
        } else {
            DLog("Write to tmux: \"\(string)\"")
        }
        if sessionTmuxGateway?.tmuxLogging == true {
            swift_printTmuxMessage("> " + string)
        }
        if let conductor, !exited, let data = string.data(using: .utf8) {
            // Running tmux inside an ssh client takes this path
            conductor.sendKeys(data)
        } else {
            writeTask(forTmuxGateway: string)
        }
    }

    @objc(swift_tmuxReadTask:windowPane:latency:)
    func swift_tmuxReadTask(_ data: Data, windowPane wp: Int32, latency: NSNumber?) {
        if let latency {
            tmuxController?.setCurrentLatency(latency.doubleValue, forPane: wp)
        }
        if let targetSession = tmuxController?.session(forWindowPane: wp) {
            targetSession.handleTmuxData(data)
        } else {
            tmuxController?.didDropOutput(data, forPane: wp)
        }
    }

    @objc(swift_handleTmuxData:)
    func swift_handleTmuxData(_ data: Data) {
        if exited {
            return
        }
        logRawTmuxDataIfEnabled(data)

        // Send the bytes from %output in to the write end of a pipe. The data will come out
        // iTermTmuxJobManager.fd, which TaskRegister selects on. The purpose of this pipe is to
        // let tmux provide backpressure to the pty. We still do the write on tmuxQueue so we don't
        // block the main queue while TaskNotifier exerts backpressure.
        weak let handle = tmuxClientWritePipe
        Self.tmuxReadTaskQueue.async {
            guard let handle else {
                return
            }
            do {
                try handle.write(contentsOf: data)
            } catch {
                DLog("\(error) while writing to tmux pipe")
            }
        }
    }

    @objc(swift_tmuxSessionPasteDidChange:)
    func swift_tmuxSessionPasteDidChange(_ pasteBufferName: String) {
        if iTermPreferences.bool(forKey: kPreferenceKeyTmuxSyncClipboard) {
            tmuxController?.copyBuffer(toLocalPasteboard: pasteBufferName)
        } else {
            iTermController.sharedInstance()?.currentTerminal?.currentSession()?.askToMirrorTmuxPasteBuffer()
        }
    }

    @objc(swift_askToMirrorTmuxPasteBuffer)
    func swift_askToMirrorTmuxPasteBuffer() {
        naggingController.tmuxDidUpdatePasteBuffer()
    }

    @objc(swift_tmuxWindowPaneDidPause:notification:)
    func swift_tmuxWindowPaneDidPause(_ wp: Int32, notification: Bool) {
        let targetSession = tmuxController?.session(forWindowPane: wp)
        targetSession?.setTmuxPaused(true, allowAutomaticUnpause: notification)
    }

    @objc(swift_tmuxClientSessionChanged:)
    func swift_tmuxClientSessionChanged(_ clientName: String) {
        DLog("Client session changed for \(clientName)")
        tmuxController?.clientSessionChanged(clientName)
    }

    @objc(swift_tmuxClientDetached:)
    func swift_tmuxClientDetached(_ clientName: String) {
        DLog("Client detached: \(clientName)")
        tmuxController?.clientDetached(clientName)
    }

    @objc(swift_setTmuxPaused:allowAutomaticUnpause:)
    func swift_setTmuxPaused(_ paused: Bool, allowAutomaticUnpause: Bool) {
        if tmuxPaused == paused {
            return
        }
        setSessionTmuxPaused(paused)
        if paused {
            swiftState.tmuxState.ttlTracker.reset()
            tmuxController?.didPausePane(tmuxPane)
            if allowAutomaticUnpause && iTermPreferences.bool(forKey: kPreferenceKeyTmuxUnpauseAutomatically) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.setTmuxPaused(false, allowAutomaticUnpause: true)
                }
                return
            }
            swift_showTmuxPausedAnnouncement(allowAutomaticUnpause)
        } else {
            swift_unpauseTmux()
        }
    }

    @objc(swift_showTmuxPausedAnnouncement:)
    func swift_showTmuxPausedAnnouncement(_ notification: Bool) {
        let title = notification
            ? "tmux paused this session because too much output was buffered."
            : "Session paused."

        dismissAnnouncement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier)
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .warning,
            withActions: ["_Unpause", "_Settings"]
        ) { [weak self] selection in
            switch selection {
            case 0:
                self?.setTmuxPaused(false, allowAutomaticUnpause: true)
            case 1:
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyTmuxPauseModeAgeLimit)
                self?.showTmuxPausedAnnouncement(notification)
            default:
                break
            }
        }
        dismissAnnouncement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier)
        removeAnnouncement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier)
        queueAnnouncement(announcement, identifier: PTYSessionTmuxPausedAnnouncementIdentifier)
    }

    @objc(swift_setTmuxHistory:altHistory:state:)
    func swift_setTmuxHistory(_ history: TmuxHistory?,
                              altHistory: TmuxHistory?,
                              state: [AnyHashable: Any]) {
        screen.performBlock(joinedThreads: { [weak self] terminal, mutableState, _ in
            guard let self else {
                return
            }
            self.reallySetTmuxHistory(
                history,
                altHistory: altHistory,
                state: state,
                terminal: terminal,
                mutableState: mutableState
            )
        })
    }

    private func reallySetTmuxHistory(_ history: TmuxHistory?,
                                      altHistory: TmuxHistory?,
                                      state: [AnyHashable: Any],
                                      terminal: VT100Terminal?,
                                      mutableState: VT100ScreenMutableState) {
        terminal?.resetForTmuxUnpause()
        clearScrollbackBuffer()
        if let history {
            mutableState.setHistory(history)
        }
        if let altData = altHistory?.data {
            mutableState.setAltScreen(altData)
        }
        swift_setTmuxState(state)
        view?.scrollview.ptyVerticalScroller()?.userScroll = false
    }

    @objc(swift_toggleTmuxPausePane)
    func swift_toggleTmuxPausePane() {
        if tmuxPaused {
            setTmuxPaused(false, allowAutomaticUnpause: true)
        } else {
            tmuxController?.pausePanes([NSNumber(value: tmuxPane)])
        }
    }

    @objc(swift_setTmuxState:)
    func swift_setTmuxState(_ state: [AnyHashable: Any]) {
        setTmuxPaneKeyModeString(state[kStateDictPaneKeyMode] as? String)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setTmux(state)
        })
    }

    @objc(swift_unpauseTmux)
    func swift_unpauseTmux() {
        dismissAnnouncement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier)
        _ = unzoomIfPossible()
        tmuxController?.unpausePanes([NSNumber(value: tmuxPane)])
    }

    @objc(swift_pauseTmux)
    func swift_pauseTmux() {
        tmuxController?.pausePanes([NSNumber(value: tmuxPane)])
    }

    @objc(swift_tmuxSessionChanged:sessionId:)
    func swift_tmuxSessionChanged(_ sessionName: String, sessionId: Int32) {
        tmuxController?.sessionChanged(to: sessionName, sessionId: sessionId)
        if !swiftState.tmuxState.haveKickedOffTmux {
            // Tell the tmux controller we want to open initial windows after version guessing finishes.
            tmuxController?.openWindowsInitial()
            // In tmux 1.8, this happens before `tmuxInitialCommandDidCompleteSuccessfully`.
            swift_kickOffTmux(forRestoration: false)
        }
    }

    @objc(swift_tmuxSessionsChanged)
    func swift_tmuxSessionsChanged() {
        tmuxController?.sessionsChanged()
    }

    @objc(swift_tmuxWindowsDidChange)
    func swift_tmuxWindowsDidChange() {
        tmuxController?.windowsChanged()
    }

    @objc(swift_tmuxSession:renamed:)
    func swift_tmuxSession(_ sessionId: Int32, renamed newName: String) {
        tmuxController?.session(sessionId, renamedTo: newName)
    }

    @objc(swift_tmuxClientSize)
    func swift_tmuxClientSize() -> VT100GridSize {
        guard let delegate else {
            DLog("No delegate so use saved grid size \(VT100GridSizeDescription(savedGridSize))")
            return savedGridSize
        }
        let tmuxWindow = delegate.tmuxWindow()
        DLog("Get size from delegate \(delegate), controller \(String(describing: tmuxController)), window \(tmuxWindow)")
        return delegate.sessionTmuxSize(withProfile: tmuxController?.profile(forWindow: tmuxWindow) ?? [:])
    }

    @objc(swift_tmuxNumberOfLinesOfScrollbackHistory)
    func swift_tmuxNumberOfLinesOfScrollbackHistory() -> Int {
        let tmuxWindow = delegate?.tmuxWindow() ?? -1
        var targetProfile = tmuxController?.profile(forWindow: tmuxWindow)
        if iTermPreferences.useTmuxProfile() {
            targetProfile = ProfileModel.sharedInstance()?.tmuxProfile()
        }
        let unlimited = (targetProfile?[KEY_UNLIMITED_SCROLLBACK] as? NSNumber)?.boolValue ?? false
        let lines = (targetProfile?[KEY_SCROLLBACK_LINES] as? NSNumber)?.intValue ?? 0
        return PTYSessionTmuxSupport.scrollbackLineCount(
            unlimitedScrollback: unlimited,
            configuredLines: lines
        )
    }

    @objc(swift_tmuxDoubleAttachForSessionGUID:)
    func swift_tmuxDoubleAttach(forSessionGUID sessionGUID: String) {
        let controller = TmuxControllerRegistry.sharedInstance()?.tmuxController(withSessionGUID: sessionGUID)
        let actions = controller != nil ? ["OK", "Reveal", "Force Detach Other"] : ["OK"]
        let selection = iTermWarning.show(
            withTitle: "This instance of Latterm is already attached to this session",
            actions: actions,
            accessory: nil,
            identifier: PTYSessionTmuxAlreadyAttachedIdentifier,
            silenceable: .kiTermWarningTypePersistent,
            heading: "Cannot Attach",
            window: view?.window
        )
        switch selection {
        case .kiTermWarningSelection0:
            return
        case .kiTermWarningSelection1:
            break
        case .kiTermWarningSelection2:
            controller?.gateway.forceDetach()
            return
        default:
            it_fatalError("Unexpected warning selection \(selection)")
        }

        let sortedClients = (controller?.clientSessions() ?? [])
            .sorted { $0.guid < $1.guid }
        let targetSession = sortedClients.first ?? PTYSession.cast(from: controller?.gateway.delegate)
        guard let targetSession else {
            (iTermApplication.shared().delegate as? iTermApplicationDelegate)?.openDashboard(nil)
            return
        }
        targetSession.reveal()
    }

    @objc(swift_tmuxWillKillWindow:)
    func swift_tmuxWillKillWindow(_ notification: Notification) {
        if let windowID = (notification.object as? NSNumber)?.int32Value,
           delegate?.tmuxWindow() == windowID {
            swiftState.tmuxState.tmuxWindowClosingByClientRequest = true
        }
    }

    // MARK: - tmux Output

    @objc(swift_printTmuxMessage:)
    func swift_printTmuxMessage(_ message: String) {
        DLog("\(message)")
        if exited {
            return
        }
        // Use mutateAsync because you get here from a side-effect.
        screen.mutateAsynchronously { terminal, mutableState, _ in
            guard let terminal else {
                mutableState.appendString(atCursor: message)
                mutableState.appendCarriageReturnLineFeed()
                return
            }
            let savedFgColor = terminal.foregroundColorCode
            let savedBgColor = terminal.backgroundColorCode
            terminal.setForegroundColor(Int32(ALTSEM_DEFAULT), alternateSemantics: true)
            terminal.setBackgroundColor(Int32(ALTSEM_DEFAULT), alternateSemantics: true)
            terminal.updateDefaultChar()
            mutableState.currentGrid.defaultChar = terminal.defaultChar
            mutableState.appendString(atCursor: message)
            mutableState.appendCarriageReturnLineFeed()
            terminal.setForegroundColor(
                Int32(savedFgColor.foregroundColor),
                alternateSemantics: savedFgColor.foregroundColorMode == ColorModeAlternate.rawValue
            )
            terminal.setBackgroundColor(
                Int32(savedBgColor.backgroundColor),
                alternateSemantics: savedBgColor.backgroundColorMode == ColorModeAlternate.rawValue
            )
            terminal.updateDefaultChar()
            mutableState.currentGrid.defaultChar = terminal.defaultChar
        }
    }

    @objc(swift_printTmuxCommandOutputToScreen:)
    func swift_printTmuxCommandOutput(toScreen response: String) {
        for line in PTYSessionTmuxSupport.commandOutputLines(from: response) {
            swift_printTmuxMessage(line)
        }
    }

    // MARK: - iTermTmuxControllerSession

    @objc(swift_tmuxControllerSessionSetTTL:redzone:)
    func swift_tmuxControllerSessionSetTTL(_ ttl: TimeInterval, redzone: Bool) {
        if tmuxPaused {
            return
        }
        if !iTermPreferences.bool(forKey: kPreferenceKeyTmuxWarnBeforePausing) {
            return
        }
        guard swiftState.tmuxState.ttlTracker.shouldUpdate(ttl: ttl) else {
            return
        }

        if !redzone {
            dismissAnnouncement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier)
            return
        }
        let title = PTYSessionTmuxSupport.pauseWarningMessage(for: ttl)
        if let existing = announcement(withIdentifier: PTYSessionTmuxPausedAnnouncementIdentifier) {
            existing.title = title
            existing.view.needsDisplay = true
            view?.updateAnnouncementFrame()
            return
        }
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: title,
            style: .warning,
            withActions: ["_Pause Settings"]
        ) { selection in
            if selection == 0 {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyTmuxPauseModeAgeLimit)
            }
        }
        announcement.dismissOnKeyDown = true
        queueAnnouncement(announcement, identifier: PTYSessionTmuxPausedAnnouncementIdentifier)
    }
}
