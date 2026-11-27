//
//  PTYSessionAnnouncementCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 5) to isolate session announcement
//  queueing, lifecycle completion tracking, and horizontal-scroll notice UI.
//

import Cocoa

@objc final class PTYSessionAnnouncementCoordinator: NSObject {
    private weak var session: PTYSession?
    private var announcements: [String: iTermAnnouncementViewController] = [:]
    private let addAnnouncementHandler: ((iTermAnnouncementViewController) -> Void)?

    @objc(initWithSession:)
    convenience init(session: PTYSession) {
        self.init(session: session, addAnnouncementHandler: nil)
    }

    init(session: PTYSession?,
         addAnnouncementHandler: ((iTermAnnouncementViewController) -> Void)?) {
        self.session = session
        self.addAnnouncementHandler = addAnnouncementHandler
        super.init()
    }

    @objc(hasAnnouncementWithIdentifier:)
    func hasAnnouncement(withIdentifier identifier: String) -> Bool {
        return announcements[identifier] != nil
    }

    @objc(announcementWithIdentifier:)
    func announcement(withIdentifier identifier: String) -> iTermAnnouncementViewController? {
        return announcements[identifier]
    }

    @objc(dismissAnnouncementWithIdentifier:)
    func dismissAnnouncement(withIdentifier identifier: String) {
        announcements[identifier]?.dismiss()
    }

    @objc(removeAnnouncementWithIdentifier:)
    func removeAnnouncement(withIdentifier identifier: String) {
        announcements.removeValue(forKey: identifier)
    }

    @objc(setCompletion:inAnnouncement:identifier:)
    func setCompletion(_ completion: @escaping (Int32) -> Void,
                       in announcement: iTermAnnouncementViewController,
                       identifier: String) {
        announcement.completion = { [weak self] selection in
            completion(selection)
            if selection == -2 {
                self?.removeAnnouncement(withIdentifier: identifier)
            }
        }
    }

    @objc(queueAnnouncement:identifier:)
    func queueAnnouncement(_ announcement: iTermAnnouncementViewController,
                           identifier: String) {
        DLog("Enqueue announcement with identifier \(identifier)")
        dismissAnnouncement(withIdentifier: identifier)

        announcements[identifier] = announcement

        let originalCompletion = announcement.completion
        setCompletion({ selection in
            originalCompletion?(selection)
        }, in: announcement, identifier: identifier)

        if let addAnnouncementHandler {
            addAnnouncementHandler(announcement)
        } else {
            session?.view?.addAnnouncement(announcement)
        }
    }

    @objc func showHorizontalScrollInfo() {
        guard !iTermSwipeTracker.isSwipeTrackingDisabled() else {
            return
        }
        guard let session,
              (session.delegate?.realParentWindow()?.tabs.count ?? 0) >= 2 else {
            return
        }
        let warningKey = "NoSyncScrollingHorizontally"
        if iTermUserDefaults.userDefaults().bool(forKey: warningKey) {
            return
        }
        let identifier = "HorizontalScrollWarning"
        if hasAnnouncement(withIdentifier: identifier) {
            return
        }
        let announcement = iTermAnnouncementViewController.announcement(
            withTitle: "When mouse reporting is on, horizontal scrolling does not switch tabs.\nHold option while swiping or disable horizontal scroll reporting to switch tabs.",
            style: .warning,
            withActions: ["Settings…"]
        ) { selection in
            if selection == 0 {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyReportHorizontalScrollEvents)
            }
            iTermUserDefaults.userDefaults().set(true, forKey: warningKey)
        }
        queueAnnouncement(announcement, identifier: identifier)
    }
}
