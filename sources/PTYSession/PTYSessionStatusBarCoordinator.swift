//
//  PTYSessionStatusBarCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa

/// Resolution strategy for the status bar separator line color.
enum PTYSessionStatusBarSeparatorResolution: Equatable {
    case noneForMinimalStyle
    case custom(NSColor)
    case derivedFromText(appearanceName: NSAppearance.Name?, alpha: CGFloat)
}

/// Target profile store for reading/writing status bar configuration.
enum PTYSessionStatusBarPreferencesTarget: Equatable {
    case sessionSpecific
    case sharedProfile
}

/// Pure policy decisions for status bar theming, preference targeting, and window dragging.
struct PTYSessionStatusBarPolicy {
    static let defaultSeparatorAlpha: CGFloat = 0.25

    static func separatorResolution(isMinimalWindowStyle: Bool,
                                    configuredColor: NSColor?,
                                    tabStyle: iTermPreferencesTabStyle) -> PTYSessionStatusBarSeparatorResolution {
        if isMinimalWindowStyle {
            return .noneForMinimalStyle
        }
        if let configuredColor {
            return .custom(configuredColor)
        }
        let appearanceName: NSAppearance.Name?
        switch tabStyle {
        case .TAB_STYLE_DARK, .TAB_STYLE_DARK_HIGH_CONTRAST:
            appearanceName = .darkAqua
        case .TAB_STYLE_LIGHT, .TAB_STYLE_LIGHT_HIGH_CONTRAST:
            appearanceName = .aqua
        case .TAB_STYLE_AUTOMATIC, .TAB_STYLE_COMPACT, .TAB_STYLE_MINIMAL:
            appearanceName = nil
        @unknown default:
            appearanceName = nil
        }
        return .derivedFromText(appearanceName: appearanceName, alpha: defaultSeparatorAlpha)
    }

    static func preferencesTargetForOpen(isDivorced: Bool,
                                         overriddenFields: Set<String>) -> PTYSessionStatusBarPreferencesTarget {
        guard isDivorced,
              overriddenFields.contains(KEY_STATUS_BAR_LAYOUT) ||
              overriddenFields.contains(KEY_SHOW_STATUS_BAR) else {
            return .sharedProfile
        }
        return .sessionSpecific
    }

    static func profileModelTarget(isDivorced: Bool,
                                   overriddenFields: Set<String>) -> PTYSessionStatusBarPreferencesTarget {
        guard isDivorced, overriddenFields.contains(KEY_STATUS_BAR_LAYOUT) else {
            return .sharedProfile
        }
        return .sessionSpecific
    }

    static func canDragWindow(inPaneTitleBar: Bool,
                              delegateAllowsTitleBarDrag: () -> Bool) -> Bool {
        guard inPaneTitleBar else {
            return true
        }
        return delegateAllowsTitleBarDrag()
    }
}

/// Coordinates `iTermStatusBarViewControllerDelegate` behavior and styling for a session.
@objc
final class PTYSessionStatusBarCoordinator: NSObject, iTermStatusBarViewControllerDelegate {
    private weak var session: PTYSession?

    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - Helpers Bridged to PTYSession

    @objc
    func textColorForStatusBar() -> NSColor? {
        guard let session,
              let view = session.view,
              let tabStyle = view.window?.ptyWindow()?.it_tabStyle(),
              let colorMap = session.screen.colorMap as? iTermColorMap else {
            return nil
        }
        return iTermTheme.sharedInstance().statusBarTextColor(
            forEffectiveAppearance: view.effectiveAppearance,
            marginColor: session.textview?.colorForMargins,
            colorMap: colorMap,
            tabStyle: tabStyle,
            mainAndActive: (view.window?.isMainWindow == true) && NSApplication.shared.isActive
        )
    }

    @objc
    func updateStatusBarStyle() {
        guard let session else {
            return
        }
        session.statusBarViewController?.updateColors()
        session.invalidateStatusBar()
    }

    @objc
    func profileModel() -> ProfileModel {
        let overridden = session?.overriddenProfileFields ?? []
        switch PTYSessionStatusBarPolicy.profileModelTarget(isDivorced: session?.isDivorced ?? false,
                                                            overriddenFields: overridden) {
        case .sessionSpecific:
            return ProfileModel.sessionsInstance()
        case .sharedProfile:
            return ProfileModel.sharedInstance()
        }
    }

    // MARK: - iTermStatusBarViewControllerDelegate

    func statusBarHasDarkBackground() -> Bool {
        guard let window = session?.view?.window else {
            return false
        }
        if let ptyWindow = window.ptyWindow(), ptyWindow.it_terminalWindowUseMinimalStyle() {
            return ptyWindow.it_terminalWindowDecorationControlColor()?.isDark ?? false
        }
        // Called early in appearance transitions before contentView subviews finish updating.
        return window.contentView?.effectiveAppearance.it_isDark ?? false
    }

    func statusBarRevealComposer() -> Bool {
        session?.composerManager.revealMinimal()
        return false
    }

    func statusBarDefaultTextColor() -> NSColor? {
        return textColorForStatusBar()
    }

    func statusBarSeparatorColor() -> NSColor? {
        guard let session else {
            return nil
        }
        let isMinimal = session.view?.window?.ptyWindow()?.it_terminalWindowUseMinimalStyle() ?? false
        let configured = session.statusBarViewController?.layout.advancedConfiguration.separatorColor
        let rawTabStyle = iTermPreferences.int(forKey: kPreferenceKeyTabStyle)
        let tabStyle = iTermPreferencesTabStyle(rawValue: rawTabStyle) ?? .TAB_STYLE_AUTOMATIC

        switch PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: isMinimal,
                                                             configuredColor: configured,
                                                             tabStyle: tabStyle) {
        case .noneForMinimalStyle:
            return nil
        case let .custom(color):
            return color
        case let .derivedFromText(appearanceName, alpha):
            let appearance = appearanceName.flatMap { NSAppearance(named: $0) } ?? NSApplication.shared.effectiveAppearance
            guard let textColor = textColorForStatusBar() else {
                return nil
            }
            return textColor.it_color(with: appearance).withAlphaComponent(alpha)
        }
    }

    func statusBarBackgroundColor() -> NSColor? {
        return session?.statusBarViewController?.layout.advancedConfiguration.backgroundColor
    }

    func statusBarEdgeSeparatorColor() -> NSColor? {
        guard let tabStyle = session?.view?.window?.ptyWindow()?.it_tabStyle() else {
            return nil
        }
        return iTermTheme.sharedInstance().statusBarEdgeSeparatorColor(for: tabStyle)
    }

    func statusBarTerminalFont() -> NSFont? {
        return session?.textview?.fontTable.asciiFont.font
    }

    func statusBarTerminalBackgroundColor() -> NSColor? {
        return session?.effectiveProcessedBackgroundColor
    }

    func statusBarProcessInfoProvider() -> (any ProcessInfoProvider)? {
        return session?.processInfoProvider
    }

    func statusBarFindDriver() -> iTermFindDriver? {
        // Always use this session's find driver; synthetic sessions take ownership of the status bar VC.
        guard let view = session?.view else {
            return nil
        }
        view.createFindDriverIfNeeded()
        return view.findDriver
    }

    func statusBarWrite(_ string: String) {
        session?.writeTask(string)
    }

    func statusBarDidUpdate() {
        session?.view?.updateFindDriver()
    }

    func statusBarOpenPreferences(to component: (any iTermStatusBarComponent)?) {
        guard let session else {
            return
        }
        let overridden = session.overriddenProfileFields
        let target = PTYSessionStatusBarPolicy.preferencesTargetForOpen(isDivorced: session.isDivorced,
                                                                        overriddenFields: overridden)
        let panel: PreferencePanel?
        let guid: String?
        switch target {
        case .sessionSpecific:
            panel = PreferencePanel.sessionsInstance()
            guid = session.profile?[KEY_GUID] as? String
        case .sharedProfile:
            panel = PreferencePanel.sharedInstance()
            guid = session.originalProfile?[KEY_GUID] as? String
        }
        guard let panel else {
            return
        }
        session.openPreferencesPanel(panel,
                                     profileGuid: guid,
                                     componentIdentifier: component?.statusBarComponentIdentifier)
    }

    func statusBarDisable() {
        guard let session else {
            return
        }
        if session.isDivorced {
            session.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: false])
        } else if let profile = session.profile,
                  let model = ProfileModel.sharedInstance() {
            iTermProfilePreferences.setBool(false,
                                            forKey: KEY_SHOW_STATUS_BAR,
                                            inProfile: profile,
                                            model: model)
        }
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: kSessionProfileDidChange),
                                        object: session.profile?[KEY_GUID])
    }

    func statusBarCanDragWindow() -> Bool {
        guard let session else {
            return true
        }
        return PTYSessionStatusBarPolicy.canDragWindow(
            inPaneTitleBar: session.view?.statusBarIsInPaneTitleBar ?? false,
            delegateAllowsTitleBarDrag: {
                session.delegate?.sessionShouldDragWindow(byPaneTitleBar: session) ?? false
            }
        )
    }

    func statusBarActivityInfo() -> iTermActivityInfo {
        return session?.activityInfo ?? iTermActivityInfo(lastNewline: 0, lastActivity: 0)
    }

    func statusBarSetFilter(_ query: String?) {
        guard let session else {
            return
        }
        if let synthetic = session.delegate?.sessionSyntheticSession(for: session) {
            synthetic.swiftState.statusBarCoordinator.statusBarSetFilter(query)
            return
        }
        if let query {
            session.delegate?.session(session, setFilter: query)
        } else {
            session.stopFiltering()
        }
    }

    func statusBarSetLayout(_ layout: iTermStatusBarLayout) {
        guard let session,
              let originalProfile = session.originalProfile else {
            return
        }
        iTermProfilePreferences.setObject(layout.dictionaryValue(),
                                          forKey: KEY_STATUS_BAR_LAYOUT,
                                          inProfile: originalProfile,
                                          model: profileModel())
    }

    @objc(statusBarPerformAction:)
    func statusBarPerformAction(_ action: Any) {
        session?.applyActionObject(action)
    }

    func statusBarEditActions() {
        session?.delegate?.sessionEditActions()
    }

    func statusBarEditSnippets() {
        session?.delegate?.sessionEditSnippets()
    }

    func statusBarResignFirstResponder() {
        guard let responder = session?.mainResponder else {
            return
        }
        session?.textview?.window?.makeFirstResponder(responder)
    }

    func statusBarReportScriptingError(_ error: Error,
                                       forInvocation invocation: String,
                                       origin: String) {
        PTYSession.reportFunctionCallError(error,
                                           forInvocation: invocation,
                                           origin: origin,
                                           window: session?.delegate?.realParentWindow()?.window)
    }

    func statusBarTriggersDataSource() -> any TriggersDataSource {
        guard let session else {
            it_fatalError("statusBarTriggersDataSource accessed after session deallocation")
        }
        return session.triggersDataSource
    }
}
