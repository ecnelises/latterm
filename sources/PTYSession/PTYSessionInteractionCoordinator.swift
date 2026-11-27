//
//  PTYSessionInteractionCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 4) to isolate badge label configuration,
//  app-switching prevention detection, immutable color-map forwarding, and
//  popup delegate coordination.
//

import Cocoa

enum PTYSessionBadgePolicy {
    static func resolveFont(named fontName: String?,
                            pointSize: CGFloat,
                            isBold: Bool,
                            fontFactory: (String, CGFloat) -> NSFont? = { NSFont(name: $0, size: $1) },
                            boldConverter: (NSFont) -> NSFont = {
                                NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask)
                            }) -> NSFont? {
        var font: NSFont?
        if let fontName, !fontName.isEmpty {
            font = fontFactory(fontName, pointSize)
        }
        if font == nil {
            font = fontFactory("Helvetica", pointSize)
        }
        if isBold, let baseFont = font {
            font = boldConverter(baseFont)
        }
        return font
    }
}

@objc final class PTYSessionInteractionCoordinator: NSObject,
    iTermBadgeLabelDelegate,
    AppSwitchingPreventionDetectorDelegate,
    iTermImmutableColorMapDelegate,
    PopupDelegate {

    private weak var session: PTYSession?
    @objc var badgeFontName: String?
    private var currentBadgeSizeFraction: NSSize = .zero
    private lazy var appSwitchingDetector: AppSwitchingPreventionDetector = {
        let detector = AppSwitchingPreventionDetector()
        detector.delegate = self
        return detector
    }()

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    @objc(updateBadgeFontName:sizeFraction:)
    func updateBadge(fontName: String?, sizeFraction: NSSize) {
        self.badgeFontName = fontName
        self.currentBadgeSizeFraction = sizeFraction
    }

    // MARK: - App Switching Prevention

    @objc(notifyCommandDidStart:)
    func notifyCommandDidStart(_ command: String) {
        appSwitchingDetector.didExecute(command: command)
    }

    @objc(notifyCommandDidFinishWithStatus:)
    func notifyCommandDidFinish(status: Int32) {
        appSwitchingDetector.commandDidFinish(status: Int(status))
    }

    @objc func appSwitchingPreventionDetectorDidDetectFailure() {
        session?.naggingController.openCommandDidFailWithSecureInputEnabled()
    }

    // MARK: - iTermBadgeLabelDelegate

    @objc(badgeLabelFontOfSize:)
    func badgeLabelFont(ofSize pointSize: CGFloat) -> NSFont? {
        return PTYSessionBadgePolicy.resolveFont(
            named: badgeFontName,
            pointSize: pointSize,
            isBold: iTermAdvancedSettingsModel.badgeFontIsBold()
        )
    }

    @objc func badgeLabelSizeFraction() -> NSSize {
        return currentBadgeSizeFraction
    }

    // MARK: - iTermImmutableColorMapDelegate

    @objc(immutableColorMap:didChangeColorForKey:from:to:)
    func immutableColorMap(_ colorMap: iTermColorMapReading,
                           didChangeColorForKey theKey: iTermColorMapKey,
                           from before: NSColor?,
                           to after: NSColor?) {
        guard let session else { return }
        session.textview?.immutableColorMap(colorMap,
                                             didChangeColorForKey: theKey,
                                             from: before,
                                             to: after)
        session.swiftState.displayCoordinator.setNeedsComposerColorUpdate(true)
    }

    @objc(immutableColorMap:dimmingAmountDidChangeTo:)
    func immutableColorMap(_ colorMap: iTermColorMapReading,
                           dimmingAmountDidChangeTo dimmingAmount: Double) {
        guard let session else { return }
        session.textview?.immutableColorMap(colorMap, dimmingAmountDidChangeTo: dimmingAmount)
        session.swiftState.displayCoordinator.setNeedsComposerColorUpdate(true)
    }

    @objc(immutableColorMap:mutingAmountDidChangeTo:)
    func immutableColorMap(_ colorMap: iTermColorMapReading,
                           mutingAmountDidChangeTo mutingAmount: Double) {
        guard let session else { return }
        session.textview?.immutableColorMap(colorMap, mutingAmountDidChangeTo: mutingAmount)
        session.swiftState.displayCoordinator.setNeedsComposerColorUpdate(true)
    }

    // MARK: - PopupDelegate

    @objc func popupShouldTakePrefixFromScreen() -> Bool {
        guard let textview = session?.textview else {
            return false
        }
        return textview.window?.firstResponder === textview
    }

    @objc(popupWordsBeforeInsertionPoint:)
    func popupWords(beforeInsertionPoint count: Int32) -> [String] {
        guard let host = session?.popupHost() else {
            return [""]
        }
        return host.words(beforeInsertionPoint: Int(count))
    }

    @objc(popupIsSearching:)
    func popupIsSearching(_ searching: Bool) {
        guard let textview = session?.textview else {
            return
        }
        textview.showSearchingCursor = searching
        textview.requestDelegateRedraw()
    }

    @objc(popupWillClose:)
    func popupWillClose(_ popup: iTermPopupWindowController) {
        session?.delegate?.realParentWindow()?.popupWillClose(popup)
    }

    @objc func popupScreenVisibleFrame() -> NSRect {
        return session?.delegate?.realParentWindow()?.window?.screen?.visibleFrame ?? .zero
    }

    @objc func popupWindowIsInFloatingHotkeyWindow() -> Bool {
        return session?.delegate?.realParentWindow()?.isFloatingHotKeyWindow() ?? false
    }

    @objc func popupWindowShouldAvoidChangingWindowOrderOnClose() -> Bool {
        guard let session else {
            return false
        }
        let ffm = iTermPreferences.bool(forKey: kPreferenceKeyFocusFollowsMouse)
        let inHotkeyWindow = session.delegate?.sessionBelongs(toHotkeyWindow: session) ?? false
        return ffm && !inHotkeyWindow
    }

    @objc func popupVT100Screen() -> VT100Screen? {
        return session?.screen
    }

    @objc func popupPresenter() -> iTermPopupWindowPresenter? {
        return session
    }

    @objc(popupInsertText:popup:)
    func popupInsertText(_ string: String, popup popupWindowController: iTermPopupWindowController) {
        guard let session else { return }
        let shouldEscape = popupWindowController.shouldEscapeShellCharacters()
        if let host = session.popupHost() {
            if shouldEscape {
                host.popupWindowHostingInsertText((string as NSString).withEscapedShellCharacters(includingNewlines: true))
            } else {
                host.popupWindowHostingInsertText(string)
            }
            return
        }
        let composer = session.composerManager
        if composer.dropDownComposerViewIsVisible {
            composer.insertText(string)
            return
        }
        if shouldEscape && session.screen.isAtCommandPrompt {
            session.insertText((string as NSString).withEscapedShellCharacters(includingNewlines: true))
        } else {
            session.insertText(string)
        }
    }

    @objc(popupPreview:)
    func popupPreview(_ text: String) {
        guard let session, let host = session.popupHost() else {
            return
        }
        let firstLine = (text as NSString).firstNonEmptyLine as NSString
        let preview = firstLine.truncated(toLength: Int(max(0, session.screen.width())), ellipsis: "…")
        host.popupWindowHostSetPreview(preview)
    }

    @objc(popupKeyDown:)
    func popupKeyDown(_ event: NSEvent) {
        session?.textview?.keyDown(with: event)
    }
}
