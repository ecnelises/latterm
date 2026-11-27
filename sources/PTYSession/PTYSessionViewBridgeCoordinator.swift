//
//  PTYSessionViewBridgeCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 5) to isolate view geometry/layout
//  policies, hotkey navigation, PUA font fallback, legacy drawing, and
//  split-pane width locking.
//

import Cocoa

enum PTYSessionViewLayoutPolicy {
    static func safeWrapperFrame(proposed: NSRect, minimumHeight: CGFloat) -> NSRect {
        if proposed.height >= minimumHeight {
            return proposed
        }
        var frame = proposed
        frame.size.height = minimumHeight
        return frame
    }

    static func clampedTmuxScrollViewSize(proposed: NSSize,
                                          ideal: NSSize,
                                          charWidth: CGFloat,
                                          lineHeight: CGFloat) -> NSSize {
        let maxWidth = ideal.width + charWidth - 1
        let maxHeight = ideal.height + lineHeight - 1
        return NSSize(width: min(proposed.width, maxWidth),
                      height: min(proposed.height, maxHeight))
    }

    static func useSeparateStatusBarsPerPane(preferenceEnabled: Bool, isTmuxClient: Bool) -> Bool {
        return preferenceEnabled && !isTmuxClient
    }

    static func splitPaneWidthLockAllowed(tmuxMode: PTYSessionTmuxMode,
                                          sessionCount: Int,
                                          hasVerticalSplitAncestor: Bool) -> Bool {
        if tmuxMode == TMUX_CLIENT || sessionCount <= 1 {
            return false
        }
        return hasVerticalSplitAncestor
    }

    static func selectionScrollAllowed(disabledInAltScreen: Bool,
                                       isAltScreen: Bool,
                                       isScrolledToBottom: Bool) -> Bool {
        if !disabledInAltScreen {
            return true
        }
        return !(isAltScreen && isScrolledToBottom)
    }
}

@objc final class PTYSessionViewBridgeCoordinator: NSObject, iTermLegacyViewDelegate {
    private weak var session: PTYSession?

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - iTermLegacyViewDelegate

    @objc(legacyView:drawRect:)
    func legacyView(_ legacyView: iTermLegacyView, draw dirtyRect: NSRect) {
        session?.textview?.draw(dirtyRect, in: legacyView)
    }

    // MARK: - PSMPUAFontProvider

    @objc(fontForPUACodePoint:)
    func font(forPUACodePoint codePoint: UTF32Char) -> NSFont? {
        return session?.textview?.fontTable.font(forPUACodePoint: codePoint)
    }

    // MARK: - iTermHotkeyNavigableSession

    @objc(sessionHotkeyDidNavigateToSession:)
    func sessionHotkeyDidNavigate(to shortcut: iTermShortcut?) {
        session?.reveal()
    }

    @objc func sessionHotkeyIsAlreadyFirstResponder() -> Bool {
        guard let textview = session?.textview,
              let window = textview.window else {
            return false
        }
        return NSApp.isActive &&
            NSApp.keyWindow === window &&
            window.firstResponder === textview
    }

    @objc func sessionHotkeyIsAlreadyActiveInNonkeyWindow() -> Bool {
        guard let session else { return false }
        if NSApp.isActive, let window = session.textview?.window, NSApp.keyWindow === window {
            return false
        }
        return session.delegate?.sessionIsActive(inSelectedTab: session) ?? false
    }

    // MARK: - SessionView & PTYTextView Geometry / Appearance

    @objc(sessionViewScrollViewWillResize:)
    func sessionViewScrollViewWillResize(_ proposedSize: NSSize) -> NSSize {
        guard let session,
              let view = session.view,
              let textview = session.textview else {
            return proposedSize
        }
        let splitsBeingDragged = session.delegate?.sessionBelongsToTmuxTabWhoseSplitsAreBeingDragged() ?? false
        guard session.isTmuxClient && !splitsBeingDragged else {
            return proposedSize
        }
        let idealSize = session.idealScrollViewSize(with: view.scrollview.scrollerStyle)
        return PTYSessionViewLayoutPolicy.clampedTmuxScrollViewSize(
            proposed: proposedSize,
            ideal: idealSize,
            charWidth: textview.charWidth,
            lineHeight: textview.lineHeight
        )
    }

    @objc func backingScaleFactor() -> CGFloat {
        guard let session else { return 1 }
        return session.delegate?.realParentWindow()?.window?.backingScaleFactor
            ?? session.view?.window?.backingScaleFactor
            ?? 0
    }

    @objc(safeFrameForWrapperViewFrame:)
    func safeFrameForWrapperViewFrame(_ proposed: NSRect) -> NSRect {
        guard let view = session?.view else {
            return proposed
        }
        return PTYSessionViewLayoutPolicy.safeWrapperFrame(
            proposed: proposed,
            minimumHeight: view.scrollview.contentSize.height
        )
    }

    @objc func sessionViewUseSeparateStatusBarsPerPane() -> Bool {
        guard let session else { return false }
        return PTYSessionViewLayoutPolicy.useSeparateStatusBarsPerPane(
            preferenceEnabled: iTermPreferences.bool(forKey: kPreferenceKeySeparateStatusBarsPerPane),
            isTmuxClient: session.isTmuxClient
        )
    }

    @objc func sessionViewDidChangeEffectiveAppearance() {
        guard let session else { return }
        session.sync()
        guard let profile = session.profile else { return }
        if iTermProfilePreferences.bool(forKey: KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE, inProfile: profile) {
            session.loadColors(fromProfile: profile)
        }
    }

    @objc func sessionViewStatusBarAdvancedConfigurationDictionary() -> [AnyHashable: Any] {
        guard let profile = session?.profile else { return [:] }
        let layout = iTermProfilePreferences.object(forKey: KEY_STATUS_BAR_LAYOUT, inProfile: profile) as? [AnyHashable: Any]
        return (layout?[iTermStatusBarLayoutKeyAdvancedConfiguration] as? [AnyHashable: Any]) ?? [:]
    }

    @objc func textViewPointsOnBottomToSuppressDrawing() -> CGFloat {
        guard let composer = session?.composerManager,
              composer.dropDownComposerViewIsVisible,
              composer.isAutoComposer,
              !composer.temporarilyHidden else {
            return 0
        }
        return composer.dropDownFrame.maxY
    }

    @objc func textViewLinesToSuppressDrawing() -> VT100GridRange {
        guard let session,
              let view = session.view,
              let textview = session.textview,
              session.composerManager.dropDownComposerViewIsVisible,
              session.composerManager.isAutoComposer,
              !session.composerManager.temporarilyHidden else {
            return VT100GridRangeMake(0, 0)
        }
        let rect = session.composerManager.dropDownFrame
        let textViewRect = textview.convert(rect, from: view)
        let topLeft = textview.coord(for: textViewRect.origin, allowRightMarginOverflow: false)
        let bottomRight = textview.coord(
            for: NSPoint(x: textViewRect.maxX - 1, y: textViewRect.maxY - 1),
            allowRightMarginOverflow: false
        )
        return VT100GridRangeMake(topLeft.y, bottomRight.y - topLeft.y + 1)
    }

    @objc func textViewCursorFrameInScreenCoords() -> NSRect {
        guard let session,
              let textview = session.textview else {
            return .zero
        }
        let cx = session.screen.cursorX() - 1
        let cy = session.screen.cursorY()
        let charWidth = textview.charWidth
        let lineHeight = textview.lineHeight
        let point = NSPoint(
            x: CGFloat(iTermPreferences.sideMargins()) + CGFloat(cx) * charWidth,
            y: CGFloat(session.screen.numberOfLines() - session.screen.height() + cy) * lineHeight
        )
        let windowPoint = textview.convert(point, to: nil)
        let origin = textview.window?.convertPoint(toScreen: windowPoint) ?? windowPoint
        return NSRect(x: origin.x, y: origin.y, width: charWidth, height: lineHeight)
    }

    @objc func textViewSelectionScrollAllowed() -> Bool {
        guard let session,
              let textview = session.textview,
              let profile = session.profile else {
            return true
        }
        let disabledInAltScreen = iTermProfilePreferences.bool(
            forKey: KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED,
            inProfile: profile
        )
        return PTYSessionViewLayoutPolicy.selectionScrollAllowed(
            disabledInAltScreen: disabledInAltScreen,
            isAltScreen: session.screen.terminalSoftAlternateScreenMode(),
            isScrolledToBottom: textview.scrolledToBottom
        )
    }

    @objc(textViewSplitPaneWidthIsLocked:)
    func textViewSplitPaneWidthIsLocked(_ allowedPtr: UnsafeMutablePointer<ObjCBool>) -> Bool {
        guard let session, let view = session.view else {
            allowedPtr.pointee = false
            return false
        }
        let sessionCount = session.delegate?.sessions().count ?? 0
        var hasVerticalSplit = false
        if session.tmuxMode != TMUX_CLIENT && sessionCount > 1 {
            var splitView = PTYSplitView.cast(from: view.superview)
            while let current = splitView, !current.isVertical {
                splitView = PTYSplitView.cast(from: current.superview)
            }
            hasVerticalSplit = splitView?.isVertical ?? false
        }
        let allowed = PTYSessionViewLayoutPolicy.splitPaneWidthLockAllowed(
            tmuxMode: session.tmuxMode,
            sessionCount: sessionCount,
            hasVerticalSplitAncestor: hasVerticalSplit
        )
        allowedPtr.pointee = ObjCBool(allowed)
        return view.preferredWidth != nil
    }

    @objc func textViewToggleLockSplitPaneWidth() {
        guard let view = session?.view else { return }
        if view.preferredWidth != nil {
            view.preferredWidth = nil
        } else {
            view.preferredWidth = NSNumber(value: Double(view.frame.size.width))
        }
    }
}
