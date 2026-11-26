//
//  PTYSessionInputModeCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 3) to isolate key mappers,
//  meta-frustration detection, copy mode, shortcut navigation, and
//  pasteboard reporting delegates.
//

import Cocoa

enum PTYSessionMetaFrustrationPolicy {
    enum Action: Equatable {
        case changeThisProfile
        case changeAllProfiles
        case stopAsking
        case dismiss
    }

    struct PromptSpec: Equatable {
        let leftOrRight: String
        let profileKey: String
        let title: String
        let actions: [String]
        let allProfilesIndex: Int?
    }

    static func promptSpec(left: Bool, profileCount: Int) -> PromptSpec {
        let leftOrRight = left ? "left" : "right"
        let profileKey = left ? KEY_OPTION_KEY_SENDS : KEY_RIGHT_OPTION_KEY_SENDS
        let title = "You seem frustrated. Would you like the \(leftOrRight) option key to send esc+keystroke?"
        if profileCount == 1 {
            return PromptSpec(
                leftOrRight: leftOrRight,
                profileKey: profileKey,
                title: title,
                actions: ["Yes", "Stop Asking"],
                allProfilesIndex: nil
            )
        }
        return PromptSpec(
            leftOrRight: leftOrRight,
            profileKey: profileKey,
            title: title,
            actions: ["Change This Profile", "Change All Profiles", "Stop Asking"],
            allProfilesIndex: 1
        )
    }

    static func action(forSelection selection: Int32, profileCount: Int) -> Action {
        if selection < 0 {
            return .dismiss
        }
        if selection == 0 {
            return .changeThisProfile
        }
        if profileCount != 1 && selection == 1 {
            return .changeAllProfiles
        }
        return .stopAsking
    }
}

enum PTYSessionShortcutNavigationPolicy {
    struct ShortcutCandidate {
        let keyEquivalent: String
        let terminating: Bool
    }

    static func isCommandPrefix(_ characters: String, in candidates: [ShortcutCandidate]) -> Bool {
        return candidates.contains { candidate in
            guard !candidate.terminating else { return false }
            return candidate.keyEquivalent.lowercased().hasPrefix(characters)
        }
    }

    static func matchingIndex(forKeyEquivalent characters: String,
                              in candidates: [ShortcutCandidate]) -> Int? {
        return candidates.firstIndex { candidate in
            guard !candidate.terminating else { return false }
            return candidate.keyEquivalent.caseInsensitiveCompare(characters) == .orderedSame
        }
    }
}

enum PTYSessionCopyModeInitialStatePolicy {
    static func initialCursorCoord(cursorX: Int32,
                                   cursorY: Int32,
                                   scrollbackLines: Int32) -> VT100GridCoord {
        return VT100GridCoordMake(cursorX - 1, cursorY - 1 + scrollbackLines)
    }
}

enum PTYSessionPasteboardPolicy {
    enum Route: Equatable {
        case tmuxOSC52
        case directReport
        case ignore
    }

    struct PermissionDecision: Equatable {
        let allowed: Bool
        let permanently: Bool
    }

    static func route(isTmuxClient: Bool, tmuxShouldHandleOSC52Queries: Bool) -> Route {
        if tmuxShouldHandleOSC52Queries {
            return .tmuxOSC52
        }
        if !isTmuxClient {
            return .directReport
        }
        return .ignore
    }

    static func permissionDecision(forSelection selection: Int32) -> PermissionDecision {
        switch selection {
        case 0:
            return PermissionDecision(allowed: true, permanently: false)
        case 1:
            return PermissionDecision(allowed: true, permanently: true)
        case 2:
            return PermissionDecision(allowed: false, permanently: true)
        default:
            return PermissionDecision(allowed: false, permanently: false)
        }
    }
}

@objc final class PTYSessionInputModeCoordinator: NSObject,
    iTermMetaFrustrationDetectorDelegate,
    ModernKeyMapperDelegate,
    iTermStandardKeyMapperDelegate,
    iTermTermkeyKeyMapperDelegate,
    iTermModifyOtherKeysMapperDelegate,
    iTermShortcutNavigationModeHandlerDelegate,
    iTermCopyModeHandlerDelegate,
    PasteboardReporterDelegate {

    private static let neverPromptOptionKeyDefaultsKey = "NoSyncNeverPromptToChangeOption"
    private static let metaFrustrationIdentifier = "OfferToChangeOptionKeyToSendESC"

    private weak var session: PTYSession?

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - iTermMetaFrustrationDetector

    @objc func metaFrustrationDetectorDidDetectFrustrationForLeftOption() {
        maybeOfferToSetOptionAsEsc(left: true)
    }

    @objc func metaFrustrationDetectorDidDetectFrustrationForRightOption() {
        maybeOfferToSetOptionAsEsc(left: false)
    }

    private func maybeOfferToSetOptionAsEsc(left: Bool) {
        guard let session else { return }
        if session.isDivorced {
            return
        }
        if iTermUserDefaults.userDefaults().bool(forKey: Self.neverPromptOptionKeyDefaultsKey) {
            return
        }
        guard let currentProfile = session.profile,
              let model = ProfileModel.sharedInstance(),
              let bookmarks = model.bookmarks() else {
            return
        }
        let profileCount = bookmarks.count
        let spec = PTYSessionMetaFrustrationPolicy.promptSpec(left: left, profileCount: profileCount)
        if iTermProfilePreferences.integer(forKey: spec.profileKey, inProfile: currentProfile) != iTermOptionKeyBehavior.OPT_NORMAL.rawValue {
            return
        }
        guard let guid = currentProfile[KEY_GUID] as? String,
              let profileToChange = model.bookmark(withGuid: guid) else {
            return
        }

        let profileKey = spec.profileKey
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: spec.title,
            style: .warning,
            withActions: spec.actions,
            completion: { selection in
                switch PTYSessionMetaFrustrationPolicy.action(forSelection: selection,
                                                            profileCount: profileCount) {
                case .dismiss:
                    return
                case .changeThisProfile:
                    iTermProfilePreferences.setInt(
                        Int32(iTermOptionKeyBehavior.OPT_ESC.rawValue),
                        forKey: profileKey,
                        inProfile: profileToChange,
                        model: model
                    )
                case .changeAllProfiles:
                    let allBookmarks = model.bookmarks() ?? []
                    for profile in allBookmarks {
                        iTermProfilePreferences.setInt(
                            Int32(iTermOptionKeyBehavior.OPT_ESC.rawValue),
                            forKey: profileKey,
                            inProfile: profile,
                            model: model
                        )
                    }
                case .stopAsking:
                    iTermUserDefaults.userDefaults().set(true, forKey: Self.neverPromptOptionKeyDefaultsKey)
                }
            }
        )
        session.queueAnnouncement(announcement, identifier: Self.metaFrustrationIdentifier)
    }

    // MARK: - ModernKeyMapperDelegate

    @objc(modernKeyMapperWillMapKey)
    func modernKeyMapperWillMapKey() -> ObjCModernKeyMapperConfiguration {
        guard let session else {
            return ObjCModernKeyMapperConfiguration(
                leftOptionKey: .OPT_NORMAL,
                rightOptionKey: .OPT_NORMAL,
                leftControlKey: .regular,
                rightControlKey: .regular,
                leftCommandKey: .regular,
                rightCommandKey: .regular,
                functionKey: .regular
            )
        }
        return ObjCModernKeyMapperConfiguration(
            leftOptionKey: session.optionKey,
            rightOptionKey: session.rightOptionKey,
            leftControlKey: session.leftControlKey,
            rightControlKey: session.rightControlKey,
            leftCommandKey: session.leftCommandKey,
            rightCommandKey: session.rightCommandKey,
            functionKey: session.functionKey
        )
    }

    @objc(modernKeyMapperDelegateStringEncoding)
    func modernKeyMapperDelegateStringEncoding() -> UInt {
        return session?.encoding ?? String.Encoding.utf8.rawValue
    }

    // MARK: - iTermStandardKeyMapperDelegate

    @objc(standardKeyMapperWillMapKey:)
    func standardKeyMapperWillMapKey(_ standardKeyMapper: iTermStandardKeyMapper) {
        guard let session, let output = session.screen.terminalOutput else { return }
        let configuration = iTermStandardKeyMapperConfiguration()
        configuration.outputFactory = output
        configuration.encoding = iTermProfilePreferences.unsignedInteger(
            forKey: KEY_CHARACTER_ENCODING,
            inProfile: session.profile ?? [:]
        )
        configuration.leftOptionKey = session.optionKey
        configuration.rightOptionKey = session.rightOptionKey
        configuration.screenlike = session.isTmuxClient
        standardKeyMapper.configuration = configuration
    }

    // MARK: - iTermTermkeyKeyMapperDelegate

    @objc(termkeyKeyMapperWillMapKey:)
    func termkeyKeyMapperWillMapKey(_ termkeyKeyMaper: iTermTermkeyKeyMapper) {
        guard let session, let output = session.screen.terminalOutput else { return }
        let configuration = iTermTermkeyKeyMapperConfiguration(
            encoding: iTermProfilePreferences.unsignedInteger(
                forKey: KEY_CHARACTER_ENCODING,
                inProfile: session.profile ?? [:]
            ),
            leftOptionKey: session.optionKey,
            rightOptionKey: session.rightOptionKey,
            applicationCursorMode: ObjCBool(output.cursorMode),
            applicationKeypadMode: ObjCBool(output.keypadMode)
        )
        termkeyKeyMaper.configuration = configuration
    }

    // MARK: - iTermModifyOtherKeysMapperDelegate

    @objc(modifiyOtherKeysDelegateEncoding:)
    func modifiyOtherKeysDelegateEncoding(_ sender: iTermModifyOtherKeysMapper) -> UInt {
        let encoding = session?.screen.terminalEncoding ?? String.Encoding.utf8.rawValue
        DLog("encoding=\(encoding)")
        return encoding
    }

    @objc(modifyOtherKeys:getOptionKeyBehaviorLeft:right:)
    func modifyOtherKeys(_ sender: iTermModifyOtherKeysMapper,
                         getOptionKeyBehaviorLeft left: UnsafeMutablePointer<iTermOptionKeyBehavior>,
                         right: UnsafeMutablePointer<iTermOptionKeyBehavior>) {
        guard let session else {
            left.pointee = .OPT_NORMAL
            right.pointee = .OPT_NORMAL
            return
        }
        left.pointee = session.optionKey
        right.pointee = session.rightOptionKey
        DLog("left=\(left.pointee.rawValue) right=\(right.pointee.rawValue)")
    }

    @objc(modifyOtherKeysOutputFactory:)
    func modifyOtherKeysOutputFactory(_ sender: iTermModifyOtherKeysMapper) -> VT100Output {
        it_assert(session?.screen.terminalOutput != nil, "terminalOutput required")
        return session!.screen.terminalOutput!
    }

    @objc(modifyOtherKeysTerminalIsScreenlike:)
    func modifyOtherKeysTerminalIsScreenlike(_ sender: iTermModifyOtherKeysMapper) -> Bool {
        let screenlike = session?.isTmuxClient ?? false
        DLog("screenlike=\(screenlike)")
        return screenlike
    }

    // MARK: - iTermShortcutNavigationModeHandlerDelegate

    private func shortcutCandidates(from shortcuts: [ContentNavigationShortcut]) -> [PTYSessionShortcutNavigationPolicy.ShortcutCandidate] {
        return shortcuts.map { shortcut in
            PTYSessionShortcutNavigationPolicy.ShortcutCandidate(
                keyEquivalent: shortcut.keyEquivalent,
                terminating: shortcut.view?.terminating ?? false
            )
        }
    }

    @objc(shortcutNavigationCharactersAreCommandPrefix:)
    func shortcutNavigationCharactersAreCommandPrefix(_ characters: String) -> Bool {
        guard let shortcuts = session?.textview?.contentNavigationShortcuts as? [ContentNavigationShortcut] else {
            return false
        }
        return PTYSessionShortcutNavigationPolicy.isCommandPrefix(
            characters,
            in: shortcutCandidates(from: shortcuts)
        )
    }

    @objc(shortcutNavigationDidSetPrefix:)
    func shortcutNavigationDidSetPrefix(_ prefix: String?) {
        guard let shortcuts = session?.textview?.contentNavigationShortcuts as? [ContentNavigationShortcut] else {
            return
        }
        for shortcut in shortcuts {
            shortcut.view?.highlight(prefix: prefix)
        }
    }

    @objc(shortcutNavigationActionForKeyEquivalent:)
    func shortcutNavigationAction(forKeyEquivalent characters: String) -> ((NSEvent) -> Void)? {
        guard let shortcuts = session?.textview?.contentNavigationShortcuts as? [ContentNavigationShortcut] else {
            return nil
        }
        guard let index = PTYSessionShortcutNavigationPolicy.matchingIndex(
            forKeyEquivalent: characters,
            in: shortcutCandidates(from: shortcuts)
        ) else {
            return nil
        }
        return shortcuts[index].action
    }

    @objc func shortcutNavigationDidComplete() {
        guard let session else { return }
        session.textview?.removeContentNavigationShortcutsAndSearchResults(session.modeHandler.clearSelectionsOnExit)
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.shortcutNavigationMode = false
        })
    }

    @objc func shortcutNavigationDidBegin() {
        session?.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.shortcutNavigationMode = true
        })
    }

    // MARK: - iTermCopyModeHandlerDelegate

    @objc(copyModeHandlerDidChangeEnabledState:)
    func copyModeHandlerDidChangeEnabledState(_ handler: iTermCopyModeHandler) {
        guard let session else { return }
        session.textview?.requestDelegateRedraw()
        let enabled = handler.enabled
        if enabled {
            if let responder = session.mainResponder {
                session.textview?.window?.makeFirstResponder(responder)
            }
        } else {
            if session.haveAutoComposer() {
                session.composerManager.makeDropDownComposerFirstResponder()
            }
            if session.textview?.selection.live == true {
                session.textview?.selection.endLive()
            }
            session.screen.mutateAsynchronously { _, mutableState, _ in
                mutableState.scheduleTokenExecution()
            }
        }
        session.composerManager.temporarilyHidden = enabled
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.copyMode = enabled
        })
    }

    @objc(copyModeHandlerCreateState:)
    func copyModeHandlerCreateState(_ handler: iTermCopyModeHandler) -> iTermCopyModeStateProtocol {
        let state = iTermCopyModeState()
        guard let session else {
            return state
        }
        state.coord = PTYSessionCopyModeInitialStatePolicy.initialCursorCoord(
            cursorX: session.screen.cursorX(),
            cursorY: session.screen.cursorY(),
            scrollbackLines: session.screen.numberOfScrollbackLines()
        )
        state.numberOfLines = session.screen.numberOfLines()
        state.textView = session.textview

        if let textview = session.textview,
           textview.selection.allSubSelections.count == 1,
           let sub = textview.selection.allSubSelections.first {
            VT100GridAbsCoordRangeTryMakeRelative(
                sub.absRange.coordRange,
                session.screen.totalScrollbackOverflow()
            ) { range in
                if let responder = session.mainResponder {
                    textview.window?.makeFirstResponder(responder)
                }
                state.selecting = true
                state.start = range.start
                state.coord = range.end
            }
        }
        session.textview?.scrollLineNumberRange(intoView: VT100GridRangeMake(state.coord.y, 1))
        return state
    }

    @objc(copyModeHandlerRedraw:)
    func copyModeHandlerRedraw(_ handler: iTermCopyModeHandler) {
        session?.textview?.requestDelegateRedraw()
    }

    @objc(copyModeHandlerShowFindPanel:)
    func copyModeHandlerShowFindPanel(_ handler: iTermCopyModeHandler) {
        session?.showFindPanel()
    }

    @objc(copyModeHandler:revealCurrentLineInState:)
    func copyModeHandler(_ handler: iTermCopyModeHandler,
                         revealCurrentLineInState state: iTermCopyModeStateProtocol) {
        guard let copyModeState = iTermCopyModeState.cast(from: state) else {
            return
        }
        session?.textview?.scrollLineNumberRange(intoView: VT100GridRangeMake(copyModeState.coord.y, 1))
    }

    @objc(copyModeHandlerCopySelection:)
    func copyModeHandlerCopySelection(_ handler: iTermCopyModeHandler) {
        session?.textview?.copySelectionAccordingToUserPreferences()
    }

    // MARK: - PasteboardReporterDelegate

    @objc func pasteboardReporter(_ sender: PasteboardReporter, reportPasteboard pasteboard: String) {
        guard let session,
              let output = session.screen.terminalOutput,
              let data = output.reportPasteboard(pasteboard, contents: NSString.fromPasteboard() ?? "") else {
            return
        }
        let route = PTYSessionPasteboardPolicy.route(
            isTmuxClient: session.isTmuxClient,
            tmuxShouldHandleOSC52Queries: session.tmuxController?.shouldHandleOSC52Queries ?? false
        )
        switch route {
        case .tmuxOSC52:
            DLog("Handling OSC 52 query")
            session.writeLatin1EncodedData(data, broadcastAllowed: false, reporting: true)
        case .directReport:
            DLog("Non-tmux")
            session.screenSendReport(data)
        case .ignore:
            DLog("Ignore")
            return
        }
        session.view?.showUnobtrusiveMessage("Clipboard contents reported", duration: 3)
    }

    @objc func pasteboardReporterRequestPermission(_ sender: PasteboardReporter,
                                                   completion: @escaping (Bool, Bool) -> Void) {
        guard let session else {
            completion(false, false)
            return
        }
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: "Share clipboard contents with app in terminal?",
            style: .warning,
            withActions: ["Just Once", "Always", "Never"],
            completion: { selection in
                let decision = PTYSessionPasteboardPolicy.permissionDecision(forSelection: selection)
                completion(decision.allowed, decision.permanently)
            }
        )
        session.queueAnnouncement(announcement, identifier: UUID().uuidString)
    }
}
