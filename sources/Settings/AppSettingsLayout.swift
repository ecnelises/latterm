//
//  AppSettingsLayout.swift
//  Latterm
//

import AppKit

/// Responsive SwiftUI `ProfileSwiftUIForm` section-card layout for App Behavior (`GeneralPreferencesViewController`).
@objc(iTermGeneralFormLayout)
final class GeneralFormLayout: NSObject {
    @objc static func install(in tabs: NSTabView, controls: [String: NSView]) {
        func control<T: NSView>(_ key: String) -> T {
            guard let view = controls[key] as? T else {
                it_fatalError("Missing general settings control: \(key)")
            }
            return view
        }
        func field(_ key: String) -> NSTextField {
            SettingsControlFactory.label(key)
        }
        func checkbox(_ key: String,
                      label: NSTextField? = nil,
                      trailing: [NSView] = [],
                      helperViews: [NSView] = [],
                      indent: CGFloat = 0,
                      suppressSeparatorAfter: Bool = false) -> ProfileFormRow {
            ProfileFormRow(label: label,
                           content: .checkbox(control(key), trailing: trailing),
                           helperViews: helperViews,
                           indent: indent,
                           suppressSeparatorAfter: suppressSeparatorAfter)
        }

        let startupClosingSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: SettingsControlFactory.localized("When Latterm Starts"),
                rows: [
                    ProfileFormRow(
                        label: control("openWindowsAtStartupLabel"),
                        content: .wrappingLine([
                            .fill(control("openWindowsAtStartup"), minWidth: 200, maxWidth: 340, wraps: true),
                            .fixed(control("warningButton"), width: 26, wraps: false)
                        ])
                    ),
                    checkbox("openBookmark", suppressSeparatorAfter: true),
                    checkbox("restoreWindowsToSameSpaces", suppressSeparatorAfter: true),
                    checkbox("alwaysOpenWindowAtStartup", helperViews: [control("alwaysOpenLegend")])
                ]
            ),
            ProfileSectionCard(
                title: SettingsControlFactory.localized("Closing & Confirmation"),
                rows: [
                    checkbox("quitWhenAllWindowsClosed", suppressSeparatorAfter: true),
                    checkbox("confirmClosingMultipleSessions", suppressSeparatorAfter: true),
                    checkbox("promptOnQuit", suppressSeparatorAfter: true),
                    checkbox("evenIfThereAreNoWindows", indent: 20, suppressSeparatorAfter: true),
                    checkbox("disableConfirmationOnShutdown")
                ]
            )
        ]

        let toolsPerformanceSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    ProfileFormRow(
                        label: field("GPU Renderer:"),
                        content: .checkbox(control("gpuRendering"), trailing: [control("advancedGPU")]),
                        suppressSeparatorAfter: true
                    ),
                    checkbox("maximizeThroughput", label: field("Performance:")),
                    ProfileFormRow(
                        label: field("Instant Replay:"),
                        content: .wrappingLine([
                            .natural(control("irMemoryLabel"), minWidth: 60, maxWidth: 220, wraps: true),
                            .fixed(control("irMemory"), width: 64, wraps: false),
                            .natural(field("MB per session"), minWidth: 60, maxWidth: 180, wraps: false)
                        ])
                    ),
                    checkbox("savePasteHistory", label: field("Clipboard History:")),
                    ProfileFormRow(
                        label: field("Python API:"),
                        content: .checkbox(control("enableAPI"), trailing: []),
                        suppressSeparatorAfter: true
                    ),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .fill(control("apiPermission"), minWidth: 180, maxWidth: 320, wraps: true),
                            .fixed(control("pythonAPIAuthHelp"), width: 24, wraps: false)
                        ]),
                        indent: 20,
                        suppressSeparatorAfter: true
                    ),
                    checkbox("useCustomScriptsFolder", indent: 20, suppressSeparatorAfter: true),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .fill(control("customScriptsFolder"), minWidth: 180, maxWidth: .greatestFiniteMagnitude, wraps: true),
                            .fixed(control("customScriptsFolderWarning"), width: 16, wraps: false),
                            .natural(control("browseCustomScriptsFolder"), minWidth: 72, maxWidth: 160, wraps: false)
                        ]),
                        indent: 40
                    ),
                    checkbox("enableBonjour", label: field("Bonjour:"))
                ]
            )
        ]

        let selectionSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    checkbox("selectionCopiesText", label: field("Copy:"), suppressSeparatorAfter: true),
                    checkbox("copyLastNewline"),
                    checkbox("allowClipboardAccessFromTerminal", label: field("Access:"), suppressSeparatorAfter: true),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .natural(control("allowsSendingClipboardContentsLabel"), minWidth: 140, maxWidth: 320, wraps: true),
                            .natural(control("allowsSendingClipboardContents"), minWidth: 130, maxWidth: 220, wraps: false)
                        ]),
                        indent: 20
                    ),
                    ProfileFormRow(
                        label: field("Selection:"),
                        content: .wrappingLine([
                            .natural(control("wordCharsLabel"), minWidth: 140, maxWidth: 340, wraps: true),
                            .fixed(control("wordCharsHelp"), width: 24, wraps: false)
                        ]),
                        suppressSeparatorAfter: true
                    ),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .natural(control("wordMode"), minWidth: 140, maxWidth: 220, wraps: false),
                            .fill(control("wordChars"), minWidth: 160, maxWidth: .greatestFiniteMagnitude, wraps: true),
                            .fill(control("wordCharsRegex"), minWidth: 160, maxWidth: .greatestFiniteMagnitude, wraps: true)
                        ]),
                        suppressSeparatorAfter: true
                    ),
                    checkbox("tripleClickSelectsFullLines", suppressSeparatorAfter: true),
                    checkbox("doubleClickPerformsSmartSelection"),
                    checkbox("enterCopyModeAutomatically", label: field("Copy Mode:")),
                    checkbox("wrapDroppedFilenamesInQuotesWhenPasting", label: field("Pasting:"))
                ]
            )
        ]

        let placementContainer: NSView = control("placementContainer")
        let windowSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    ProfileFormRow(
                        label: field("New window placement:"),
                        content: .custom(hostedViews: [placementContainer]) { x, availableWidth, y, _ in
                            var cursorY: CGFloat = 0
                            for radio in placementContainer.subviews where !radio.isHidden {
                                let size = ProfileFormMeasurement.measureControl(radio, maxWidth: availableWidth)
                                let h = max(20, ceil(size.height))
                                radio.frame = NSRect(x: 0, y: cursorY, width: min(availableWidth, ceil(size.width) + 4), height: h)
                                cursorY += h + 4
                            }
                            let totalHeight = max(22, cursorY > 0 ? cursorY - 4 : 22)
                            // Flip internal radio positions top-down within non-flipped placementContainer
                            var flipTop = totalHeight
                            for radio in placementContainer.subviews where !radio.isHidden {
                                let h = radio.frame.height
                                flipTop -= h
                                radio.frame.origin.y = flipTop
                                flipTop -= 4
                            }
                            placementContainer.frame = NSRect(x: x, y: y, width: availableWidth, height: totalHeight)
                            return totalHeight
                        }
                    ),
                    checkbox("adjustWindowForFontSizeChange", label: field("Resizing:"), suppressSeparatorAfter: true),
                    checkbox("maxVertically"),
                    checkbox("lionStyleFullscreen", label: field("Full screen:")),
                    checkbox("separateWindowTitlePerTab", label: field("Titles:"))
                ]
            )
        ]

        let backupSyncSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    checkbox("loadPrefsFromCustomFolder", label: field("External  settings:"), suppressSeparatorAfter: true),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .fill(control("prefsCustomFolder"), minWidth: 180, maxWidth: .greatestFiniteMagnitude, wraps: true),
                            .fixed(control("prefsDirWarning"), width: 16, wraps: false),
                            .natural(control("browseCustomFolder"), minWidth: 72, maxWidth: 160, wraps: false)
                        ]),
                        suppressSeparatorAfter: true
                    ),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .natural(control("saveChangesLabel"), minWidth: 64, maxWidth: 160, wraps: false),
                            .fill(control("saveChanges"), minWidth: 150, maxWidth: 260, wraps: true),
                            .natural(control("pushToCustomFolder"), minWidth: 84, maxWidth: 160, wraps: false)
                        ])
                    ),
                    ProfileFormRow(
                        label: field("Backup & restore:"),
                        content: .wrappingLine([
                            .natural(control("exportAllButton"), minWidth: 120, maxWidth: 280, wraps: true),
                            .natural(control("importAllButton"), minWidth: 120, maxWidth: 280, wraps: true)
                        ])
                    ),
                    ProfileFormRow(
                        label: field("Reset:"),
                        content: .single(control("eraseAllButton"), fillsWidth: false, minWidth: 120, maxWidth: 280)
                    )
                ]
            )
        ]

        let tmuxSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    checkbox("openTmuxWindowsAsTabsInAttachingWindow", label: field("Attaching:"), suppressSeparatorAfter: true),
                    ProfileFormRow(
                        content: .wrappingLine([
                            .natural(control("whenAttachingTmuxLabel"), minWidth: 140, maxWidth: 340, wraps: true),
                            .natural(control("openUnrecognizedTmuxWindowsIn"), minWidth: 140, maxWidth: 240, wraps: false)
                        ]),
                        suppressSeparatorAfter: true
                    ),
                    checkbox("autoHideTmuxClientSession"),
                    checkbox("useTmuxProfile", label: field("Profile:")),
                    checkbox("useTmuxStatusBar",
                             label: field("Status Bar:"),
                             helperViews: [SettingsControlFactory.wrappingLabel("Requires tmux 2.9 or later.", smallSecondary: true)]),
                    ProfileFormRow(
                        label: field("Pausing:"),
                        content: .wrappingLine([
                            .natural(field("Pause a pane if it would take more than"), minWidth: 140, maxWidth: 320, wraps: true),
                            .fixed(control("tmuxPauseModeAgeLimit"), width: 64, wraps: false),
                            .natural(field("seconds to catch up"), minWidth: 80, maxWidth: 200, wraps: false)
                        ]),
                        suppressSeparatorAfter: true
                    ),
                    checkbox("tmuxWarnBeforePausing", suppressSeparatorAfter: true),
                    checkbox("unpauseTmuxAutomatically",
                             helperViews: [SettingsControlFactory.wrappingLabel("The “pause” feature requires tmux 3.2 or later.", smallSecondary: true)]),
                    checkbox("syncTmuxClipboard", label: field("Clipboard:"))
                ]
            )
        ]

        let experimentalSections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: nil,
                rows: [
                    checkbox("enableRTL", suppressSeparatorAfter: true),
                    checkbox("sshIntegrationForURLs")
                ]
            )
        ]

        let allGroups: [[ProfileSectionCard]] = [
            startupClosingSections,
            toolsPerformanceSections,
            selectionSections,
            windowSections,
            backupSyncSections,
            tmuxSections,
            experimentalSections
        ]
        it_assert(tabs.numberOfTabViewItems == allGroups.count,
                  "General form categories (\(tabs.numberOfTabViewItems)) must match layout groups (\(allGroups.count))")
        for (item, cards) in zip(tabs.tabViewItems, allGroups) {
            guard let root = item.view else { continue }
            ProfilePageHelpers.installDocument(cards, on: root)
        }
    }
}

/// Responsive SwiftUI `ProfileSwiftUIForm` section-card layout for Appearance (`AppearancePreferencesViewController`).
@objc(iTermAppearanceFormLayout)
final class AppearanceFormLayout: NSObject {
    @objc static func install(in tabs: NSTabView, controls: [String: NSView]) {
        func control<T: NSView>(_ key: String) -> T {
            guard let view = controls[key] as? T else {
                it_fatalError("Missing appearance settings control: \(key)")
            }
            return view
        }
        func field(_ key: String) -> NSTextField {
            SettingsControlFactory.label(key)
        }
        func checkbox(_ key: String,
                      label: NSTextField? = nil,
                      indent: CGFloat = 0,
                      suppressSeparatorAfter: Bool = false) -> ProfileFormRow {
            ProfileFormRow(label: label,
                           content: .checkbox(control(key), trailing: []),
                           indent: indent,
                           suppressSeparatorAfter: suppressSeparatorAfter)
        }

        let generalCard = ProfileSectionCard(
            title: nil,
            rows: [
                ProfileFormRow(label: control("tabStyleLabel"),
                               content: .single(control("tabStyle"), fillsWidth: false, minWidth: 160, maxWidth: 260)),
                ProfileFormRow(label: control("tabPositionLabel"),
                               content: .single(control("tabPosition"), fillsWidth: false, minWidth: 160, maxWidth: 260)),
                ProfileFormRow(label: control("statusBarPositionLabel"),
                               content: .single(control("statusBarPosition"), fillsWidth: false, minWidth: 160, maxWidth: 260)),
                checkbox("hideMenuBarInFullscreen", suppressSeparatorAfter: true),
                checkbox("uiElement", suppressSeparatorAfter: true),
                checkbox("uiElementRequiresHotkeyWindows", indent: 20, suppressSeparatorAfter: true),
                checkbox("hideMenuItemIcons")
            ]
        )

        let windowsCard = ProfileSectionCard(
            title: nil,
            rows: [
                checkbox("windowNumber", label: field("Title bar:"), suppressSeparatorAfter: true),
                checkbox("enableDivisionView", suppressSeparatorAfter: true),
                checkbox("enableProxyIcon"),
                checkbox("showWindowBorder", label: field("Aesthetics:"), suppressSeparatorAfter: true),
                checkbox("hideScrollbar", suppressSeparatorAfter: true),
                checkbox("disableFullscreenTransparency")
            ]
        )

        let tabsCard = ProfileSectionCard(
            title: nil,
            rows: [
                checkbox("newTabsOpenAtEndOfTabBar", label: field("New Tabs")),
                checkbox("hideTab", label: field("Visibility:"), suppressSeparatorAfter: true),
                checkbox("flashTabBarInFullscreenWhenSwitchingTabs", suppressSeparatorAfter: true),
                checkbox("showTabBarInFullscreen"),
                checkbox("preserveWindowSizeWhenTabBarVisibilityChanges", label: field("Resizing:"), suppressSeparatorAfter: true),
                checkbox("preserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges", indent: 20),
                checkbox("hideTabNumber", label: field("Features:"), suppressSeparatorAfter: true),
                checkbox("tabsHaveCloseButtons", suppressSeparatorAfter: true),
                checkbox("hideActivityIndicator", suppressSeparatorAfter: true),
                checkbox("showNewOutputIndicator"),
                checkbox("stretchTabsToFillBar", label: field("Appearance:")),
                checkbox("htmlTabTitles", label: field("HTML titles:"))
            ]
        )

        let panesCard = ProfileSectionCard(
            title: nil,
            rows: [
                checkbox("showPaneTitles", label: field("Per-pane UI:"), suppressSeparatorAfter: true),
                checkbox("showPaneTitlesEvenIfOnlyOnePane", indent: 20, suppressSeparatorAfter: true),
                checkbox("perPaneStatusBars", suppressSeparatorAfter: true),
                checkbox("separateBackgroundImages"),
                ProfileFormRow(
                    label: control("sideMarginsLabel"),
                    content: .wrappingLine([
                        .fixed(control("sideMargins"), width: 52, wraps: false),
                        .fixed(control("sideMarginsStepper"), width: 19, wraps: false)
                    ])
                ),
                ProfileFormRow(
                    label: control("topBottomMarginsLabel"),
                    content: .wrappingLine([
                        .fixed(control("topBottomMargins"), width: 52, wraps: false),
                        .fixed(control("topBottomMarginsStepper"), width: 19, wraps: false)
                    ])
                )
            ]
        )

        let dimmingSlider: NSSlider = control("dimmingAmount")
        let dimmingSliderHost: NSView = (dimmingSlider.superview as? iTermSlider) ?? dimmingSlider
        let dimmingCard = ProfileSectionCard(
            title: nil,
            rows: [
                ProfileFormRow(
                    label: control("dimmingAmountLabel"),
                    content: .single(dimmingSliderHost, fillsWidth: true, minWidth: 180, maxWidth: 320)
                ),
                checkbox("dimInactiveSplitPanes", suppressSeparatorAfter: true),
                checkbox("dimBackgroundWindows", suppressSeparatorAfter: true),
                checkbox("dimOnlyText")
            ]
        )

        let cardByIdentifier: [String: ProfileSectionCard] = [
            "General": generalCard,
            "Windows": windowsCard,
            "Tabs": tabsCard,
            "Panes": panesCard,
            "Dimming": dimmingCard
        ]
        for item in tabs.tabViewItems {
            guard let key = item.identifier as? String,
                  let card = cardByIdentifier[key],
                  let root = item.view else {
                continue
            }
            ProfilePageHelpers.installDocument([card], on: root)
        }
    }
}
