//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

@objc
class PTYSessionClipping: NSObject {
    @objc let type: String
    @objc let title: String
    @objc let detail: String

    @objc(initWithType:title:detail:)
    init(type: String, title: String, detail: String) {
        self.type = type
        self.title = title
        self.detail = detail
    }

    @objc var dictionaryValue: [String: String] {
        return ["type": type, "title": title, "detail": detail]
    }

    @objc(initWithDictionary:)
    convenience init?(dictionary: [String: String]) {
        guard let type = dictionary["type"],
              let title = dictionary["title"],
              let detail = dictionary["detail"] else {
            return nil
        }
        self.init(type: type, title: title, detail: detail)
    }
}
@objc
class PTYSessionSwiftState: NSObject {
    // The iTermWorkgroupInstance owns the peer port (held
    // strongly by it and by the workgroup controller's dict).
    weak var peerPort: PTYSessionPeerPort?

    // The controller's dict keeps the instance alive
    // for the workgroup's lifetime; sessions never outlive their
    // workgroup (the sessionWillTerminate observer tears the
    // workgroup down if any tracked session goes away).
    weak var workgroupInstance: iTermWorkgroupInstance?

    // Mode this session inherited from its workgroup config when it was
    // spawned. .regular for everything that didn't come from a workgroup
    // (or that came from a regular-mode workgroup config). .codeReview
    // gates the deferred prompt-overlay launch path.
    var workgroupSessionMode: iTermWorkgroupSessionMode = .regular

    // When true, this session's `endAction` always reports .default no
    // matter what the profile's "Close Sessions On End" (KEY_SESSION_END_ACTION)
    // is. Set on workgroup-spawned member sessions (peers, splits, tabs)
    // so a profile sync — which reconciles non-overridden keys back to
    // the shared profile — can't quietly flip a member to Close and make
    // it auto-close when its program exits (e.g. a Diff pane whose
    // difftool finishes), which would tear the whole workgroup down. The
    // leader/main session is deliberately not marked, so it still honors
    // its profile.
    var forceDefaultEndAction = false

    // For .codeReview sessions, the raw (unwrapped, swifty-templated)
    // command — e.g. "claude \(codeReviewPrompt)". Cached so any future
    // relaunch (toolbar reload, broken-pipe restart announcement) can
    // re-present the prompt overlay against the original template.
    var codeReviewRawCommand: String?

    // For .codeReview sessions, the prompt text the user last submitted
    // from the overlay (which may be a preset or a hand-edited value).
    // nil until the first submission. When the overlay is re-presented
    // (toolbar reload, broken-pipe restart) this is used as the default
    // instead of the store's last-selected preset, so the user's prior
    // edits are preserved across reloads.
    var codeReviewLastUsedPrompt: String?

    // For .diff sessions whose spawn was deferred (the workgroup's git
    // poller hadn't reported any pending change yet at spawn time), the
    // captured closure that fires the launch request. Cleared by
    // firePendingDiffLaunch after it runs so a subsequent poll doesn't
    // re-launch the same session.
    var pendingDiffLaunch: (() -> Void)?

    // For .codeReview sessions, whether the "auto-send clippings when idle"
    // toolbar toggle is on. When on, the workgroup peer port sends this
    // session's clippings to the workgroup's main session each time the
    // review session transitions from working to idle. Runtime-only and
    // defaults off: re-entering a workgroup starts with the toggle off.
    var autoSendClippingsWhenIdle = false

    // For the main (root) session, whether the "auto-request review when
    // idle" toolbar toggle is on. When on, the workgroup peer port asks
    // the sole code-review session to run a review each time the main
    // session transitions from working to idle. Runtime-only and defaults
    // off, same as autoSendClippingsWhenIdle.
    var autoRequestReviewWhenIdle = false

    var delegateObservers = [(PTYSessionDelegate) -> ()]()

    // Canonical storage for this session's clippings. Sessions in a peer group
    // all delegate through PTYSessionPeerPort to the leader session's storage,
    // so this is only the active backing store on the leader (or on a solo
    // session). Non-leader sessions keep this empty.
    var clippings = [PTYSessionClipping]()

    // Past snapshots produced by "archive clippings". Oldest first. Each entry
    // is the full clippings list at the moment the user (or claude-code)
    // pressed Archive. Combined with `clippings` they form a timeline whose
    // tail is the live list.
    var clippingsArchive = [[PTYSessionClipping]]()

    // Which entry in the [archive..., live] timeline the view is showing.
    // -1 means the live list (`clippings`); 0..<clippingsArchive.count means
    // that archive entry. Anything else is treated as live. Persisted to
    // arrangements so re-opening a window restores the view position.
    var clippingsViewIndex = -1

    // Whether the user wants the clippings panel shown. Defaults to false so
    // a fresh launch shows nothing; add_clipping flips it to true. Lives on
    // the leader (parallel to `clippings`) and is exposed via the peer port
    // so all peers share it.
    var clippingsVisibilityFlag = false

    // Holds the modal panel used by the "+" button so it isn't deallocated
    // before the sheet finishes.
    var activeAddClippingPanel: AddClippingPanel?

    // ID of the chat hosted in this session's right-gutter panel, or nil if
    // none. A session owns at most one inline chat at a time.
    var inlineChatID: String?

    // Whether the inline chat panel is currently shown. The panel only
    // contributes to the right-extra width budget when this is true and
    // inlineChatID is non-nil.
    var inlineChatVisibilityFlag = true
}

// MARK: - Annotations and Mark URLs
extension PTYSession {
    @objc func revealAnnotation(_ id: String) {
        screen.enumerateObservableMarks { type, line, obj in
            guard type == .annotation, let note = obj as? PTYAnnotationReading, note.uniqueID == id else {
                return
            }
            textview?.scrollLineNumberRange(
                intoView: VT100GridRangeMake(Int32(Int64(line) - screen.totalScrollbackOverflow()), 1))
            highlightMarkOrNote(obj)
        }
    }

    private func url(annotation: String) -> URL? {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "annotation"
        components.queryItems = [URLQueryItem(name: "ann", value: annotation),
                                 URLQueryItem(name: "s", value: guid)]
        return components.url
    }

    @objc(urlForPromptMark:)
    func promptMarkURL(mark: VT100ScreenMarkReading) -> URL {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "reveal-mark"
        var items = [URLQueryItem]()
        items.append(URLQueryItem(name: "s", value: guid))
        items.append(URLQueryItem(name: "m", value: mark.guid))
        components.queryItems = items
        return components.url!
    }

    private func url(_ selection: iTermSelection, in snapshot: TerminalContentSnapshot) -> URL? {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "/compound-location"
        var items = [URLQueryItem]()
        items.append(URLQueryItem(name: "session", value: guid))
        let overflow = screen.totalScrollbackOverflow()
        for sub in selection.allSubSelections {
            let coordRange = VT100GridCoordRangeFromAbsCoordRange(sub.absRange.coordRange, overflow)
            if coordRange.start.y < 0 {
                continue
            }
            guard let start = snapshot.lineBuffer.position(forCoordinate: coordRange.start,
                                                           width: screen.width(),
                                                           offset: 0) else {
                continue
            }
            guard let end = snapshot.lineBuffer.position(forCoordinate: coordRange.end,
                                                         width: screen.width(),
                                                         offset: 0) else {
                continue
            }
            let location = sub.absRange.columnWindow.location
            let length = sub.absRange.columnWindow.length
            let info = SubSelectionSerializationInfo(
                mode: sub.selectionMode.rawValue,
                start: start,
                end: end,
                windowedRange: location..<(location + length))
            items.append(URLQueryItem(name: "sub", value: info.queryValue))
        }
        components.queryItems = items
        return components.url
    }

    @objc(explainSelectionWithAI:truncated:snapshot:command:subjectMatter:title:error:)
    func explainWithAI(selection: iTermSelection,
                       truncated: Bool,
                       snapshot: TerminalContentSnapshot,
                       command: String?,
                       subjectMatter: String,
                       title: String) throws {
        _ = selection
        _ = truncated
        _ = snapshot
        _ = command
        _ = subjectMatter
        _ = title
        iTermWarning.show(withTitle: "Explain Output with AI is unavailable in the terminal-first fork.",
                          actions: ["OK"],
                          accessory: nil,
                          identifier: nil,
                          silenceable: .kiTermWarningTypePersistent,
                          heading: "Feature Unavailable",
                          window: self.genericView?.window)
    }
}

struct SubSelectionSerializationInfo {
    var mode: Int
    var start: LineBufferPosition
    var end: LineBufferPosition
    var windowedRange: Range<Int32>?

    // Format: "mode;startCompact;endCompact;range"
    // where range is "lower:upper" if non-nil, or "nil" otherwise.
    var queryValue: String {
        let rangeString = windowedRange.map { "\($0.lowerBound):\($0.upperBound)" } ?? "nil"
        return "\(mode);\(start.compactStringValue);\(end.compactStringValue);\(rangeString)"
    }

    static func from(queryValue: String) -> SubSelectionSerializationInfo? {
        let components = queryValue.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        precondition(components.count == 4, "Invalid queryValue format")

        guard let mode = Int(components[0]) else {
            RLog("Invalid mode in queryValue \(queryValue)")
            return nil
        }

        // Assumes LineBufferPosition can be re-created from its compact string.
        let start = LineBufferPosition.fromCompactStringValue(components[1])
        let end = LineBufferPosition.fromCompactStringValue(components[2])

        let windowedRange: Range<Int32>? = {
            if components[3] == "nil" { return nil }
            let parts = components[3].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            precondition(parts.count == 2, "Invalid range format")
            guard let lower = Int32(parts[0]), let upper = Int32(parts[1]) else {
                RLog("Invalid range bounds in queryValue \(queryValue)")
                return nil
            }
            return lower..<upper
        }()

        return SubSelectionSerializationInfo(mode: mode, start: start, end: end, windowedRange: windowedRange)
    }

    func absRange(_ screen: VT100Screen) -> VT100GridAbsWindowedRange? {
        let snapshot = screen.snapshotForcingPrimaryGrid(false)
        var ok = ObjCBool(false)
        let startCoord = snapshot.lineBuffer.coordinate(for: start,
                                                        width: screen.width(),
                                                        extendsRight: true,
                                                        ok: &ok)
        guard ok.boolValue else {
            return nil
        }
        let endCoord = snapshot.lineBuffer.coordinate(for: end,
                                                      width: screen.width(),
                                                      extendsRight: true,
                                                      ok: &ok)
        guard ok.boolValue else {
            return nil
        }
        let overflow = screen.totalScrollbackOverflow()
        let coordRange = VT100GridAbsCoordRange(start: VT100GridAbsCoordFromCoord(startCoord, overflow),
                                                end: VT100GridAbsCoordFromCoord(endCoord, overflow))
        return VT100GridAbsWindowedRange(coordRange: coordRange,
                                         columnWindow: VT100GridRange(location: windowedRange?.lowerBound ?? 0,
                                                                      length: Int32(windowedRange?.count ?? 0)))
    }
}

@objc
extension iTermSubSelection {
    @objc(initWithCompactString:screen:)
    convenience init?(compactString: String, screen: VT100Screen) {
        guard let info = SubSelectionSerializationInfo.from(queryValue: compactString) else {
            return nil
        }
        guard let absRange = info.absRange(screen) else {
            return nil
        }
        guard let mode = iTermSelectionMode(rawValue: info.mode) else {
            return nil
        }
        self.init(absRange: absRange,
                  mode: mode,
                  width: screen.width())
    }
}

extension PTYSession {
    // Returns an error if one occurs.
    @objc(performCopyModeCommands:)
    func performCopyModeCommands(_ commands: String) -> String? {
        let parser = VimKeyParser(commands)
        let events: [NSEvent]
        do {
            events = try parser.events()
        } catch {
            return error.localizedDescription
        }
        let wasInCopyMode = copyMode
        defer {
            copyMode = wasInCopyMode
        }
        copyMode = true
        for event in events {
            modeHandler.handle(event)
            if !copyMode {
                copyMode = true
            }
        }
        return nil
    }
}

@available(macOS 11.0, *)
extension PTYSession: PathCompletionHelperDelegate {
    @objc(showCompletionUIForPathMark:)
    func showCompletionUI(pathMark: PathMarkReading) -> PathCompletionHelper? {
        guard screen.isAtCommandPrompt else {
            return nil
        }
        let pathCompletionHelper = PathCompletionHelper(remoteHost: screen.lastRemoteHost(),
                                                        conductor: conductor,
                                                        pathMark: pathMark)
        pathCompletionHelper.delegate = self
        pathCompletionHelper.begin()
        return pathCompletionHelper
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              rangeForInterval interval: Interval) -> VT100GridCoordRange {
        return screen.coordRange(for: interval)
    }

    func pathCompletionHelperWidth(_ helper: PathCompletionHelper) -> Int32 {
        return screen.width()
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper,
                              screenRectForCoordRange coordRange: VT100GridCoordRange) -> NSRect {
        guard let textview else { return .zero }
        let startRect = textview.rect(for: coordRange.start)
        let endRect = textview.rect(for: coordRange.end)
        let textViewRect = startRect.union(endRect)
        let windowRect = textview.convert(textViewRect, to: nil)
        let screenRect = textview.window?.convertToScreen(windowRect) ?? .zero
        return screenRect
    }

    func pathCompletionHelperWindow(_ helper: PathCompletionHelper) -> NSWindow? {
        return textview?.window
    }

    func pathCompletionHelperFont(_ helper: PathCompletionHelper) -> NSFont {
        return textview?.fontTable.asciiFont.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    func pathCompletionHelper(_ helper: PathCompletionHelper, didSelect suggestion: String) {
        let escaped = (suggestion as NSString).withBackslashEscapedShellCharacters(includingNewlines: true)
        if screen.isAtCommandPrompt && (currentCommand ?? "").isEmpty {
            writeTask("cd \(escaped)\r")
        } else {
            setOrAppendComposerString((currentCommand ?? "") + escaped)
        }
        helper.invalidate()
        pathCompletionHelper = nil
    }
}

extension PTYSession {
    // NOTE: The channels branch of iTerm2-Shell-Integration has the `it2run` server process you need to test this.
    @objc(addChannelClient:command:)
    func add(channelClient: ChannelClient, command: String) {
        it_assert(!isTmuxClient)

        channelClients.add(channelClient)
        let session = newSession(forChannelID: channelClient.uid, command: command)!
        let iobuffer = IOBuffer(fileDescriptor: channelClient.fd,
                                operationQueue: FileDescriptorMonitor.queue) { [weak session] in
            // receive returns nil if only part of a segmented message is received.
            if var data = channelClient.mux.receive() {
                data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
                    session?.threadedReadTask(ptr.baseAddress!, length: Int32(ptr.count))
                }
            }
        } writeClosure: { data in
            channelClient.mux.send(message: data)
        }
        session.shell.ioBuffer = iobuffer
        session.channelParentGuid = guid
        // Should only be nil for tmux
        let restorableSession = self.restorableSession
        restorableSession.arrangement = [:]
        restorableSession.sessions = [session]
        restorableSession.group = .kiTermRestorableSessionGroupChannel
        iTermBuriedSessions.sharedInstance().add(restorableSession, for: session)
    }

    @objc(removeChannelClientWithID:)
    func removeChannelClient(id: String) {
        let indexes = channelClients.indexesOfObjects { obj, _, _ in
            (obj as! ChannelClient).uid == id
        }
        channelClients.removeObjects(at: indexes)
    }

    @objc(removeChannelClientsForConductor:)
    func removeChannelClients(for conductor: Conductor) {
        let indexes = channelClients.indexesOfObjects { obj, _, _ in
            (obj as! ChannelClient).conductor === conductor
        }
        channelClients.removeObjects(at: indexes)
    }

    @objc(swapWithChannelSessionWithUID:)
    func swapWithChannelSession(uid: String) {
        let session = iTermBuriedSessions.sharedInstance().buriedSessions().first { candidate in
            candidate.channelUID == uid
        }
        guard let session else {
            RLog("No buried session with channel uid \(uid)")
            return
        }
        delegate?.swapSession(self, withBuriedSession: session)
    }

}

@objc
extension PTYSession {
    func smartSelectAllVisible() {
        DLog("begin");
        guard let textview, let view else { return }
        textview.removeContentNavigationShortcutsAndSearchResults(false)
        let visibleLines = textview.rangeOfVisibleLines
        let overflow = screen.totalScrollbackOverflow()
        let y = VT100GridRangeNoninclusiveMaxLL(visibleLines) + overflow
        textview.findOnPageHelper.setStartPoint(VT100GridAbsCoordMake(0, y))
        let findDriver = view.findDriverCreatingIfNeeded

        let regex = regularExpressonForNonLowPrecisionSmartSelectionRulesCombined
        DLog("findDriver=\(findDriver.d) regex=\(regex)")
        var done = false
        let visibleAbsLines = NSMakeRange(Int(visibleLines.location) + Int(overflow),
                                          Int(visibleLines.length))
        var indexes = IndexSet(integersIn: Range(visibleAbsLines)!)
        findDriver?.closeViewAndDoTemporarySearch(for: regex,
                                                  mode: .caseSensitiveRegex,
                                                  extendResultsAcrossSoftBoundaries: false) { [weak self] linesSearched in
            guard let textview = self?.textview, !done else {
                return
            }
            indexes.remove(integersIn: Range(linesSearched)!)
            if indexes.isEmpty {
                textview.convertVisibleSearchResultsToContentNavigationShortcuts(with: .copy,
                                                                                 clearOnEnd: true)
                done = true
            }
        }
    }
}

extension PTYSession {
    @objc
    var minimalThemeTextColor: NSColor {
        if let color = textview?.colorForMargins {
            if color.isDark {
                return NSColor(displayP3Red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            } else {
                return NSColor(displayP3Red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
            }
        }
        return textview?.colorMap.color(forKey: kColorMapForeground) ?? NSColor.textColor
    }
}

@objc
extension PTYSession {
    var defaultAccountNameForPasswordManager: String? {
        return nil
    }
}

@objc
extension PTYSession {
    func willOpenEditSessionSettings() {
        if var triggerDicts = self.justProfile[KEY_TRIGGERS] as? [NSDictionary] {
            var haveStats = false
            screen.performBlock(joinedThreads: { _, state, _ in
                let stats = state.triggerStats()
                if stats.count == triggerDicts.count {
                    for i in 0..<stats.count {
                        if var dict = triggerDicts[i] as? [String: Any] {
                            haveStats = true
                            dict[kTriggerPerformanceKey] = stats[i].dictionaryValue
                            triggerDicts[i] = dict as NSDictionary
                        }
                    }
                }
            })
            if haveStats {
                setSessionSpecificProfileValues([KEY_TRIGGERS: triggerDicts])
            }
        }
    }
}

@objc
extension PTYSession {
    func saveArchive() {
        guard let destination = iTermProfilePreferences.string(forKey: KEY_ARCHIVEDIR, inProfile: justProfile) else {
            RLog("No archive dir in profile")
            return
        }
        let term = delegate?.realParentWindow() as? PseudoTerminal
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        let dateTime = formatter.string(from: now)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ",", with: "")
        let filename = "\(dateTime) - \(name).itermarchive"
        let url = URL(fileURLWithPath: destination).appendingPathComponent(filename)
        saveArchive(to: iTermSavePanelItem(filename: url.path, host: .localhost), term: term)
    }

    @objc(saveArchiveTo:term:)
    func saveArchive(to location: iTermSavePanelItem, term: PseudoTerminal?) {

        let arrangement: [AnyHashable: Any]?
        if let term {
            arrangement = term.arrangement(with: self)
        } else {
            arrangement = PseudoTerminal.arrangement(with: self)
        }
        guard let data = (arrangement as? NSDictionary)?.propertyListData() else {
            DLog("Invalid plist at \(((arrangement as? NSDictionary)?.it_invalidPathInPlist()).d)")
            return
        }
        if location.host.isLocalhost {
            // This has to be synchronous for saving archives on app quit.
            do {
                try data.write(to: URL(fileURLWithPath: location.filename))
                ArchivesMenuBuilder.shared?.didAdd(path: location.filename)
            } catch {
                RLog("Saving to \(location.description) failed: \(error)")
                iTermNotificationController.sharedInstance().notify(
                    "Archiving to \(location.displayName) failed: \(error.localizedDescription)")
            }
            return
        }
        Task { @MainActor in
            do {
                try await location.upload(data: data)
                if location.host.isLocalhost {
                    ArchivesMenuBuilder.shared?.didAdd(path: location.filename)
                }
            } catch {
                RLog("Saving to \(location.description) failed: \(error)")
                iTermNotificationController.sharedInstance().notify(
                    "Archiving to \(location.displayName) failed: \(error.localizedDescription)")
            }
        }
    }
}

extension PTYSession: AutomaticProfileSwitchingSessionDelegate {
    func automaticProfileSwitchingSessionExpressionNeedEvaluation(_ session: AutomaticProfileSwitchingSession) {
        if iTermProfilePreferences.bool(forKey: KEY_PREVENT_APS, inProfile: justProfile) {
            return
        }
        // apsContext is initialized in -setPreferencesFromAddressBookEntry:.
        // This delegate callback only fires after that runs, so this is
        // belt-and-suspenders.
        guard let apsContext else { return }
        automaticProfileSwitcher.markDirty()
        automaticProfileSwitcher.setHostname(genericScope.value(forVariableName: iTermVariableKeySessionHostname) as? String,
                                             username: genericScope.value(forVariableName: iTermVariableKeySessionUsername) as? String,
                                             path: genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String,
                                             job: genericScope.value(forVariableName: iTermVariableKeySessionJob) as? String,
                                             commandLine: genericScope.value(forVariableName: iTermVariableKeySessionCommandLine) as? String,
                                             expressionValueProvider: apsContext)
    }
}

// MARK: - Session Note

extension PTYSession {
    @objc func textViewEditSessionNote() {
        guard let view else { return }
        if view.isSessionNoteVisible {
            view.hideSessionNote()
        } else {
            if sessionNoteModel == nil {
                sessionNoteModel = SessionNoteModel()
            }
            view.showSessionNote(with: sessionNoteModel!)
        }
    }
}

extension PTYSession {
    var peerPort: PTYSessionPeerPort? {
        get {
            swiftState.peerPort
        }
        set {
            swiftState.peerPort = newValue
        }
    }

    // Read-only bridge for ObjC. We deliberately don't make the Swift
    // `peerPort` property `@objc` directly: doing so would also expose
    // the setter to ObjC, which lets callers bypass `set(peerPort:)`'s
    // "self.peerPort == nil" invariant. ObjC consumers that need to
    // *read* the peer port (e.g. the toolbelt's window-contains check)
    // go through this method.
    @objc(peerPort)
    func _objcPeerPort() -> PTYSessionPeerPort? {
        return peerPort
    }

    func set(peerPort: PTYSessionPeerPort) {
        it_assert(self.peerPort == nil)
        self.peerPort = peerPort
    }

    // Display label identifying this peer within its workgroup peer
    // group, or nil when the session isn't a member of a multi-peer
    // workgroup port. Used by the Session Status toolbelt tool to
    // disambiguate rows for sessions that share a tab/workgroup name.
    var peerDisplayLabel: String? {
        guard let port = peerPort as? iTermWorkgroupPeerPort,
              port.peerCount > 1,
              let id = port.identifier(for: self) else {
            return nil
        }
        return port.label(forPeerID: id)
    }

    // Workgroup runtime: when a workgroup is active on this session,
    // `workgroupInstance` points at the per-entry state owner.
    @objc var workgroupInstance: iTermWorkgroupInstance? {
        get { swiftState.workgroupInstance }
        set { swiftState.workgroupInstance = newValue }
    }

    // Workgroup-mode tag set by the spawn path. .codeReview triggers the
    // deferred-launch / prompt-overlay path; .regular runs the program
    // immediately as before.
    @objc var workgroupSessionMode: iTermWorkgroupSessionMode {
        get { swiftState.workgroupSessionMode }
        set { swiftState.workgroupSessionMode = newValue }
    }

    // See SwiftState.forceDefaultEndAction. Read by -[PTYSession endAction].
    @objc var forceDefaultEndAction: Bool {
        get { swiftState.forceDefaultEndAction }
        set { swiftState.forceDefaultEndAction = newValue }
    }

    // Raw (unwrapped, swifty-templated) command for .codeReview sessions.
    // Used by reload paths (toolbar reload, restart-after-exit) to
    // re-present the prompt overlay against the original template.
    @objc var codeReviewRawCommand: String? {
        get { swiftState.codeReviewRawCommand }
        set { swiftState.codeReviewRawCommand = newValue }
    }

    // Prompt text last submitted from the code-review overlay; used as the
    // default when re-presenting the overlay so prior (possibly hand-edited)
    // input is preserved across reloads. See PTYSession+CodeReviewPrompt.
    @objc var codeReviewLastUsedPrompt: String? {
        get { swiftState.codeReviewLastUsedPrompt }
        set { swiftState.codeReviewLastUsedPrompt = newValue }
    }

    // Closure that fires the deferred launch for a .diff-mode session
    // whose spawn was held back because the workgroup’s git poller had
    // not yet reported a pending change. iTermWorkgroupInstance calls
    // firePendingDiffLaunch from gitPollerDidUpdate once changes appear.
    var pendingDiffLaunch: (() -> Void)? {
        get { swiftState.pendingDiffLaunch }
        set { swiftState.pendingDiffLaunch = newValue }
    }

    @objc var hasPendingDiffLaunch: Bool {
        return swiftState.pendingDiffLaunch != nil
    }

    // Run the captured deferred-launch closure (if any) and clear it so
    // a later gitPollerDidUpdate doesn’t fire a second launch. Also
    // dismiss the waiting overlay (if presented); the actual launch
    // will paint terminal output onto a freshly-cleared session view.
    @objc
    func firePendingDiffLaunch() {
        let closure = swiftState.pendingDiffLaunch
        RLog("PTYSession[\(guid)]: firePendingDiffLaunch hasClosure=\(closure != nil)")
        swiftState.pendingDiffLaunch = nil
        // While the diff-waiting overlay is up, -mainResponder routes to
        // its Run Anyway button, so the peer swap that revealed this
        // session parked the window's first responder on that button.
        // Dismissing the overlay removes that button; without reassigning,
        // the window is left with a dead first responder and typing beeps
        // (the first-visit "command runs but the terminal isn't first
        // responder" bug). If the overlay owns focus right now, hand it
        // back to the terminal once the overlay is gone and the deferred
        // command has launched — mainResponder then resolves to the
        // freshly-running text view.
        let overlayOwnedFocus = diffWaitingOverlayOwnsFirstResponder
        view?.dismissDiffWaitingPromptOverlay()
        closure?()
        if overlayOwnedFocus {
            view?.window?.makeFirstResponder(mainResponder)
        }
    }

    // True when the diff-waiting overlay (or one of its subviews, e.g.
    // its Run Anyway button — see -mainResponder) currently holds the
    // window's first responder. firePendingDiffLaunch consults this
    // before tearing the overlay down so it only restores focus to the
    // terminal when the overlay actually owned it, and leaves first
    // responder alone when a poller-driven launch fires while the user's
    // focus is elsewhere.
    private var diffWaitingOverlayOwnsFirstResponder: Bool {
        guard let overlay = view?.diffWaitingPromptOverlay,
              let responder = overlay.window?.firstResponder as? NSView else {
            return false
        }
        return responder.isDescendant(of: overlay)
    }

    // Drop the initial-spawn waiting overlay onto the session view.
    // Called from the .diff spawn paths immediately after
    // pendingDiffLaunch is set, so the user sees an explanation rather
    // than a blank screen the moment they activate the buried peer
    // (or, for split/tab .diff sessions, the moment the spawn lands in
    // the window). The Run Anyway button routes back through
    // firePendingDiffLaunch so the manual override and the poller-
    // driven path go through the same dismiss + launch sequence.
    @objc
    func presentDiffWaitingPromptOverlay() {
        guard let sessionView: SessionView = view else {
            RLog("PTYSession[\(guid)]: presentDiffWaitingPromptOverlay aborted, session has no view")
            return
        }
        sessionView.presentDiffWaitingPromptOverlay { [weak self] in
            self?.firePendingDiffLaunch()
        }
    }

    // Drop the queued-reload waiting overlay onto the session view.
    // Distinct from the initial-spawn variant: the previous program
    // is still rendered on the terminal underneath, so the text says
    // "Reload queued" rather than "waiting to start" and there's a
    // Cancel button that clears pendingDiffLaunch without firing it
    // (otherwise an accidental Reload click on a clean tree would
    // queue a restart that the next poll tick fires, killing the
    // visible output).
    @objc
    func presentDiffWaitingPromptOverlayForQueuedReload() {
        guard let sessionView: SessionView = view else {
            RLog("PTYSession[\(guid)]: presentDiffWaitingPromptOverlayForQueuedReload aborted, session has no view")
            return
        }
        sessionView.presentDiffWaitingPromptOverlayForQueuedReload(
            onRunAnyway: { [weak self] in
                self?.firePendingDiffLaunch()
            },
            onCancel: { [weak self] in
                // Clear the closure without firing it: the user picked
                // Cancel because they don't want to restart after all.
                self?.pendingDiffLaunch = nil
            })
    }

    // Reload entry point for .diff-mode workgroup sessions. Handles
    // all three runtime states:
    //
    //   A) Initial spawn still waiting: pendingDiffLaunch is set, no
    //      program has run yet. If the poller now reports pending
    //      changes, fire the stashed closure (which is the original
    //      attachOrLaunch). Otherwise the overlay is already up; do
    //      nothing and let the next poll tick fire it.
    //
    //   B) Program is running or restartable: if there are pending
    //      changes, restart() immediately. Otherwise install a fresh
    //      restart() closure as pendingDiffLaunch and re-present the
    //      waiting overlay so a subsequent poll tick (or Run Anyway)
    //      re-runs the command. Re-checks isRestartable() inside the
    //      closure because the program may exit between the click and
    //      the fire, and -restart asserts isRestartable on entry.
    //
    //   C) Not restartable and no pending launch: nothing to do.
    //
    // Called from both the peer-port and instance-side reload
    // delegates so a reload button on either a peer or a non-peer
    // (split/tab) .diff session lands here. Both call sites bypass
    // the global isRestartable() guard for .diff because State A is a
    // legitimately reloadable state even though _program is nil.
    //
    // `resolveCommand` yields the login-shell-wrapped diff command
    // matching the file picker's selection AT THE MOMENT IT RUNS
    // (per-file when a file is picked, All Files otherwise). It is
    // evaluated as late as possible: immediately for the ready path,
    // or inside the deferred pendingDiffLaunch closure at fire time
    // (the next poll tick or Run Anyway), so a picker pick or gitBase
    // change between the reload click and the actual relaunch is
    // reflected. Reload must run this rather than the session's
    // last-launched _program, because the two can silently diverge:
    // when the file the popup was on stops being a diffable change, a
    // git poll resets the popup back to "All Files" in
    // CCDiffSelectorItem.set(fileStatuses:) without restarting the
    // session, leaving _program pointed at a now-clean per-file diff.
    // Replaying that _program runs `git difftool` on a file with no
    // changes, which prints nothing and exits 0, ending the session
    // instead of re-diffing. A nil resolver (or one that yields nil)
    // falls back to a plain restart() for callers (e.g. arrangement
    // restoration) that have no selector selection to resolve.
    func reloadDiffWithDeferralIfNeeded(resolveCommand: (() -> String?)? = nil) {
        let ready = workgroupInstance?.diffLaunchReady ?? false
        RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded ready=\(ready) hasPendingDiffLaunch=\(hasPendingDiffLaunch) restartable=\(isRestartable())")
        if hasPendingDiffLaunch {
            if ready {
                RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded firing pending diff launch (State A)")
                firePendingDiffLaunch()
            } else {
                RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded waiting, launch not ready (State A)")
            }
            return
        }
        guard isRestartable() else {
            RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded aborted, not restartable and no pending launch (State C)")
            return
        }
        // No inner isRestartable() re-check inside the closure: under
        // current invariants -isRestartable becomes true once _program
        // is assigned and never flips back (no code path clears
        // _program; browser-ness is fixed at session creation). The
        // outer guard is enough, so the closure only needs the weak
        // self check.
        let restartWithCurrentSelection: () -> Void = { [weak self] in
            if let command = resolveCommand?() {
                self?.restart(withCommand: command)
            } else {
                self?.restart()
            }
        }
        if ready {
            RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded restarting immediately (State B, ready)")
            restartWithCurrentSelection()
            return
        }
        RLog("PTYSession[\(guid)]: reloadDiffWithDeferralIfNeeded queuing restart and showing waiting overlay (State B, not ready)")
        pendingDiffLaunch = restartWithCurrentSelection
        // Queued-reload variant of the overlay: the previous diff
        // output is still on screen behind the panel. Cancel clears
        // pendingDiffLaunch without firing it, so an accidental
        // Reload click can be undone.
        presentDiffWaitingPromptOverlayForQueuedReload()
    }

    // Whether the user can currently see this session: it has a live
    // delegate (a buried peer has none) and its tab is the selected one.
    // Gates the deferred .diff launch so the diff runs against the tree
    // as it stands when the session is actually shown, not whenever the
    // poller first happened to see a change.
    var isVisibleForDeferredDiff: Bool {
        return delegate?.sessionBelongsToVisibleTab() ?? false
    }

    // Called when a .diff session may have become visible (a peer swapped
    // into its tab, or a tab selected). The initial diff launch is
    // deferred until the session is actually shown, so if it is now
    // visible and the poller already reports diffable changes, fire it
    // rather than making the user wait for the next poll tick. If there's
    // nothing diffable yet, the "waiting for changes" overlay stays up
    // and the next poll tick fires it (the session is visible now, so
    // fireDeferredDiffLaunches' gate passes).
    //
    // The isVisibleForDeferredDiff guard is load-bearing: a peer swap can
    // complete on a background tab (workgroup restoration across tabs, a
    // programmatic reveal), and firing there would run the diff against
    // the swap-in-time tree instead of what's on screen when the user
    // first sees it. A background swap is a no-op here; the tab-select
    // hook or the next poll tick picks the session up once it truly
    // reaches the foreground.
    //
    // This only ever fires the one deferred launch: firePendingDiffLaunch
    // clears the closure, so re-showing a diff that already ran does
    // nothing. Switching between peers never re-runs the diff.
    @objc
    func fireDeferredDiffLaunchIfVisibleNow() {
        guard workgroupSessionMode == .diff,
              hasPendingDiffLaunch,
              isVisibleForDeferredDiff,
              workgroupInstance?.diffLaunchReady == true else {
            return
        }
        firePendingDiffLaunch()
    }

    // Build a peer session for a workgroup's configured peer, driven
    // by an iTermWorkgroupSessionConfig config (profile override, command
    // override, buried until activated). `workgroupInstanceID` is
    // injected as ITERM_WORKGROUP_ID in the launch request so the
    // peer's shell sees the per-entry workgroup id.
    func makeWorkgroupPeer(config: iTermWorkgroupSessionConfig,
                           workgroupInstanceID: String) -> iTermPromise<PTYSession> {
        return iTermPromise<PTYSession> { seal in
            withDelegate { [weak self] delegate in
                guard let self else {
                    seal.reject(iTermError("Session terminated"))
                    return
                }
                asyncInitialDirectoryForNewSessionBased { [weak self] oldCWD in
                    guard let self else {
                        seal.reject(iTermError("Session terminated"))
                        return
                    }
                    let factory = iTermSessionFactory()
                    guard var profile = self.profile else {
                        seal.reject(iTermError("Session has no profile"))
                        return
                    }
                    guard let myView = self.view else {
                        seal.reject(iTermError("Session has no view"))
                        return
                    }
                    if let guid = config.profileGUID,
                       let override = ProfileModel.sharedInstance()?
                        .bookmark(withGuid: guid) {
                        profile = override
                    }
                    // Peer sessions live on the same screen as the
                    // main session and should never prompt on close —
                    // they're torn down when the workgroup exits.
                    profile[KEY_PROMPT_CLOSE] = PROMPT_ALWAYS
                    profile[KEY_SESSION_END_ACTION] =
                        iTermSessionEndAction.default.rawValue
                    // Browser profile + configured URL: seed
                    // KEY_INITIAL_URL so the browser session's
                    // deferred-URL load picks it up.
                    if !config.urlString.isEmpty,
                       let customCommand = profile[KEY_CUSTOM_COMMAND as String] as? String,
                       customCommand == kProfilePreferenceCommandTypeBrowserValue {
                        profile[KEY_INITIAL_URL as String] = config.urlString
                    }

                    let newSession = factory.newSession(withProfile: profile,
                                                        parent: self)
                    // Durably pin the default end action: the profile
                    // override above sets the initial value, but a later
                    // profile sync can revert a non-overridden key to the
                    // shared profile's Close. This flag can't be reverted,
                    // so the peer never auto-closes on program exit.
                    newSession.forceDefaultEndAction = true
                    newSession.setScreenSize(myView.bounds.size,
                                             parent: delegate.realParentWindow())
                    newSession.setSize(screen.size)
                    if let newSessionView = newSession.view {
                        newSessionView.scrollview.hasVerticalScroller = myView.scrollview.hasVerticalScroller
                        newSessionView.scrollview.lineScroll = myView.scrollview.lineScroll
                        newSessionView.scrollview.pageScroll = myView.scrollview.pageScroll
                    }
                    if let imagePath = backgroundImagePath {
                        newSession.backgroundImagePath = imagePath
                    }
                    newSession.setPreferencesFromAddressBookEntry(profile)
                    newSession.loadInitialColorTableAndResetCursorGuide()
                    newSession.screen.resetTimestamps()

                    if ProfileModel.sessionsInstance().bookmark(withGuid: (newSession.justProfile[KEY_GUID] as! String)) != nil && isDivorced {
                        newSession.inheritDivorce(
                            from: self,
                            decree: "Workgroup peer of session with guid \(d(profile[KEY_GUID]))")
                    }
                    // Workgroup commands run via /usr/bin/login +
                    // ShellLauncher so dotfiles are sourced and the
                    // user's interactive PATH/aliases are visible.
                    // KEY_RUN_COMMAND_IN_LOGIN_SHELL doesn't apply
                    // here — the launch request below feeds `command`
                    // into the launcher directly, bypassing the
                    // bookmarkCommandSwiftyString: wrapping path.
                    newSession.workgroupSessionMode = config.mode
                    let urlString = config.urlString.isEmpty ? nil : config.urlString

                    // .codeReview mode defers the entire spawn: bury and
                    // fulfill the promise immediately so the workgroup
                    // can activate this peer (showing its overlay), then
                    // present the prompt overlay in the session's view.
                    // The Start handler builds and fires the launch
                    // request when the user is ready.
                    //
                    // The bury() is peer-specific: peers live in the
                    // same tab as the leader and need to be in the
                    // buried-sessions registry so the workgroup's
                    // mode-switch path can swap them in via
                    // sessionActivateSession:amongPeers:moveToolbar:.
                    // The parallel deferred-launch path in
                    // DefaultWorkgroupSessionSpawner.launch (for
                    // .codeReview splits/tabs) does NOT bury — split
                    // and tab sessions are visible in the window the
                    // moment they're inserted, so there's nothing to
                    // unbury from later.
                    if config.mode == .codeReview {
                        newSession.bury()
                        newSession.presentCodeReviewPromptOverlay(
                            rawCommand: config.command,
                            urlString: urlString,
                            objectType: .paneObject,
                            factory: factory,
                            windowController: nil,
                            oldCWD: oldCWD,
                            workgroupInstanceID: workgroupInstanceID)
                        seal.fulfill(newSession)
                        return
                    }

                    if config.mode == .diff {
                        // Bury immediately and defer the actual launch
                        // until the workgroup’s git poller reports a
                        // pending change (see firePendingDiffLaunch).
                        // The seal is fulfilled now so the peer port
                        // wires up the session and the workgroup is
                        // not blocked waiting on this peer.
                        //
                        // `factory` is a local with no other strong
                        // reference once this closure unwinds, so it
                        // has to be captured strongly here. Otherwise
                        // it deallocs before the poller's first update
                        // and the deferred launch silently no-ops. The
                        // closure itself dies after firePendingDiffLaunch
                        // clears it, so there's no long-lived retain.
                        //
                        // The captured `oldCWD` is the leader's PWD at
                        // spawn time; the deferred launch uses it
                        // as-is rather than re-resolving when the
                        // closure fires. A workgroup peer is supposed
                        // to mirror the entry point, so if the leader
                        // cd's elsewhere later the diff peer keeps
                        // diffing the repo the workgroup was opened
                        // on.
                        //
                        // gitBase is intentionally re-resolved at fire
                        // time using the workgroup instance's current
                        // value. The caller (iTermWorkgroupInstance.enter
                        // and friends) hands us an unsubstituted config
                        // for .diff, so a gitBase change while the
                        // deferred launch is pending automatically
                        // propagates without the gitBase delegate path
                        // having to rebuild this closure.
                        newSession.bury()
                        newSession.presentDiffWaitingPromptOverlay()
                        let cfg = config
                        newSession.pendingDiffLaunch = { [weak newSession] in
                            guard let newSession else { return }
                            let base = newSession.workgroupInstance?.currentGitBase
                                ?? CCGitBaseSelectorItem.defaultBase
                            let resolved = cfg.resolvedCommand(gitBase: base)
                            let cmd = resolved.isEmpty
                                ? nil
                                : ITAddressBookMgr.commandByWrapping(inLoginShell: resolved)
                            let request = iTermSessionAttachOrLaunchRequest(
                                session: newSession,
                                canPrompt: false,
                                objectType: .paneObject,
                                hasServerConnection: false,
                                serverConnection: iTermGeneralServerConnection(),
                                urlString: urlString,
                                allowURLSubs: false,
                                environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                                customShell: nil,
                                oldCWD: oldCWD,
                                forceUseOldCWD: true,
                                command: cmd,
                                isUTF8: nil,
                                substitutions: nil,
                                windowController: nil,
                                ready: nil) { _, _ in }
                            factory.attachOrLaunch(with: request)
                        }
                        seal.fulfill(newSession)
                        return
                    }
                    let command = config.command.isEmpty
                        ? nil
                        : ITAddressBookMgr.commandByWrapping(inLoginShell: config.command)
                    let launchRequest = iTermSessionAttachOrLaunchRequest(
                        session: newSession,
                        canPrompt: false,
                        objectType: .paneObject,
                        hasServerConnection: false,
                        serverConnection: iTermGeneralServerConnection(),
                        urlString: urlString,
                        allowURLSubs: false,
                        environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                        customShell: nil,
                        oldCWD: oldCWD,
                        forceUseOldCWD: true,
                        command: command,
                        isUTF8: nil,
                        substitutions: nil,
                        windowController: nil,
                        ready: nil) { session, ok in
                            if ok, let session {
                                session.bury()
                                seal.fulfill(session)
                            } else {
                                seal.reject(iTermError("Failed to create session"))
                            }
                        }
                    factory.attachOrLaunch(with: launchRequest)
                }
            }
        }
    }
    
    @objc
    func didAssignDelegate() {
        let observers = swiftState.delegateObservers
        swiftState.delegateObservers = []
        for closure in observers {
            if let delegate {
                closure(delegate)
            } else {
                swiftState.delegateObservers.append(closure)
            }
        }
    }
    
    private func withDelegate(_ closure: @escaping (PTYSessionDelegate) -> ()) {
        if let delegate {
            closure(delegate)
            return
        }
        swiftState.delegateObservers.append(closure)
    }
    
    @objc(sessionBelongsToPeers:)
    func belongs(toPeers peers: PTYSessionPeerPort) -> Bool {
        return peers.contains(session: self)
    }

    // Public accessor — delegates to the peer-group's leader if this session
    // is in a peer group, otherwise reads/writes its own swiftState storage.
    @objc var clippings: [PTYSessionClipping] {
        get {
            if let peerPort {
                return peerPort.clippings
            }
            return swiftState.clippings
        }
        set {
            if let peerPort {
                peerPort.clippings = newValue
            } else {
                swiftState.clippings = newValue
            }
        }
    }

    // Runtime toggle backing the code-review "auto-send clippings when idle"
    // toolbar item. Stored directly on the session (not peer-delegated) since
    // it controls this one review session's behavior, not shared group state.
    @objc var autoSendClippingsWhenIdle: Bool {
        get { swiftState.autoSendClippingsWhenIdle }
        set { swiftState.autoSendClippingsWhenIdle = newValue }
    }

    // Runtime toggle backing the main session's "auto-request review when
    // idle" toolbar item. Stored on the main session; controls its own
    // idle-driven behavior, not shared group state.
    @objc var autoRequestReviewWhenIdle: Bool {
        get { swiftState.autoRequestReviewWhenIdle }
        set { swiftState.autoRequestReviewWhenIdle = newValue }
    }

    // Bypasses peer-port delegation. Used by PTYSessionPeerPort to talk to its
    // leader's storage without recursing, and by save/restore so the leader's
    // data is persisted at the session level.
    @objc var localClippings: [PTYSessionClipping] {
        get { swiftState.clippings }
        set { swiftState.clippings = newValue }
    }

    @objc var localClippingsAsDictionaries: [[String: String]] {
        return swiftState.clippings.map { $0.dictionaryValue }
    }

    @objc(setLocalClippingsFromDictionaries:)
    func setLocalClippingsFromDictionaries(_ dictionaries: [[String: String]]) {
        swiftState.clippings = dictionaries.compactMap {
            PTYSessionClipping(dictionary: $0)
        }
    }

    // Public accessor for the archive — delegates to the peer-group leader
    // when in a peer group so all peers see the same history.
    @objc var clippingsArchive: [[PTYSessionClipping]] {
        get {
            if let peerPort {
                return peerPort.clippingsArchive
            }
            return swiftState.clippingsArchive
        }
        set {
            if let peerPort {
                peerPort.clippingsArchive = newValue
            } else {
                swiftState.clippingsArchive = newValue
            }
        }
    }

    // Bypasses peer-port delegation for save/restore and PTYSessionPeerPort.
    @objc var localClippingsArchive: [[PTYSessionClipping]] {
        get { swiftState.clippingsArchive }
        set { swiftState.clippingsArchive = newValue }
    }

    @objc var localClippingsArchiveAsDictionaries: [[[String: String]]] {
        return swiftState.clippingsArchive.map { snapshot in
            snapshot.map { $0.dictionaryValue }
        }
    }

    @objc(setLocalClippingsArchiveFromDictionaries:)
    func setLocalClippingsArchiveFromDictionaries(_ dictionaries: [[[String: String]]]) {
        swiftState.clippingsArchive = dictionaries.map { snapshot in
            snapshot.compactMap { PTYSessionClipping(dictionary: $0) }
        }
    }

    // Currently displayed entry in the timeline. -1 = live; 0..<archive.count
    // = that archive snapshot.
    @objc var clippingsViewIndex: Int {
        get {
            if let peerPort {
                return peerPort.clippingsViewIndex
            }
            return swiftState.clippingsViewIndex
        }
        set {
            let clamped = Self.clampClippingsViewIndex(newValue, archiveCount: clippingsArchive.count)
            if let peerPort {
                peerPort.clippingsViewIndex = clamped
            } else {
                swiftState.clippingsViewIndex = clamped
            }
            clippingsDidChange()
        }
    }

    @objc var localClippingsViewIndex: Int {
        get { swiftState.clippingsViewIndex }
        set { swiftState.clippingsViewIndex = newValue }
    }

    private static func clampClippingsViewIndex(_ index: Int, archiveCount: Int) -> Int {
        if index < 0 || index >= archiveCount {
            return -1
        }
        return index
    }

    // The list shown in the panel: live or one of the archive entries.
    @objc var viewedClippings: [PTYSessionClipping] {
        let index = clippingsViewIndex
        let archive = clippingsArchive
        if index >= 0 && index < archive.count {
            return archive[index]
        }
        return clippings
    }

    // True when the view is on the live list (index -1). Mutating actions in
    // the panel (add/delete/reorder/drop) are gated by this.
    @objc var clippingsViewIsLive: Bool {
        let index = clippingsViewIndex
        return index < 0 || index >= clippingsArchive.count
    }

    @objc(addClippingWithType:title:detail:)
    func addClipping(type: String, title: String, detail: String) {
        var current = clippings
        current.append(PTYSessionClipping(type: type, title: title, detail: detail))
        clippings = current
        // Adding a clipping is always an action against the live list, so
        // hop the view back to live so the new item is visible. The
        // clippingsViewIndex setter posts the change notification, so the
        // already-visible branch needs no further work; the auto-show branch
        // re-posts once via the visibility setter, which is fine.
        clippingsViewIndex = -1
        if !clippingsVisible {
            clippingsVisible = true
        }
    }

    // Hard cap on archived snapshots to keep the arrangement size bounded.
    // The auto-archive integration (one snapshot per Claude Code review pass)
    // is the primary driver: a long-lived session that runs dozens of passes
    // would otherwise grow the arrangement unbounded.
    private static let maxClippingsArchiveEntries = 50

    // Snapshot the live list into the archive (if it's non-empty) and clear
    // the live list. Leaves the view on "live" so the user immediately sees
    // a fresh, empty list. Routing for code-review workgroup peers is handled
    // by callers (the built-in function and toolbar action) so this method
    // can run unconditionally on the resolved target session.
    @objc(archiveClippings)
    @discardableResult
    func archiveClippings() -> Bool {
        let live = clippings
        guard !live.isEmpty else {
            return false
        }
        var archive = clippingsArchive
        archive.append(live)
        if archive.count > Self.maxClippingsArchiveEntries {
            archive.removeFirst(archive.count - Self.maxClippingsArchiveEntries)
        }
        clippingsArchive = archive
        clippings = []
        // clippingsViewIndex setter broadcasts; no explicit follow-up needed.
        clippingsViewIndex = -1
        return true
    }

    // Public accessor — delegates to the peer-group's leader, or own storage if solo.
    @objc var clippingsVisible: Bool {
        get {
            if let peerPort {
                return peerPort.clippingsVisibilityFlag
            }
            return swiftState.clippingsVisibilityFlag
        }
        set {
            if let peerPort {
                peerPort.clippingsVisibilityFlag = newValue
            } else {
                swiftState.clippingsVisibilityFlag = newValue
            }
            clippingsDidChange()
        }
    }

    // Bypasses peer-port delegation — used by PTYSessionPeerPort to talk to
    // the leader's storage without recursing.
    @objc var localClippingsVisibilityFlag: Bool {
        get { swiftState.clippingsVisibilityFlag }
        set { swiftState.clippingsVisibilityFlag = newValue }
    }

    // Effective visibility is just the user-controlled flag — no auto-hide
    // when the list is empty.
    @objc var clippingsPanelEffectivelyVisible: Bool {
        return clippingsVisible
    }

    // Call after any mutation to the clippings list — broadcasts to gutter
    // panels so they reload and re-evaluate their visibility.
    @objc func clippingsDidChange() {
        NotificationCenter.default.post(name: PTYSession.clippingsDidChangeNotification,
                                        object: nil)
        // The gutter controller only instantiates the clippings panel when the
        // registry's width is > 0. On the 0→1 transition (e.g., first clipping
        // added via the Python API) no panel exists yet to consume the
        // notification above, so kick the parent window's layout cascade —
        // which ends up calling iTermRightGutterController.layoutPanels and
        // creates the panel. Same goes for the 1→0 transition tearing it down
        // when no panel is around to detect its own visibility flip.
        if view?.actualRightExtra != desiredRightExtra() {
            delegate?.realParentWindow()?.rightExtraDidChange()
        }
    }

    @objc static let clippingsDidChangeNotification =
        Notification.Name("iTermClippingsDidChange")

    // The chat ID currently bound to this session's inline-chat right-gutter
    // panel, or nil if none. Setting this value re-runs the layout cascade
    // because the right-extra budget depends on whether an inline chat is
    // installed.
    @objc var inlineChatID: String? {
        get { swiftState.inlineChatID }
        set {
            swiftState.inlineChatID = newValue
            inlineChatDidChange()
        }
    }

    // Whether the inline chat panel should be shown. Honored only when an
    // inlineChatID is set; with no chat to show, visibility has no effect.
    @objc var inlineChatVisible: Bool {
        get { swiftState.inlineChatVisibilityFlag }
        set {
            swiftState.inlineChatVisibilityFlag = newValue
            inlineChatDidChange()
        }
    }

    @objc func inlineChatDidChange() {
        NotificationCenter.default.post(name: PTYSession.inlineChatDidChangeNotification,
                                        object: self)
        if view?.actualRightExtra != desiredRightExtra() {
            delegate?.realParentWindow()?.rightExtraDidChange()
        }
    }

    @objc static let inlineChatDidChangeNotification =
        Notification.Name("iTermInlineChatDidChange")

    // Inline chat is unavailable in the terminal-first fork. Keep the
    // selector as a compatibility no-op while menu and responder cleanup
    // continues.
    @objc(toggleInlineChat)
    func toggleInlineChat() {
        inlineChatID = nil
        inlineChatVisible = false
    }
}
