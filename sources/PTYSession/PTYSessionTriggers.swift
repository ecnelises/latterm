//
//  PTYSessionTriggers.swift
//  iTerm2SharedARC
//

import AppKit

private let twoCoprocessesCanNotRunAtOnceAnnouncementIdentifier =
    "NoSyncTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier"

enum PTYSessionTriggerSupport {
    static func triggerNames(from dicts: [[AnyHashable: Any]]) -> [String] {
        dicts.compactMap { dict in
            guard let trigger = Trigger(fromUntrustedDict: dict) else {
                return nil
            }
            let title = type(of: trigger).title.removingSuffix("…")
            return "\(title) — \(trigger.regex)"
        }
    }

    static func enabledTriggerIndexes(from dicts: [[AnyHashable: Any]]) -> IndexSet {
        var indexes = IndexSet()
        for (index, dict) in dicts.enumerated() {
            let disabledValue = dict[kTriggerDisabledKey]
            let isDisabled = (disabledValue as? NSNumber)?.boolValue ??
                ((disabledValue as? NSString)?.boolValue ?? false)
            if !isDisabled {
                indexes.insert(index)
            }
        }
        return indexes
    }

    static func scrollRangeForStopScrolling(absLine: Int64,
                                            totalScrollbackOverflow: Int64,
                                            screenHeight: Int32,
                                            numberOfLines: Int32) -> VT100GridRange? {
        let line = absLine - totalScrollbackOverflow
        guard line >= 0, Int64(numberOfLines) >= line else {
            return nil
        }
        let height = max(Int32(1), screenHeight)
        let top = Int32(max(0, line - Int64(height) + 1))
        return VT100GridRangeMake(top, height)
    }

    static func canEnterWorkgroup(hasWorkgroup: Bool, isRestoring: Bool) -> Bool {
        !hasWorkgroup && !isRestoring
    }

    static func canExitWorkgroup(hasWorkgroup: Bool, leaderOnly: Bool, isLeader: Bool) -> Bool {
        guard hasWorkgroup else {
            return false
        }
        if leaderOnly && !isLeader {
            return false
        }
        return true
    }
}

// MARK: - iTermTriggerSideEffectExecutor

extension PTYSession {
    @objc(swift_triggerSessionSetBufferInput:)
    func triggerSessionSetBufferInput(_ shouldBuffer: Bool) {
        if buffering == shouldBuffer {
            return
        }
        toggleBufferInput()
    }

    @objc(swift_triggerSideEffectShowAlertWithMessage:rateLimit:disable:)
    func triggerSideEffectShowAlert(withMessage message: String,
                                    rateLimit: iTermRateLimitedUpdate,
                                    disable: @escaping () -> Void) {
        iTermGCD.assertMainQueueSafe()
        // Dispatch because it's not safe to start a runloop in a side-effect.
        DispatchQueue.main.async { [weak self] in
            self?.reallyShowTriggerAlert(message: message, rateLimit: rateLimit, disable: disable)
        }
    }

    private func reallyShowTriggerAlert(message: String,
                                        rateLimit: iTermRateLimitedUpdate,
                                        disable: @escaping () -> Void) {
        rateLimit.performRateLimitedBlock { [weak self] in
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show Session")
            alert.addButton(withTitle: "Disable This Alert")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                self?.reveal()
            case .alertThirdButtonReturn:
                disable()
            default:
                break
            }
        }
    }

    @objc(swift_triggerSideEffectLaunchCoprocessWithCommand:identifier:silent:triggerTitle:)
    func triggerSideEffectLaunchCoprocess(withCommand command: String,
                                          identifier: String?,
                                          silent: Bool,
                                          triggerTitle triggerName: String) {
        iTermGCD.assertMainQueueSafe()
        launchCoprocess(command: command,
                        identifier: identifier,
                        silent: silent,
                        triggerTitle: triggerName)
    }

    @objc(launchCoprocessWithCommand:identifier:silent:triggerTitle:)
    func launchCoprocess(command: String,
                         identifier: String?,
                         silent: Bool,
                         triggerTitle name: String) {
        if hasCoprocess {
            if let identifier, iTermUserDefaults.userDefaults().bool(forKey: identifier) {
                return
            }
            let message = "\(name): Can’t run two coprocesses at once."
            let actions = identifier != nil ? ["Silence Warning"] : []
            let announcement = iTermAnnouncementViewController.announcement(
                withTitle: message,
                style: .warning,
                withActions: actions
            ) { selection in
                guard let identifier else {
                    return
                }
                if selection == 0 {
                    iTermUserDefaults.userDefaults().set(true, forKey: identifier)
                }
            }
            queueAnnouncement(announcement,
                              identifier: twoCoprocessesCanNotRunAtOnceAnnouncementIdentifier)
        } else if silent {
            launchSilentCoprocess(withCommand: command)
        } else {
            launchCoprocess(withCommand: command)
        }
    }

    @objc(swift_triggerSideEffectPostUserNotificationWithMessage:)
    func triggerSideEffectPostUserNotification(withMessage message: String) {
        iTermGCD.assertMainQueueSafe()
        let notificationController = iTermNotificationController.sharedInstance()
        let tabNumber = delegate?.tabNumber() ?? 0
        let triggerDescription = "A trigger fired in session “\(name.removingHTMLFromTabTitleIfNeeded())” in tab #\(tabNumber)."
        _ = notificationController?.notify(
            message,
            withDescription: triggerDescription,
            windowIndex: screenWindowIndex(),
            tabIndex: screenTabIndex(),
            viewIndex: screenViewIndex()
        )
    }

    // Scroll so that `absLine` is the last visible onscreen.
    @objc(swift_triggerSideEffectStopScrollingAtLine:)
    func triggerSideEffectStopScrolling(atLine absLine: Int64) {
        iTermGCD.assertMainQueueSafe()
        guard let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: absLine,
            totalScrollbackOverflow: screen.totalScrollbackOverflow(),
            screenHeight: screen.height(),
            numberOfLines: screen.numberOfLines()
        ) else {
            return
        }
        textview?.scrollLineNumberRange(intoView: range)
        view?.scrollview.ptyVerticalScroller()?.userScroll = true
    }

    @objc(swift_triggerSideEffectOpenPasswordManagerToAccountName:)
    func triggerSideEffectOpenPasswordManager(toAccountName accountName: String?) {
        iTermGCD.assertMainQueueSafe()
        // Dispatch because you can't have a runloop in a side-effect and the password manager is a bunch of modal UI.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let appDelegate = iTermApplication.shared().delegate as? iTermApplicationDelegate else {
                return
            }
            appDelegate.openPasswordManager(toAccountName: accountName, in: self)
        }
    }

    @objc(swift_triggerSideEffectRunBackgroundCommand:pool:)
    func triggerSideEffectRunBackgroundCommand(_ command: String,
                                             pool: iTermBackgroundCommandRunnerPool) {
        iTermGCD.assertMainQueueSafe()
        guard let runner = pool.requestBackgroundCommandRunner(terminationBlock: nil) else {
            return
        }
        runner.command = command
        runner.title = "Run Command Trigger"
        runner.notificationTitle = "Run Command Trigger Failed"
        runner.shell = userShell ?? ""
        runner.run()
    }

    @objc(swift_triggerWriteTextWithoutBroadcasting:)
    func triggerWriteTextWithoutBroadcasting(_ text: String) {
        writeTaskNoBroadcast(text)
    }

    @objc(swift_triggerSideEffectVariableScope)
    func triggerSideEffectVariableScope() -> iTermVariableScope {
        iTermGCD.assertMainQueueSafe()
        return genericScope
    }

    @objc(swift_triggerSideEffectSetTitle:)
    func triggerSideEffectSetTitle(_ newName: String) {
        iTermGCD.assertMainQueueSafe()
        genericScope.setValuesFrom([
            iTermVariableKeySessionTriggerName: newName,
            iTermVariableKeySessionAutoNameFormat: newName
        ])
        if !newName.isEmpty {
            enableNameTitleComponentIfPossible()
        }
    }

    @objc(swift_triggerSideEffectEnterWorkgroupWithIdentifier:)
    func triggerSideEffectEnterWorkgroup(withIdentifier workgroupUniqueIdentifier: String) {
        iTermGCD.assertMainQueueSafe()
        guard PTYSessionTriggerSupport.canEnterWorkgroup(
            hasWorkgroup: workgroupInstance != nil,
            isRestoring: iTermWorkgroupRestoration.isRestoring(guid: guid)
        ) else {
            return
        }
        // Defer to the next main-runloop tick because workgroup entry splits panes
        // and calls performBlockWithJoinedThreads, which asserts we're outside side-effects.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workgroupInstance == nil else {
                return
            }
            iTermWorkgroupController.instance.enter(workgroupUniqueIdentifier: workgroupUniqueIdentifier,
                                                    on: self)
        }
    }

    @objc(swift_triggerSideEffectExitWorkgroupLeaderOnly:)
    func triggerSideEffectExitWorkgroup(leaderOnly: Bool) {
        iTermGCD.assertMainQueueSafe()
        guard PTYSessionTriggerSupport.canExitWorkgroup(
            hasWorkgroup: workgroupInstance != nil,
            leaderOnly: leaderOnly,
            isLeader: workgroupInstance?.mainSession === self
        ) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  PTYSessionTriggerSupport.canExitWorkgroup(
                      hasWorkgroup: self.workgroupInstance != nil,
                      leaderOnly: leaderOnly,
                      isLeader: self.workgroupInstance?.mainSession === self
                  ) else {
                return
            }
            iTermWorkgroupController.instance.exit(on: self)
        }
    }

    @objc(swift_triggerSideEffectInvokeFunctionCall:withVariables:captures:trigger:)
    func triggerSideEffectInvokeFunctionCall(_ invocation: String,
                                             withVariables temporaryVariables: [AnyHashable: Any],
                                             captures captureStringArray: [String],
                                             trigger: Trigger) {
        iTermGCD.assertMainQueueSafe()
        let scope = genericScope.addingBackreferences(captureStringArray, owner: trigger)
        if let stringKeyedVariables = temporaryVariables as? [String: Any] {
            scope.setValuesFrom(stringKeyedVariables)
        } else {
            for (key, value) in temporaryVariables {
                if let stringKey = key as? String {
                    scope.setValue(value, forVariableNamed: stringKey)
                }
            }
        }
        invokeFunctionCall(invocation, scope: scope, origin: "Trigger")
    }

    @objc(swift_triggerSideEffectSetValue:forVariableNamed:)
    func triggerSideEffectSetValue(_ value: Any?, forVariableNamed name: String) {
        iTermGCD.assertMainQueueSafe()
        genericScope.setValue(value, forVariableNamed: name)
    }

    @objc(swift_triggerSideEffectCurrentDirectoryDidChange:)
    func triggerSideEffectCurrentDirectoryDidChange(_ newPath: String) {
        iTermGCD.assertMainQueueSafe()
        didUpdateCurrentDirectory(newPath)
    }
}

// MARK: - iTermTriggersDataSource

extension PTYSession: TriggersDataSource {
    var numberOfTriggers: Int {
        triggerProfileDicts?.count ?? 0
    }

    var triggerNames: [String] {
        PTYSessionTriggerSupport.triggerNames(from: triggerProfileDicts ?? [])
    }

    var enabledTriggerIndexes: NSIndexSet {
        PTYSessionTriggerSupport.enabledTriggerIndexes(from: triggerProfileDicts ?? []) as NSIndexSet
    }

    @objc(toggleTriggerAtIndex:)
    func toggleTrigger(index: Int) {
        toggleTriggerEnabled(at: index)
    }

    @objc(addTrigger)
    func addTrigger() {
        openAddTriggerViewController(withText: textview?.selectedText ?? "")
    }

    @objc(editTriggers)
    func editTriggers() {
        openTriggersViewController()
    }
}

// MARK: - TriggerDelegate

extension PTYSession: TriggerDelegate {
    @objc(triggerChanged:newValue:)
    public func triggerChanged(_ triggerController: TriggerController, newValue value: [Any]) {
        if let undoManager = triggerController.window?.undoManager {
            undoManager.registerUndo(withTarget: self,
                                     selector: #selector(setTriggersValue(_:)),
                                     object: profile?[KEY_TRIGGERS])
            undoManager.setActionName("Edit Triggers")
        }
        setSessionSpecificProfileValues([KEY_TRIGGERS: value])
        if let guid = profile?[KEY_GUID] as? String {
            triggerController.guid = guid
        }
    }

    @objc private func setTriggersValue(_ value: [Any]) {
        setSessionSpecificProfileValues([KEY_TRIGGERS: value])
        if let guid = profile?[KEY_GUID] as? String {
            triggerWindowController?.guid = guid
        }
        triggerWindowController?.profileDidChange()
    }

    @objc(triggerSetUseInterpolatedStrings:)
    public func triggerSetUseInterpolatedStrings(_ useInterpolatedStrings: Bool) {
        setSessionSpecificProfileValues([KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: useInterpolatedStrings])
        if let guid = profile?[KEY_GUID] as? String {
            triggerWindowController?.guid = guid
        }
    }

    @objc(triggersCloseSheet)
    public func triggersCloseSheet() {
        closeTriggerWindowController()
    }

    @objc(triggersCopyToProfile)
    public func triggersCopyToProfile() {
        guard let originalGuid = profile?[KEY_ORIGINAL_GUID] as? String else {
            return
        }
        ProfileModel.updateSharedProfile(
            withGUID: originalGuid,
            newValues: [
                KEY_TRIGGERS: profile?[KEY_TRIGGERS] ?? [],
                KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: profile?[KEY_TRIGGERS_USE_INTERPOLATED_STRINGS] ?? false
            ]
        )
    }
}
