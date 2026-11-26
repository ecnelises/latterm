//
//  PTYSessionProfileAndLoggingCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 3) to isolate automatic profile switching,
//  session name controller, directory tracker, logging helper, coprocess error
//  handling, bound variable synchronization, and tab status updates.
//

import Cocoa

enum PTYSessionAutomaticProfileSwitchPolicy {
    static func fontZoomDelta(preserveFontSize: Bool,
                              currentPointSize: CGFloat,
                              originalPointSize: CGFloat) -> CGFloat {
        guard preserveFontSize else {
            return 0
        }
        return currentPointSize - originalPointSize
    }

    static func filteredDivorcedOverrides(overriddenFields: Set<String>,
                                          savedProfileValues: [AnyHashable: Any],
                                          fontZoomDelta: CGFloat) -> [AnyHashable: Any] {
        let fontKeys: Set<String> = fontZoomDelta != 0
            ? [KEY_NORMAL_FONT, KEY_NON_ASCII_FONT, KEY_FONT_CONFIG]
            : []
        var overrides = [AnyHashable: Any]()
        for key in overriddenFields {
            if key == KEY_GUID || key == KEY_ORIGINAL_GUID {
                continue
            }
            if fontKeys.contains(key) {
                continue
            }
            if let value = savedProfileValues[key] {
                overrides[key] = value
            }
        }
        return overrides
    }
}

enum PTYSessionTitleIdentifierPolicy {
    static func uniqueIdentifier(components: iTermTitleComponents,
                                 titleFuncPlist: Any?) -> String? {
        if components != .custom {
            return iTermSessionNameControllerSystemTitleUniqueIdentifier
        }
        guard let titleFuncPlist else {
            return nil
        }
        let tuple = iTermTuple<NSString, NSString>.fromPlistValue(titleFuncPlist)
        guard tuple.firstObject != nil,
              let second = tuple.secondObject else {
            return nil
        }
        return second as String
    }
}

enum PTYSessionLoggingTimestampPolicy {
    static func shouldIncludePlainTextTimestamp(enabled: Bool,
                                                style: iTermLoggingStyle) -> Bool {
        return enabled && style == .plainText
    }
}

enum PTYSessionTabStatusNotificationPolicy {
    static func shouldPostNotification(previousStatusText: String?,
                                       newStatusText: String?,
                                       priorityAllowsNotification: Bool) -> Bool {
        guard let newStatusText else {
            return false
        }
        if newStatusText == (previousStatusText ?? "") {
            return false
        }
        return priorityAllowsNotification
    }
}

@objc final class PTYSessionProfileAndLoggingCoordinator: NSObject,
    iTermAutomaticProfileSwitcherDelegate,
    iTermSessionNameControllerDelegate,
    iTermSessionDirectoryTrackerDelegate,
    iTermLogging,
    iTermCoprocessDelegate,
    iTermWeaklyReferenceable {

    private weak var session: PTYSession?

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    @objc func weakSelf() -> Any {
        return iTermWeakReference<AnyObject>(object: self)!
    }

    // MARK: - iTermAutomaticProfileSwitcherDelegate

    @objc func automaticProfileSwitcherSessionName() -> String {
        guard let session else { return "" }
        let title = session.nameController.presentationSessionTitle ?? ""
        let tty = session.tty ?? ""
        return "\(title) — \(tty)"
    }

    @objc func automaticProfileSwitcherCurrentSavedProfile() -> iTermSavedProfile {
        let savedProfile = iTermSavedProfile()
        guard let session else {
            return savedProfile
        }
        savedProfile.profile = session.profile
        savedProfile.originalProfile = session.originalProfile
        savedProfile.isDivorced = session.isDivorced
        savedProfile.overriddenFields = NSMutableSet(set: session.overriddenProfileFields)
        return savedProfile
    }

    @objc func automaticProfileSwitcherCurrentProfile() -> [AnyHashable: Any] {
        return session?.originalProfile ?? [:]
    }

    @objc(automaticProfileSwitcherLoadProfile:)
    func automaticProfileSwitcherLoadProfile(_ savedProfile: iTermSavedProfile) {
        guard let session else { return }
        let original = savedProfile.originalProfile ?? [:]
        let guid = original[KEY_GUID] as? String
        let underlyingProfile = guid.flatMap { ProfileModel.sharedInstance()?.bookmark(withGuid: $0) }
        let replacementProfile = underlyingProfile ?? original
        let originalProfile = session.originalProfile ?? [:]
        let currentFont = session.textview?.fontTable.asciiFont.font
        DLog("APS load profile: target=\(String(describing: underlyingProfile?[KEY_NAME])) isDivorced=\(savedProfile.isDivorced) currentFont=\(String(describing: currentFont)) originalProfileGuid=\(String(describing: originalProfile[KEY_GUID]))")

        let currentPointSize = currentFont?.pointSize ?? 0
        let originalFontTable = FontTable.fontTable(forProfile: originalProfile)
        let originalPointSize = originalFontTable.asciiFont.font.pointSize
        let fontZoomDelta = PTYSessionAutomaticProfileSwitchPolicy.fontZoomDelta(
            preserveFontSize: iTermAdvancedSettingsModel.preserveFontSizeOnAutomaticProfileSwitch(),
            currentPointSize: currentPointSize,
            originalPointSize: originalPointSize
        )
        if iTermAdvancedSettingsModel.preserveFontSizeOnAutomaticProfileSwitch() {
            DLog("APS zoom: currentPointSize=\(currentPointSize) originalPointSize=\(originalPointSize) fontZoomDelta=\(fontZoomDelta)")
        }

        session.setProfile(replacementProfile, preservingName: false, adjustWindow: false)
        if savedProfile.isDivorced {
            if fontZoomDelta != 0 {
                DLog("APS excluding font keys from divorced overrides because fontZoomDelta=\(fontZoomDelta)")
            }
            let overridden = (savedProfile.overriddenFields?.allObjects as? [String]) ?? []
            DLog("APS restoring divorced overrides: \(overridden)")
            let overrides = PTYSessionAutomaticProfileSwitchPolicy.filteredDivorcedOverrides(
                overriddenFields: Set(overridden),
                savedProfileValues: savedProfile.profile ?? [:],
                fontZoomDelta: fontZoomDelta
            )
            session.withWindowAdjustmentDisabled {
                session.setSessionSpecificProfileValues(overrides)
            }
        }

        if fontZoomDelta != 0, let fontTable = session.textview?.fontTable, let textview = session.textview {
            DLog("APS applying zoom delta \(fontZoomDelta) to font \(fontTable.asciiFont.font)")
            session.withWindowAdjustmentDisabled {
                let zoomedTable = fontTable.fontTable(grownBy: fontZoomDelta)
                session.setFontTable(zoomedTable,
                                     horizontalSpacing: textview.horizontalSpacing,
                                     verticalSpacing: textview.verticalSpacing)
            }
            DLog("APS after zoom: font=\(String(describing: session.textview?.fontTable.asciiFont.font))")
        } else {
            DLog("APS skipping zoom: delta=0")
        }

        if iTermAdvancedSettingsModel.showAutomaticProfileSwitchingBanner() {
            let name = (underlyingProfile?[KEY_NAME] as? String) ?? ""
            session.view?.showUnobtrusiveMessage("Switched to profile “\(name)”.")
        }
    }

    @objc func automaticProfileSwitcherAllProfiles() -> [[AnyHashable: Any]] {
        return ProfileModel.sharedInstance()?.bookmarks() ?? []
    }

    // MARK: - iTermSessionNameControllerDelegate

    @objc func sessionNameControllerUniqueIdentifier() -> String? {
        guard let session else {
            return iTermSessionNameControllerSystemTitleUniqueIdentifier
        }
        let profile = session.profile ?? [:]
        let rawComponents = iTermProfilePreferences.unsignedInteger(forKey: KEY_TITLE_COMPONENTS, inProfile: profile)
        let components = iTermTitleComponents(rawValue: rawComponents)
        let titleFuncPlist = iTermProfilePreferences.string(forKey: KEY_TITLE_FUNC, inProfile: profile)
        return PTYSessionTitleIdentifierPolicy.uniqueIdentifier(
            components: components,
            titleFuncPlist: titleFuncPlist
        )
    }

    @objc(sessionNameControllerNameWillChangeTo:)
    func sessionNameControllerNameWillChange(to newName: String) {
        session?.genericScope.setValue(newName, forVariableNamed: iTermVariableKeySessionName)
    }

    @objc(sessionNameControllerPresentationNameDidChangeTo:)
    func sessionNameControllerPresentationNameDidChange(to presentationName: String) {
        guard let session else { return }
        session.delegate?.name(of: session, didChangeTo: presentationName)
        session.view?.setTitle(presentationName)

        let parentWindow = session.delegate?.parentWindow()
        if let currentTerminal = iTermController.sharedInstance().currentTerminal,
           (currentTerminal as AnyObject) === (parentWindow as AnyObject?) {
            NotificationCenter.default.post(name: NSNotification.Name("iTermNameOfSessionDidChange"),
                                            object: parentWindow,
                                            userInfo: nil)
        }
        NotificationCenter.default.post(name: .PTYSessionPresentationNameDidChange,
                                        object: session)
        session.genericScope.setValue(presentationName,
                                       forVariableNamed: iTermVariableKeySessionPresentationName)
        session.textview?.setBadgeLabel(session.badgeLabel ?? "")
    }

    @objc func sessionNameControllerDidChangeWindowTitle() {
        guard let session else { return }
        if session.delegate?.sessionBelongsToVisibleTab() == true {
            session.delegate?.parentWindow()?.setWindowTitle()
        }
    }

    @objc func sessionNameControllerFormattingDescriptor() -> iTermSessionFormattingDescriptor {
        let descriptor = iTermSessionFormattingDescriptor()
        guard let session else {
            return descriptor
        }
        descriptor.isTmuxGateway = session.isTmuxGateway
        descriptor.tmuxClientName = session.tmuxController?.clientName
        descriptor.haveTmuxController = (session.tmuxController != nil)
        descriptor.tmuxWindowName = session.delegate?.tmuxWindowName()
        return descriptor
    }

    @objc func sessionNameControllerScope() -> iTermVariableScope {
        it_assert(session?.genericScope != nil, "genericScope required for name controller")
        return session!.genericScope
    }

    // MARK: - Variable & Tab Status Bridges

    @objc(boundVariableDidChange:value:)
    func boundVariableDidChange(_ key: String, value: Any?) {
        guard let session else { return }
        DLog("key=\(key) value=\(String(describing: value))")
        if let value {
            if let plistValue = iTermProfilePreferences.plistValue(fromBoundVariableValue: value, forKey: key) {
                DLog("plistValue=\(plistValue)")
                session.setSessionSpecificProfileValues([key: plistValue])
            }
            return
        }
        if let profile = session.profile,
           let unboundValue = iTermProfilePreferences.object(forKey: key, inProfile: profile) {
            DLog("unboundValue=\(unboundValue)")
            session.setSessionSpecificProfileValues([key: unboundValue])
        }
    }

    @objc(screenSetTabStatus:)
    func screenSetTabStatus(_ status: VT100TabStatusUpdate) {
        guard let session else { return }
        DLog("\(session) screenSetTabStatus: \(status.description)")
        guard let tabStatus = session.tabStatus else {
            return
        }
        let previousStatusText = tabStatus.statusText
        guard tabStatus.apply(status) else {
            DLog("No change")
            return
        }
        maybePostTabStatusNotification(previousStatusText: previousStatusText, tabStatus: tabStatus)
        session.delegate?.sessionTabStatusDidChange(session)
    }

    private func maybePostTabStatusNotification(previousStatusText: String?,
                                                tabStatus: iTermSessionTabStatus) {
        guard let session else { return }
        let newStatusText = tabStatus.statusText
        guard PTYSessionTabStatusNotificationPolicy.shouldPostNotification(
            previousStatusText: previousStatusText,
            newStatusText: newStatusText,
            priorityAllowsNotification: newStatusText.map { StatusPrioritySettings.shared.shouldNotify(for: $0) } ?? false
        ), let newStatusText else {
            return
        }
        let sessionName = session.name.removingHTMLFromTabTitleIfNeeded()
        iTermNotificationController.sharedInstance().notify(
            String(format: NSLocalizedString("Session “%@”", comment: "User notification"), sessionName),
            withDescription: String(format: NSLocalizedString("Status changed to “%@”", comment: "User notification"), newStatusText),
            windowIndex: session.screenWindowIndex(),
            tabIndex: session.screenTabIndex(),
            viewIndex: session.screenViewIndex()
        )
    }

    @objc func clearTabStatus() {
        guard let session,
              let tabStatus = session.existingTabStatus,
              tabStatus.hasActiveStatus else {
            return
        }
        tabStatus.clear()
        iTermDockBadgeController.sharedInstance.sessionDidLeaveWaiting(session.guid)
        session.delegate?.sessionTabStatusDidChange(session)
    }

    // MARK: - iTermSessionDirectoryTrackerDelegate

    @objc(directoryTrackerDidChangeDirectory:)
    func directoryTrackerDidChangeDirectory(_ tracker: iTermSessionDirectoryTracker) {
        guard let session else { return }
        session.delegate?.sessionCurrentDirectoryDidChange(session)
    }

    @objc(directoryTrackerDidUpdateCurrentDirectory:path:)
    func directoryTrackerDidUpdateCurrentDirectory(_ tracker: iTermSessionDirectoryTracker, path: String?) {
        guard let conductor = session?.conductor else { return }
        MainActor.assumeIsolated {
            conductor.currentDirectory = path
        }
    }

    @objc(directoryTracker:createMarkForPolledDirectory:)
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          createMarkForPolledDirectory directory: String) {
        guard let session else { return }
        let absLine = Int64(session.screen.lineNumberOfCursor) + session.screen.totalScrollbackOverflow()
        session.screen.mutateAsynchronously { _, mutableState, _ in
            mutableState.setWorkingDirectory(
                directory,
                onAbsLine: absLine,
                pushed: false,
                token: mutableState.setWorkingDirectoryOrderEnforcer.newToken()
            )
        }
    }

    @objc(directoryTrackerProcessID:)
    func directoryTrackerProcessID(_ tracker: iTermSessionDirectoryTracker) -> pid_t {
        return session?.shell.pid ?? -1
    }

    @objc(directoryTrackerEnvironmentPWD:)
    func directoryTrackerEnvironmentPWD(_ tracker: iTermSessionDirectoryTracker) -> String? {
        return session?.sessionEnvironment?["PWD"] as? String
    }

    @objc(directoryTrackerIsInSoftAlternateScreenMode:)
    func directoryTrackerIsInSoftAlternateScreenMode(_ tracker: iTermSessionDirectoryTracker) -> Bool {
        return session?.screen.terminalSoftAlternateScreenMode ?? false
    }

    @objc(directoryTrackerEscapeSequencesDisabled:)
    func directoryTrackerEscapeSequencesDisabled(_ tracker: iTermSessionDirectoryTracker) -> Bool {
        return iTermAdvancedSettingsModel.disablePotentiallyInsecureEscapeSequences()
    }

    @objc(directoryTrackerWorkingDirectoryProvider:)
    func directoryTrackerWorkingDirectoryProvider(_ tracker: iTermSessionDirectoryTracker) -> (any iTermWorkingDirectoryProvider)? {
        return session?.shell
    }

    @objc(directoryTrackerSSHIdentityProvider:)
    func directoryTrackerSSHIdentityProvider(_ tracker: iTermSessionDirectoryTracker) -> (any SSHIdentityProvider)? {
        guard let conductor = session?.conductor else {
            return nil
        }
        return MainActor.assumeIsolated {
            conductor
        }
    }

    @objc(directoryTracker:didChangeLocalDirectory:)
    func directoryTracker(_ tracker: iTermSessionDirectoryTracker,
                          didChangeLocalDirectory directory: String?) {
        if let directory {
            session?.swiftState.composerCoordinator.updateLocalFileCheckerWorkingDirectory(directory)
        }
    }

    // MARK: - iTermLogging

    @objc(loggingHelperStart:)
    func loggingHelperStart(_ loggingHelper: iTermLoggingHelper) {
        guard let session,
              loggingHelper.style == .HTML,
              let font = session.textview?.fontTable.asciiFont.font,
              let familyName = font.familyName,
              let bgColor = session.screen.colorMap.color(forKey: kColorMapBackground),
              let fgColor = session.screen.colorMap.color(forKey: kColorMapForeground) else {
            return
        }
        let css = NSData.styleSheet(fontFamily: familyName,
                                    fontSize: font.pointSize,
                                    backgroundColor: bgColor,
                                    textColor: fgColor)
        loggingHelper.logWithoutTimestamp(css)
    }

    @objc(loggingHelperStop:)
    func loggingHelperStop(_ loggingHelper: iTermLoggingHelper) {
    }

    @objc(loggingHelperTimestamp:)
    func loggingHelperTimestamp(_ loggingHelper: iTermLoggingHelper) -> String? {
        let enabled = iTermAdvancedSettingsModel.logTimestampsWithPlainText()
        guard PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(
            enabled: enabled,
            style: loggingHelper.style
        ) else {
            return nil
        }
        let formatter = DateFormatter.cacheableFormatter(template: iTermAdvancedSettingsModel.logTimestampFormat())
        return "[\(formatter.string(from: Date()))] ".replacingUnicodeSpacesWithASCIISpace()
    }

    // MARK: - iTermCoprocessDelegate

    @objc(coprocess:didTerminateWithErrorOutput:)
    func coprocess(_ coprocess: Coprocess, didTerminateWithErrorOutput errors: String) {
        guard let session,
              let command = coprocess.command,
              !Coprocess.shouldIgnoreErrors(fromCommand: command) else {
            return
        }
        let commandCopy = command
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: "Coprocess “\(commandCopy)” terminated with output on stderr.",
            style: .warning,
            withActions: ["_View Errors", "Ignore Errors from This Command"],
            completion: { selection in
                if selection == 0 {
                    if let filename = NSWorkspace.shared.temporaryFileName(withPrefix: "coprocess-stderr.",
                                                                           suffix: ".txt") {
                        try? errors.write(toFile: filename, atomically: false, encoding: .utf8)
                        NSWorkspace.shared.open(URL(fileURLWithPath: filename))
                    }
                } else if selection == 1 {
                    Coprocess.setSilentlyIgnoreErrors(true, fromCommand: commandCopy)
                }
            }
        )
        session.queueAnnouncement(announcement, identifier: UUID().uuidString)
    }
}
