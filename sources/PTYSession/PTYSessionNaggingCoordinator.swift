//
//  PTYSessionNaggingCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa

/// Target store for session profile mutations initiated from nagging actions.
enum PTYSessionProfileMutationTarget: Equatable {
    case sessionSpecific
    case sharedProfileModel
}

/// Pure policy calculations for nagging announcements and saved-arrangement actions.
struct PTYSessionNaggingPolicy {
    static func announcementObscuresCursor(announcementHeight: CGFloat,
                                           lineHeight: CGFloat,
                                           cursorY: Int32) -> Bool {
        guard lineHeight > 0 else {
            return false
        }
        let ratio = announcementHeight / lineHeight
        guard ratio.isFinite else {
            return false
        }
        let linesObscuredByAnnouncement = Int(ceil(ratio))
        return Int(cursorY) <= linesObscuredByAnnouncement
    }

    static func backgroundImageUpdatePayload(for filename: String?) -> [String: Any] {
        if let filename, !filename.isEmpty {
            return [KEY_BACKGROUND_IMAGE_LOCATION: filename]
        }
        return [KEY_BACKGROUND_IMAGE_LOCATION: NSNull()]
    }

    static func profileMutationTarget(isDivorced: Bool) -> PTYSessionProfileMutationTarget {
        return isDivorced ? .sessionSpecific : .sharedProfileModel
    }

    static func shouldReloadCodeReviewPrompt(mode: iTermWorkgroupSessionMode,
                                           hasRawCommand: Bool) -> Bool {
        return mode == .codeReview && hasRawCommand
    }
}

/// Tracks originating arrangement metadata and caches arrangement profile repair availability.
struct PTYSessionArrangementRepairCache {
    private(set) var originatingArrangementName: String?
    private(set) var originatingSessionGUID: String?
    private var cachedGeneration: Int = -1
    private var cachedCanChange: Bool = false

    mutating func setOriginating(arrangement: [AnyHashable: Any]?, name: String?) {
        originatingArrangementName = name
        originatingSessionGUID = arrangement?[SESSION_ARRANGEMENT_GUID] as? String
        cachedGeneration = -1
        cachedCanChange = false
    }

    mutating func canChangeProfile(currentGeneration: Int,
                                   hasWindowArrangements: Bool,
                                   finder: (String) -> Bool) -> Bool {
        guard originatingArrangementName != nil,
              let guid = originatingSessionGUID,
              hasWindowArrangements else {
            return false
        }
        if cachedGeneration == currentGeneration {
            return cachedCanChange
        }
        let found = finder(guid)
        cachedGeneration = currentGeneration
        cachedCanChange = found
        return found
    }

    static func replacingProfile(in sessionArrangement: [AnyHashable: Any],
                                 matchingGUID guid: String,
                                 with profile: [AnyHashable: Any]) -> [AnyHashable: Any] {
        guard (sessionArrangement[SESSION_ARRANGEMENT_GUID] as? String) == guid else {
            return sessionArrangement
        }
        var fixed = sessionArrangement
        fixed[SESSION_ARRANGEMENT_BOOKMARK] = profile
        return fixed
    }
}

/// Coordinates nagging prompts, announcement actions, and saved-arrangement profile repairs for a session.
@objc
final class PTYSessionNaggingCoordinator: NSObject, iTermNaggingControllerDelegate {
    private weak var session: PTYSession?
    private var arrangementCache = PTYSessionArrangementRepairCache()

    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - Saved Arrangement Metadata & Repair

    @objc(setOriginatingArrangement:name:)
    func setOriginating(arrangement: [AnyHashable: Any]?, name: String?) {
        arrangementCache.setOriginating(arrangement: arrangement, name: name)
    }

    @objc
    func canChangeProfileInArrangement() -> Bool {
        guard let arrangementName = arrangementCache.originatingArrangementName else {
            return false
        }
        let windowArrangements = (WindowArrangements.arrangement(withName: arrangementName) ?? [])
            .compactMap { $0 as? [AnyHashable: Any] }
        return arrangementCache.canChangeProfile(
            currentGeneration: WindowArrangements.generation,
            hasWindowArrangements: !windowArrangements.isEmpty
        ) { guid in
            windowArrangements.contains { windowArrangement in
                PseudoTerminal.arrangement(windowArrangement) { candidate in
                    (candidate?[SESSION_ARRANGEMENT_GUID] as? String) == guid
                }
            }
        }
    }

    @objc
    func changeProfileInArrangement() {
        guard canChangeProfileInArrangement(),
              let arrangementName = arrangementCache.originatingArrangementName,
              let guid = arrangementCache.originatingSessionGUID else {
            return
        }
        changeProfileInArrangementNamed(arrangementName, guid: guid) { [weak self] profile in
            guard let profile else {
                return
            }
            self?.session?.setProfile(profile, preservingName: true)
        }
    }

    private func changeProfileInArrangementNamed(_ arrangementName: String,
                                                 guid: String,
                                                 completion: @escaping ([AnyHashable: Any]?) -> Void) {
        let model = ProfileModel.sharedInstance()
        let alert = NSAlert()
        alert.messageText = "Select a profile to use for this session. Your selection will be saved back to the arrangement."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard let profiles = ProfileListView(frame: NSRect(x: 0, y: 0, width: 300, height: 300),
                                             model: model,
                                             font: nil) else {
            completion(nil)
            return
        }
        profiles.disableArrowHandler()
        alert.accessoryView = profiles

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] button in
            if button == .alertFirstButtonReturn {
                self?.reallyChangeProfileInArrangement(arrangementName,
                                                       guid: guid,
                                                       profiles: profiles,
                                                       completion: completion)
            } else {
                completion(nil)
            }
        }
        if let window = session?.view?.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func reallyChangeProfileInArrangement(_ arrangementName: String,
                                                  guid: String,
                                                  profiles: ProfileListView,
                                                  completion: @escaping ([AnyHashable: Any]?) -> Void) {
        let selectedGuid = profiles.selectedGuid as String?
        let profile = selectedGuid.flatMap { ProfileModel.sharedInstance()?.bookmark(withGuid: $0) }
        if let profile {
            setProfileInArrangement(arrangementName, withGUID: guid, toProfile: profile)
        }
        completion(profile)
    }

    private func setProfileInArrangement(_ arrangementName: String,
                                         withGUID guid: String,
                                         toProfile profile: [AnyHashable: Any]) {
        guard let windowArrangements = WindowArrangements.arrangement(withName: arrangementName) else {
            return
        }
        let modifiedArrangements: [Any] = windowArrangements.compactMap { entry in
            guard let arrangement = entry as? [AnyHashable: Any] else {
                return nil
            }
            return PseudoTerminal.modifiedArrangement(arrangement) { sessionArrangement in
                return PTYSessionArrangementRepairCache.replacingProfile(in: sessionArrangement ?? [:],
                                                                           matchingGUID: guid,
                                                                           with: profile)
            }
        }
        WindowArrangements.setArrangement(modifiedArrangements, withName: arrangementName)
    }

    // MARK: - iTermNaggingControllerDelegate

    func naggingControllerCanShowMessage(withIdentifier identifier: String) -> Bool {
        return !(session?.hasAnnouncement(withIdentifier: identifier) ?? false)
    }

    func naggingControllerShowMarkdownMessage(_ message: String,
                                              isQuestion: Bool,
                                              important: Bool,
                                              identifier: String,
                                              options: [String],
                                              completion: @escaping (Int32) -> Void) {
        showAnnouncement(message: message,
                         isMarkdown: true,
                         isQuestion: isQuestion,
                         important: important,
                         identifier: identifier,
                         options: options,
                         completion: completion)
    }

    func naggingControllerShowMessage(_ message: String,
                                      isQuestion: Bool,
                                      important: Bool,
                                      identifier: String,
                                      options: [String],
                                      completion: @escaping (Int32) -> Void) {
        showAnnouncement(message: message,
                         isMarkdown: false,
                         isQuestion: isQuestion,
                         important: important,
                         identifier: identifier,
                         options: options,
                         completion: completion)
    }

    private func showAnnouncement(message: String,
                                  isMarkdown: Bool,
                                  isQuestion: Bool,
                                  important: Bool,
                                  identifier: String,
                                  options: [String],
                                  completion: @escaping (Int32) -> Void) {
        guard let session else {
            return
        }
        let style: iTermAnnouncementViewStyle = isQuestion ? .question : .warning
        let announcement: iTermAnnouncementViewController
        if isMarkdown {
            announcement = iTermAnnouncementViewController.announcement(withMarkdownTitle: message,
                                                                        style: style,
                                                                        withActions: options) { selection in
                completion(selection)
            }
        } else {
            announcement = iTermAnnouncementViewController.announcement(withTitle: message,
                                                                        style: style,
                                                                        withActions: options) { selection in
                completion(selection)
            }
        }
        if !important {
            announcement.dismissOnKeyDown = true
        }
        session.queueAnnouncement(announcement, identifier: identifier)
    }

    func naggingControllerRepairSavedArrangement(_ savedArrangementName: String,
                                                 missingProfileNamed missingProfileName: String,
                                                 guid: String) {
        guard let similarlyNamedProfile = ProfileModel.sharedInstance()?.bookmark(withName: missingProfileName),
              let replacementGUID = similarlyNamedProfile[KEY_GUID] as? String else {
            return
        }
        iTermController.sharedInstance()?.repairSavedArrangementNamed(savedArrangementName,
                                                                      replacingMissingGUID: guid,
                                                                      withGUID: replacementGUID)
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: PTYSessionDidRepairSavedArrangement),
                                        object: guid,
                                        userInfo: ["new profile": similarlyNamedProfile])
    }

    func naggingControllerRemoveMessage(withIdentifier identifier: String) {
        session?.dismissAnnouncement(withIdentifier: identifier)
        session?.removeAnnouncement(withIdentifier: identifier)
    }

    func naggingControllerSetProfileProperties(_ dict: [AnyHashable: Any]) {
        session?.setSessionSpecificProfileValues(dict)
    }

    func naggingControllerAnnouncementWouldObscureCursor(forText text: String) -> Bool {
        guard let session,
              let view = session.view,
              let textview = session.textview else {
            return false
        }
        let announcementHeight = iTermAnnouncementView.estimatedHeight(forWidth: view.frame.size.width,
                                                                       text: text)
        return PTYSessionNaggingPolicy.announcementObscuresCursor(announcementHeight: announcementHeight,
                                                                  lineHeight: textview.lineHeight,
                                                                  cursorY: session.screen.cursorY())
    }

    func naggingControllerPrettyPrintJSON() {
        guard let session, let textview = session.textview else {
            return
        }
        let window = session.view?.window
        if let replacement = textview.replacementPayloadsForSelection().first(where: { $0.kind == .json }) {
            textview.replaceSelection(with: replacement)
            iTermWarning.show(withTitle: "You can find this feature under Edit > Replace Selection > Replace with Pretty-Printed JSON if you want to use it again.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Done!",
                              window: window)
        } else {
            iTermWarning.show(withTitle: "Looks like the selection changed and is no longer a valid JSON object.\nYou can find this feature under Edit > Replace Selection > Replace with Pretty-Printed JSON if you want to try again.",
                              actions: ["OK"],
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              window: window)
        }
    }

    func naggingControllerWindow() -> NSWindow? {
        return session?.view?.window
    }

    func naggingControllerRestart() {
        guard let session else {
            return
        }
        if PTYSessionNaggingPolicy.shouldReloadCodeReviewPrompt(mode: session.workgroupSessionMode,
                                                                hasRawCommand: session.codeReviewRawCommand != nil) {
            // Code-review sessions re-show the prompt overlay so the user
            // can edit the prompt before the program is rerun.
            session.reloadCodeReviewPromptOverlay()
            return
        }
        session.replaceTerminatedShellWithNewInstance()
    }

    func naggingControllerAbortDownload() {
        session?.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.stopReceivingFile()
        })
    }

    func naggingControllerAbortUpload() {
        session?.abortFileUpload()
    }

    func naggingControllerSetBackgroundImageToFile(withName filename: String?) {
        session?.setSessionSpecificProfileValues(
            PTYSessionNaggingPolicy.backgroundImageUpdatePayload(for: filename)
        )
    }

    func naggingControllerDisableMouseReportingPermanently(_ permanently: Bool) {
        guard let session else {
            return
        }
        session.screen.performBlock(joinedThreads: { [weak session] terminal, _, _ in
            if permanently, let session {
                switch PTYSessionNaggingPolicy.profileMutationTarget(isDivorced: session.isDivorced) {
                case .sessionSpecific:
                    session.setSessionSpecificProfileValues([KEY_XTERM_MOUSE_REPORTING: false])
                case .sharedProfileModel:
                    if let profile = session.profile,
                       let model = ProfileModel.sharedInstance() {
                        iTermProfilePreferences.setBool(false,
                                                        forKey: KEY_XTERM_MOUSE_REPORTING,
                                                        inProfile: profile,
                                                        model: model)
                        if let guid = profile[KEY_GUID] {
                            NotificationCenter.default.post(name: NSNotification.Name(rawValue: kSessionProfileDidChange),
                                                            object: guid)
                        }
                    }
                }
            }
            terminal?.mouseMode = .MOUSE_REPORTING_NONE
        })
    }

    func naggingControllerDisableBracketedPasteMode() {
        session?.screen.performBlock(joinedThreads: { terminal, _, _ in
            terminal?.bracketedPasteMode = false
        })
    }

    @objc
    func naggingControllerResetKeyReportingMode() {
        // Dispatch to avoid reentrant performBlock(joinedThreads:) when this runs from a side effect.
        DispatchQueue.main.async { [weak self] in
            self?.session?.screen.performBlock(joinedThreads: { terminal, _, _ in
                terminal?.resetKeyReportingModeLocally()
            })
        }
    }

    @objc(naggingControllerRestoreIconNameTo:windowName:)
    func naggingControllerRestoreIconName(to iconName: String, windowName: String) {
        session?.screenSetWindowTitle(windowName)
        session?.screenSetIconName(iconName)
    }

    func naggingControllerCloseSession() {
        guard let session else {
            return
        }
        session.delegate?.close(session)
    }

    func naggingControllerRepairInitialWorkingDirectoryOfSession(withGUID guid: String,
                                                                 inArrangementWithName arrangementName: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let path = panel.directoryURL?.path else {
            return
        }
        iTermController.sharedInstance()?.repairSavedArrangementNamed(arrangementName,
                                                                      replaceInitialDirectoryForSessionWithGUID: guid,
                                                                      with: path)
    }

    func naggingControllerDisableTriggersInInteractiveApps() {
        guard let session else {
            return
        }
        let update: [String: Any] = [KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS: false]
        switch PTYSessionNaggingPolicy.profileMutationTarget(isDivorced: session.isDivorced) {
        case .sessionSpecific:
            session.setSessionSpecificProfileValues(update)
            iTermNotificationController.sharedInstance()?.notify(
                NSLocalizedString("Session Updated", comment: "User notification"),
                withDescription: NSLocalizedString("Triggers disabled in interactive apps. You can change this in Edit Session > Advanced.", comment: "User notification")
            )
        case .sharedProfileModel:
            if let profile = session.profile,
               let model = ProfileModel.sharedInstance() {
                iTermProfilePreferences.setObjectsFrom(update, inProfile: profile, model: model)
            }
            iTermNotificationController.sharedInstance()?.notify(
                NSLocalizedString("Profile Updated", comment: "User notification"),
                withDescription: NSLocalizedString("Triggers disabled in interactive apps. You can change this in Settings > Profiles > Advanced.", comment: "User notification")
            )
        }
    }

    func naggingControllerAssignProfile(toSession arrangementName: String, guid: String) {
        changeProfileInArrangementNamed(arrangementName, guid: guid) { _ in }
    }
}
