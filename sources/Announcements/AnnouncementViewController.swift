//
//  AnnouncementViewController.swift
//  iTerm2SharedARC
//
//  Migrated from iTermAnnouncementViewController.{h,m}.
//

import Cocoa

/// Delegate notified when an announcement finishes dismissing.
@objc(iTermAnnouncementDelegate)
protocol iTermAnnouncementDelegate: NSObjectProtocol {
    @objc(announcementWillDismiss:)
    func announcementWillDismiss(_ announcement: iTermAnnouncementViewController)
}

/// Manages an announcement banner view, optional auto-dismiss timer, and keyboard shortcuts.
@objc(iTermAnnouncementViewController)
final class iTermAnnouncementViewController: NSViewController {
    @objc weak var delegate: iTermAnnouncementDelegate?
    @objc var completion: ((Int32) -> Void)?
    @objc var isMarkdown = false

    private var _dismissOnKeyDown = false
    /// Once set to `true`, this cannot be unset due to view label appending.
    @objc var dismissOnKeyDown: Bool {
        get { _dismissOnKeyDown }
        set {
            guard newValue, !_dismissOnKeyDown else {
                return
            }
            _dismissOnKeyDown = true
            (view as? iTermAnnouncementView)?.addDismissOnKeyDownLabel()
        }
    }

    private var actions: [String] = []
    private var style: iTermAnnouncementViewStyle = .warning
    private var dismissing = false
    private var timer: Timer?
    private var visible = false
    private var timeout: TimeInterval = 0
    private var didTimeoutFlag = false

    @objc(announcementWithTitle:style:withActions:completion:)
    static func announcement(withTitle title: String,
                             style: iTermAnnouncementViewStyle,
                             withActions actions: [String],
                             completion: @escaping (Int32) -> Void) -> iTermAnnouncementViewController {
        makeController(title: title, isMarkdown: false, style: style, actions: actions, completion: completion)
    }

    @objc(announcementWithMarkdownTitle:style:withActions:completion:)
    static func announcement(withMarkdownTitle title: String,
                             style: iTermAnnouncementViewStyle,
                             withActions actions: [String],
                             completion: @escaping (Int32) -> Void) -> iTermAnnouncementViewController {
        makeController(title: title, isMarkdown: true, style: style, actions: actions, completion: completion)
    }

    private static func makeController(title: String,
                                       isMarkdown: Bool,
                                       style: iTermAnnouncementViewStyle,
                                       actions: [String],
                                       completion: @escaping (Int32) -> Void) -> iTermAnnouncementViewController {
        let controller = iTermAnnouncementViewController()
        controller.isMarkdown = isMarkdown
        controller.title = title
        controller.actions = actions
        controller.completion = completion
        controller.style = style
        return controller
    }

    override var description: String {
        String(format: "<%@: %p title=\"%@\" dismissing=%d>",
               String(describing: type(of: self)),
               self,
               title ?? "",
               dismissing ? 1 : 0)
    }

    override var title: String? {
        didSet {
            guard isViewLoaded, let announcementView = view as? iTermAnnouncementView else {
                return
            }
            announcementView.title = title ?? ""
        }
    }

    override func loadView() {
        let titleText = title ?? ""
        let handler: (Int32) -> Void = { [weak self] index in
            self?.didInvoke(index: index)
        }
        if isMarkdown {
            view = iTermAnnouncementView.announcementView(
                withMarkdownTitle: titleText,
                style: style,
                actions: actions,
                block: handler)
        } else {
            view = iTermAnnouncementView.announcementView(
                withTitle: titleText,
                style: style,
                actions: actions,
                block: handler)
        }
    }

    @objc func dismiss() {
        DLog("Dismiss announcement \(self) from\n\(Thread.callStackSymbols)")
        guard !dismissing else {
            return
        }
        dismissing = true
        visible = false
        timer?.invalidate()
        timer = nil
        (view as? iTermAnnouncementView)?.willDismiss()
        completion?(-2)
        delegate?.announcementWillDismiss(self)
    }

    /// Amount of time announcement will stay onscreen before auto-dismissing.
    @objc(setTimeout:)
    func setTimeout(_ timeout: TimeInterval) {
        self.timeout = timeout
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.didTimeout()
        }
    }

    /// Called when the announcement is displayed to the user.
    @objc func didBecomeVisible() {
        visible = true
        if timeout != 0 {
            setTimeout(timeout)
        }
    }

    /// Indicates whether the announcement has not yet timed out.
    @objc func shouldBecomeVisible() -> Bool {
        !didTimeoutFlag
    }

    @objc(handleKeyDown:)
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let handled = reallyHandleKeyDown(event)
        if !handled && dismissOnKeyDown {
            dismiss()
            return true
        }
        return handled
    }

    // MARK: - Private

    private func didInvoke(index: Int32) {
        DLog("Outer completion block invoked for announcement \(self)")
        guard !dismissing else {
            return
        }
        DLog("Invoking inner completion block with index \(index)")
        completion?(index)
        dismiss()
    }

    private func reallyHandleKeyDown(_ event: NSEvent) -> Bool {
        let relevantMask: NSEvent.ModifierFlags = [.option, .command, .shift, .control]
        guard event.modifierFlags.intersection(relevantMask) == [.option],
              let eventKey = event.charactersIgnoringModifiers?.uppercased() else {
            return false
        }
        guard let matchingIndex = actions.firstIndex(where: { action in
            guard let underscore = action.firstIndex(of: "_") else {
                return false
            }
            let nextIndex = action.index(after: underscore)
            guard nextIndex < action.endIndex else {
                return false
            }
            return String(action[nextIndex]).uppercased() == eventKey
        }) else {
            return false
        }
        (view as? iTermAnnouncementView)?.select(index: matchingIndex)
        return true
    }

    private func didTimeout() {
        timer = nil
        dismiss()
        didTimeoutFlag = true
    }
}
