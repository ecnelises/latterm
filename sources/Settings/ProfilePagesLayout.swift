//
//  ProfilePagesLayout.swift
//  iTerm2SharedARC
//
//  Responsive section-card layouts for all 8 Profiles tabs and Edit Current Session.
//

import AppKit
import BetterFontPicker

private enum ProfilePageHelpers {
    static func sectionTitle(from label: NSTextField?, fallback: String = "") -> String {
        guard let raw = label?.stringValue, !raw.isEmpty else {
            return fallback
        }
        let cleaned = raw
            .replacingOccurrences(of: "[:：\\s]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func localizedSection(_ key: String) -> String {
        NSLocalizedString(key, comment: "Profile settings section title")
    }

    static func sliderContainer(for slider: NSSlider) -> NSView {
        if let wrapper = slider.superview as? iTermSlider {
            return wrapper
        }
        return slider
    }

    static func embeddedScrollView(for tableView: NSTableView) -> NSView {
        return tableView.enclosingScrollView ?? tableView
    }

    static func installDocument(_ sections: [ProfileSectionCard],
                                on rootView: NSView,
                                stateContainersToKeep: [NSView] = []) {
        let doc = ProfileFormDocumentView(sections: sections)
        let keepSet = Set(stateContainersToKeep.map { ObjectIdentifier($0) })

        for container in stateContainersToKeep {
            if container.superview !== doc {
                container.removeFromSuperview()
                container.autoresizingMask = []
                doc.addSubview(container)
            }
            container.frame = .zero
        }

        let leftovers = rootView.subviews.filter { view in
            !(view is ProfileFormDocumentView) && !keepSet.contains(ObjectIdentifier(view))
        }
        for previousDoc in rootView.subviews where previousDoc is ProfileFormDocumentView {
            previousDoc.removeFromSuperview()
        }
        doc.adoptHiddenLegacyViews(leftovers)

        rootView.it_installInlineProfileForm(doc)
        doc.invalidateFormLayout()
    }

    static func findTableView(in root: NSView) -> NSTableView? {
        if let table = root as? NSTableView {
            return table
        }
        for child in root.subviews {
            if let found = findTableView(in: child) {
                return found
            }
        }
        return nil
    }

    static func naturalTableContainerHeight(in container: NSView,
                                            minHeight: CGFloat,
                                            maxHeight: CGFloat,
                                            extraChrome: CGFloat = 0) -> CGFloat {
        guard let table = findTableView(in: container) else {
            return minHeight
        }
        let rows = max(0, table.numberOfRows)
        let rowStep = max(20, table.rowHeight + table.intercellSpacing.height)
        let headerH = table.headerView?.frame.height ?? 0
        let desired = headerH + CGFloat(rows) * rowStep + 14 + extraChrome
        return min(maxHeight, max(minHeight, ceil(desired)))
    }

    static func colorWellPairRow(rowLabel: NSTextField?,
                                 firstHeader: NSTextField,
                                 firstWell: NSView,
                                 secondHeader: NSTextField,
                                 secondWell: NSView,
                                 suppressSeparatorAfter: Bool = false) -> ProfileFormRow {
        ProfileFormMeasurement.configureStaticLabel(firstHeader, alignment: .left)
        ProfileFormMeasurement.configureStaticLabel(secondHeader, alignment: .left)
        return ProfileFormRow(
            label: rowLabel,
            content: .custom(hostedViews: [firstHeader, firstWell, secondHeader, secondWell]) { x, availableWidth, y, _ in
                let header1Size = ProfileFormMeasurement.measureStaticText(firstHeader, maxWidth: availableWidth)
                let header2Size = ProfileFormMeasurement.measureStaticText(secondHeader, maxWidth: availableWidth)
                let wellW: CGFloat = 44
                let wellH: CGFloat = 22
                let pair1W = max(header1Size.width, wellW)
                let pair2W = max(header2Size.width, wellW)
                let pairGap: CGFloat = 28

                if pair1W + pairGap + pair2W <= availableWidth {
                    firstHeader.frame = NSRect(x: x, y: y, width: pair1W, height: header1Size.height)
                    secondHeader.frame = NSRect(x: x + pair1W + pairGap, y: y, width: pair2W, height: header2Size.height)
                    let wellY = y + max(header1Size.height, header2Size.height) + 4
                    firstWell.frame = NSRect(x: x, y: wellY, width: wellW, height: wellH)
                    secondWell.frame = NSRect(x: x + pair1W + pairGap, y: wellY, width: wellW, height: wellH)
                    return wellY + wellH - y
                } else {
                    var cursorY = y
                    firstHeader.frame = NSRect(x: x, y: cursorY, width: availableWidth, height: header1Size.height)
                    cursorY += header1Size.height + 4
                    firstWell.frame = NSRect(x: x, y: cursorY, width: wellW, height: wellH)
                    cursorY += wellH + 8
                    secondHeader.frame = NSRect(x: x, y: cursorY, width: availableWidth, height: header2Size.height)
                    cursorY += header2Size.height + 4
                    secondWell.frame = NSRect(x: x, y: cursorY, width: wellW, height: wellH)
                    return cursorY + wellH - y
                }
            },
            suppressSeparatorAfter: suppressSeparatorAfter
        )
    }

    static func tableWithAddRemoveRow(scrollView: NSView,
                                      addButton: NSView,
                                      removeButton: NSView,
                                      trailingViews: [NSView] = [],
                                      tableHeight: CGFloat) -> ProfileFormRow {
        var hosted: [NSView] = [scrollView, addButton, removeButton]
        hosted.append(contentsOf: trailingViews)
        return ProfileFormRow(
            content: .custom(hostedViews: hosted) { x, availableWidth, y, _ in
                let dynamicH = ProfilePageHelpers.naturalTableContainerHeight(
                    in: scrollView,
                    minHeight: tableHeight,
                    maxHeight: 360
                )
                scrollView.frame = NSRect(x: x, y: y, width: availableWidth, height: dynamicH)
                let toolbarY = y + dynamicH + 8
                let buttonH: CGFloat = 24
                let addW: CGFloat = 26
                let removeW: CGFloat = 26
                addButton.frame = NSRect(x: x, y: toolbarY, width: addW, height: buttonH)
                removeButton.frame = NSRect(x: x + addW + 2, y: toolbarY, width: removeW, height: buttonH)

                var bottomY = toolbarY + buttonH
                let visibleTrailing = trailingViews.filter { !$0.isHidden }
                if !visibleTrailing.isEmpty {
                    let inlineStartX = x + addW + removeW + 12
                    let inlineWidth = availableWidth - (inlineStartX - x)
                    var cursorX = inlineStartX
                    var lineY = toolbarY
                    var rowMaxH = buttonH
                    for view in visibleTrailing {
                        let size = ProfileFormMeasurement.measureControl(view, maxWidth: max(80, availableWidth))
                        if cursorX > inlineStartX && cursorX + size.width > x + availableWidth {
                            lineY = max(lineY + rowMaxH + 6, toolbarY + buttonH + 6)
                            cursorX = x
                            rowMaxH = size.height
                            let fullSize = ProfileFormMeasurement.measureControl(view, maxWidth: availableWidth)
                            view.frame = NSRect(x: cursorX, y: lineY, width: fullSize.width, height: fullSize.height)
                            cursorX += fullSize.width + 8
                            bottomY = max(bottomY, lineY + fullSize.height)
                        } else if inlineWidth >= 80 {
                            let yOffset = lineY == toolbarY ? floor((buttonH - size.height) / 2.0) : 0
                            view.frame = NSRect(x: cursorX, y: lineY + max(0, yOffset), width: size.width, height: size.height)
                            cursorX += size.width + 8
                            bottomY = max(bottomY, lineY + max(buttonH, size.height))
                        } else {
                            lineY = toolbarY + buttonH + 6
                            let fullSize = ProfileFormMeasurement.measureControl(view, maxWidth: availableWidth)
                            view.frame = NSRect(x: x, y: lineY, width: fullSize.width, height: fullSize.height)
                            bottomY = max(bottomY, lineY + fullSize.height)
                        }
                    }
                }
                return bottomY - y
            },
            fullCardWidth: true
        )
    }
}

// MARK: - 1. Basics / General

extension ProfilesGeneralPreferencesViewController {
    @objc func installProfileLayout() {
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Profile Identity"),
                rows: [
                    ProfileFormRow(label: profileNameFieldLabel,
                                   content: .single(profileNameField, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: shortcutLabel,
                                   content: .single(profileShortcut, fillsWidth: true, minWidth: 140, maxWidth: 280)),
                    ProfileFormRow(label: tagsLabel,
                                   content: .single(tagsTokenField, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: subtitleLabel,
                                   content: .single(subtitleText, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude),
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.subtitleText.isHidden
                                   }),
                    ProfileFormRow(
                        label: subtitleLabel,
                        content: .custom(hostedViews: [tallTabBarRequestView]) { x, availableWidth, y, _ in
                            let subviews = self.tallTabBarRequestView.subviews
                            let label = subviews.compactMap { $0 as? NSTextField }.first
                            let button = subviews.compactMap { $0 as? NSButton }.first
                            var innerY: CGFloat = 0
                            if let label {
                                ProfileFormMeasurement.configureStaticLabel(label, alignment: .left)
                                let size = ProfileFormMeasurement.measureStaticText(label, maxWidth: availableWidth)
                                label.frame = NSRect(x: 0, y: innerY, width: availableWidth, height: size.height)
                                innerY += size.height + 6
                            }
                            if let button {
                                let bSize = ProfileFormMeasurement.measureControl(button, maxWidth: availableWidth)
                                button.frame = NSRect(x: 0, y: innerY, width: bSize.width, height: bSize.height)
                                innerY += bSize.height
                            }
                            let h = max(24, innerY)
                            self.tallTabBarRequestView.frame = NSRect(x: x, y: y, width: availableWidth, height: h)
                            return h
                        },
                        isVisible: { [weak self] in
                            guard let self else { return false }
                            return !self.tallTabBarRequestView.isHidden
                        }
                    ),
                    ProfileFormRow(label: iconLabel,
                                   content: .wrappingLine([
                                       .fill(icon, minWidth: 140, maxWidth: 320, wraps: false),
                                       .fixed(imageWell, width: 26, wraps: false)
                                   ]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Badge & Title"),
                rows: [
                    ProfileFormRow(label: badgeLabel,
                                   content: .wrappingLine([
                                       .fill(badgeText, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .natural(editBadgeButton, minWidth: 68, maxWidth: 140, wraps: true)
                                   ])),
                    ProfileFormRow(label: titleSettingsLabel,
                                   content: .wrappingLine([
                                       .fill(titleSettings, minWidth: 150, maxWidth: .greatestFiniteMagnitude, wraps: false),
                                       .fixed(customTitleHelp, width: 22, wraps: false)
                                   ]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(allowTitleSetting, trailing: []))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Command & Working Directory"),
                rows: [
                    ProfileFormRow(label: commandLabel,
                                   content: .wrappingLine([
                                       .natural(commandType, minWidth: 110, maxWidth: 200, wraps: true),
                                       .fill(customCommand, minWidth: 150, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .natural(configureSSHButton, minWidth: 86, maxWidth: 160, wraps: true)
                                   ]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(runCommandInLoginShell, trailing: [commandWarningImageView]),
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.runCommandInLoginShell.isHidden
                                   }),
                    ProfileFormRow(label: sendTextAtStartLabel,
                                   content: .single(sendTextAtStart, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(
                        label: directoryLabel,
                        content: .custom(hostedViews: [initialDirectoryType, customDirectory, editAdvancedConfigButton]) { x, availableWidth, y, _ in
                            let matrixSize = self.initialDirectoryType.fittingSize
                            let naturalMatrixW = (self.initialDirectoryType.cells.map { ceil($0.cellSize.width) }.max() ?? 160) + 8
                            let matrixW = min(availableWidth, max(132, naturalMatrixW))
                            let matrixH = max(84, ceil(matrixSize.height))
                            self.initialDirectoryType.frame = NSRect(x: x, y: y, width: matrixW, height: matrixH)

                            var bottomY = y + matrixH
                            let sideRowMaxW = (2..<self.initialDirectoryType.cells.count)
                                .map { ceil(self.initialDirectoryType.cells[$0].cellSize.width) }
                                .max() ?? matrixW
                            let sideAnchorW = min(matrixW, max(96, sideRowMaxW + 12))
                            let canPlaceSideBySide = (sideAnchorW + 12 + 150 <= availableWidth)
                            if canPlaceSideBySide {
                                let fieldX = x + sideAnchorW + 8
                                let fieldW = max(120, availableWidth - sideAnchorW - 8)
                                let rowCount = self.initialDirectoryType.numberOfRows
                                let dirRowY: CGFloat = rowCount > 2
                                    ? self.initialDirectoryType.cellFrame(atRow: 2, column: 0).midY - 11
                                    : 42
                                let advRowMidY: CGFloat = rowCount > 3
                                    ? self.initialDirectoryType.cellFrame(atRow: 3, column: 0).midY
                                    : matrixH - 11
                                if !self.customDirectory.isHidden {
                                    self.customDirectory.frame = NSRect(x: fieldX, y: y + max(0, round(dirRowY)), width: fieldW, height: 22)
                                }
                                if !self.editAdvancedConfigButton.isHidden {
                                    let btnSize = ProfileFormMeasurement.measureControl(self.editAdvancedConfigButton, maxWidth: fieldW)
                                    let btnY = y + max(0, round(advRowMidY - btnSize.height * 0.5))
                                    self.editAdvancedConfigButton.frame = NSRect(x: fieldX,
                                                                                 y: btnY,
                                                                                 width: btnSize.width,
                                                                                 height: btnSize.height)
                                    bottomY = max(bottomY, btnY + btnSize.height)
                                }
                            } else {
                                if !self.customDirectory.isHidden {
                                    bottomY += 6
                                    self.customDirectory.frame = NSRect(x: x, y: bottomY, width: availableWidth, height: 22)
                                    bottomY += 22
                                }
                                if !self.editAdvancedConfigButton.isHidden {
                                    bottomY += 6
                                    let btnSize = ProfileFormMeasurement.measureControl(self.editAdvancedConfigButton, maxWidth: availableWidth)
                                    self.editAdvancedConfigButton.frame = NSRect(x: x, y: bottomY, width: btnSize.width, height: btnSize.height)
                                    bottomY += btnSize.height
                                }
                            }
                            return bottomY - y
                        }
                    ),
                    ProfileFormRow(label: schemesLabel,
                                   content: .single(urlSchemes, fillsWidth: true, minWidth: 150, maxWidth: 360))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: view)
    }

    @objc func installEditSessionLayout() {
        profiles.useSettingsAppearance()
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Session"),
                rows: [
                    ProfileFormRow(label: editSessionNameLabel,
                                   content: .wrappingLine([
                                       .fill(profileNameFieldForEditCurrentSession, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: false),
                                       .fixed(locked, width: 22, wraps: false)
                                   ])),
                    ProfileFormRow(label: editSessionBadgeLabel,
                                   content: .single(badgeTextForEditCurrentSession, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: editSessionTitleLabel,
                                   content: .single(titleSettingsForEditCurrentSession, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: editSessionTabTitleLabel,
                                   content: .single(tabTitle, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: editSessionWindowTitleLabel,
                                   content: .single(windowTitle, fillsWidth: true, minWidth: 140, maxWidth: .greatestFiniteMagnitude))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Switch or Copy Profile"),
                rows: [
                    ProfileFormRow(
                        content: .custom(hostedViews: [profiles, copySettingsToProfile, copyProfileToSession]) { x, availableWidth, y, _ in
                            let listH: CGFloat = 210
                            self.profiles.frame = NSRect(x: x, y: y, width: availableWidth, height: listH)
                            var cursorY = y + listH + 10
                            let btn1 = ProfileFormMeasurement.measureControl(self.copySettingsToProfile, maxWidth: availableWidth)
                            let btn2 = ProfileFormMeasurement.measureControl(self.copyProfileToSession, maxWidth: availableWidth)
                            let gap: CGFloat = 8
                            if btn1.width + gap + btn2.width <= availableWidth {
                                let rowH = max(btn1.height, btn2.height)
                                self.copySettingsToProfile.frame = NSRect(x: x, y: cursorY, width: btn1.width, height: rowH)
                                self.copyProfileToSession.frame = NSRect(x: x + btn1.width + gap, y: cursorY, width: btn2.width, height: rowH)
                                cursorY += rowH
                            } else {
                                self.copySettingsToProfile.frame = NSRect(x: x, y: cursorY, width: btn1.width, height: btn1.height)
                                cursorY += btn1.height + 6
                                self.copyProfileToSession.frame = NSRect(x: x, y: cursorY, width: btn2.width, height: btn2.height)
                                cursorY += btn2.height
                            }
                            return cursorY - y
                        },
                        fullCardWidth: true
                    )
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Session Shortcut & Switching"),
                rows: [
                    ProfileFormRow(label: editSessionHotkeyLabel,
                                   content: .single(sessionHotkeyInputView, fillsWidth: false, minWidth: 180, maxWidth: 260)),
                    ProfileFormRow(content: .checkbox(preventAutomaticProfileSwitching, trailing: []))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: editCurrentSessionView)
    }
}

// MARK: - 2. Colors

extension ProfilesColorsPreferencesViewController {
    @objc func installProfileLayout() {
        let ansiRows: [(NSTextField, NSView, NSView)] = [
            (ansi0ColorLabel, ansi0Color, ansi8Color),
            (ansi1ColorLabel, ansi1Color, ansi9Color),
            (ansi2ColorLabel, ansi2Color, ansi10Color),
            (ansi3ColorLabel, ansi3Color, ansi11Color),
            (ansi4ColorLabel, ansi4Color, ansi12Color),
            (ansi5ColorLabel, ansi5Color, ansi13Color),
            (ansi6ColorLabel, ansi6Color, ansi14Color),
            (ansi7ColorLabel, ansi7Color, ansi15Color)
        ]

        var ansiHostedViews: [NSView] = [ansiNormalHeader, ansiBrightHeader, hueVisualization]
        for (lbl, norm, bright) in ansiRows {
            ProfileFormMeasurement.configureStaticLabel(lbl, alignment: .right)
            ansiHostedViews.append(contentsOf: [lbl, norm, bright])
        }
        ProfileFormMeasurement.configureStaticLabel(ansiNormalHeader, alignment: .center)
        ProfileFormMeasurement.configureStaticLabel(ansiBrightHeader, alignment: .center)

        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: modesSectionLabel, fallback: "Modes"),
                rows: [
                    ProfileFormRow(content: .checkbox(useSeparateColorsForLightAndDarkMode, trailing: [modeWarning]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(label: modeLabel,
                                   content: .single(mode, fillsWidth: false, minWidth: 160, maxWidth: 280),
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.mode.isHidden
                                   }),
                    ProfileFormRow(label: presetsLabel,
                                   content: .single(presetsPopupButton, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Basic Colors"),
                rows: [
                    ProfilePageHelpers.colorWellPairRow(rowLabel: foregroundColorLabel,
                                                        firstHeader: backgroundColorLabel,
                                                        firstWell: backgroundColor,
                                                        secondHeader: defaultsForegroundHeader,
                                                        secondWell: foregroundColor),
                    ProfilePageHelpers.colorWellPairRow(rowLabel: cursorColorLabel,
                                                        firstHeader: cursorBackgroundHeader,
                                                        firstWell: cursorColor,
                                                        secondHeader: cursorTextColorLabel,
                                                        secondWell: cursorTextColor,
                                                        suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(useSmartCursorColor, trailing: [])),
                    ProfileFormRow(label: imeCursorColorLabel,
                                   content: .single(imeCursorColor, fillsWidth: false, minWidth: 40, maxWidth: 44)),
                    ProfilePageHelpers.colorWellPairRow(rowLabel: selectionColorLabel,
                                                        firstHeader: selectionBackgroundHeader,
                                                        firstWell: selectionColor,
                                                        secondHeader: selectionForegroundHeader,
                                                        secondWell: selectedTextColor,
                                                        suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(selectedTextColorEnabledButton, trailing: [])),
                    ProfileFormRow(label: matchColorLabel,
                                   content: .single(matchColor, fillsWidth: false, minWidth: 40, maxWidth: 44)),
                    ProfileFormRow(label: linkColorLabel,
                                   content: .single(linkColor, fillsWidth: false, minWidth: 40, maxWidth: 44)),
                    ProfileFormRow(label: boldColorLabel,
                                   content: .wrappingLine([
                                       .fixed(boldColor, width: 44, wraps: false),
                                       .natural(useBrightBold, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(brightenBoldText, trailing: [])),
                    ProfileFormRow(label: underlineColorLabel,
                                   content: .wrappingLine([
                                       .fixed(underlineColor, width: 44, wraps: false),
                                       .natural(useUnderlineColor, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: cursorGuideLabel,
                                   content: .wrappingLine([
                                       .fixed(guideColor, width: 44, wraps: false),
                                       .natural(useGuide, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: badgeColorLabel,
                                   content: .single(badgeColor, fillsWidth: false, minWidth: 40, maxWidth: 44))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: ansiColorsSectionLabel, fallback: "ANSI Colors"),
                rows: [
                    ProfileFormRow(
                        content: .custom(hostedViews: ansiHostedViews) { x, availableWidth, y, _ in
                            let nameColW: CGFloat = 78
                            let wellW: CGFloat = 44
                            let wellH: CGFloat = 22
                            let colGap: CGFloat = 12
                            let normalX = x + nameColW + 10
                            let brightX = normalX + wellW + colGap
                            let gridWidth = (brightX - x) + wellW
                            let hueW = min(203, max(168, availableWidth - gridWidth - 28))
                            let sideBySide = availableWidth >= gridWidth + 24 + 168

                            let headerY = y
                            self.ansiNormalHeader.frame = NSRect(x: normalX, y: headerY, width: wellW + 8, height: 15)
                            self.ansiBrightHeader.frame = NSRect(x: brightX, y: headerY, width: wellW + 8, height: 15)

                            var rowY = headerY + 20
                            let rowStep: CGFloat = 26
                            for (lbl, norm, bright) in ansiRows {
                                lbl.frame = NSRect(x: x, y: rowY + 3, width: nameColW, height: 16)
                                norm.frame = NSRect(x: normalX + 4, y: rowY, width: wellW, height: wellH)
                                bright.frame = NSRect(x: brightX + 4, y: rowY, width: wellW, height: wellH)
                                rowY += rowStep
                            }
                            let gridBottomY = rowY - 4

                            if sideBySide {
                                let hueSize = min(203, hueW)
                                let hueX = x + gridWidth + floor((availableWidth - gridWidth - hueSize) / 2.0)
                                let hueY = y + max(0, floor(((gridBottomY - y) - hueSize) / 2.0))
                                self.hueVisualization.frame = NSRect(x: hueX, y: hueY, width: hueSize, height: hueSize)
                                return max(gridBottomY, hueY + hueSize) - y
                            } else {
                                let hueSize = min(203, max(140, availableWidth - 24))
                                let hueX = x + floor((availableWidth - hueSize) / 2.0)
                                let hueY = gridBottomY + 14
                                self.hueVisualization.frame = NSRect(x: hueX, y: hueY, width: hueSize, height: hueSize)
                                return hueY + hueSize - y
                            }
                        },
                        fullCardWidth: true
                    ),
                    ProfileFormRow(content: .checkbox(harmonize256, trailing: []))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Contrast & Alpha"),
                rows: [
                    ProfileFormRow(
                        label: minimumContrastLabel,
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: minimumContrast),
                                         minLabel: nil,
                                         maxLabel: nil,
                                         trailingNote: nil,
                                         maxWidth: 340),
                        helperViews: [bwWarning1, bwWarning2]
                    ),
                    ProfileFormRow(
                        label: faintTextAlphaLabel,
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: faintTextAlpha),
                                         minLabel: faintTransparentLabel,
                                         maxLabel: faintOpaqueLabel,
                                         trailingNote: nil,
                                         maxWidth: 340)
                    ),
                    ProfileFormRow(
                        label: cursorBoostLabel,
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: cursorBoost),
                                         minLabel: nil,
                                         maxLabel: nil,
                                         trailingNote: nil,
                                         maxWidth: 340)
                    )
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Tab & Pane"),
                rows: [
                    ProfileFormRow(label: tabColorLabel,
                                   content: .wrappingLine([
                                       .fixed(tabColor, width: 44, wraps: false),
                                       .natural(useTabColor, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: paneColorLabel,
                                   content: .wrappingLine([
                                       .fixed(activePaneBorderColor, width: 44, wraps: false),
                                       .natural(useActivePaneBorder, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ]))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: view)
    }
}

// MARK: - 3. Text

extension ProfilesTextPreferencesViewController {
    @objc func installProfileLayout() {
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Cursor"),
                rows: [
                    ProfileFormRow(label: cursorTypeLabel,
                                   content: .single(cursorType, fillsWidth: false, minWidth: 140, maxWidth: 260),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(blinkingCursor, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(cursorSmoothBlink, trailing: [cursorSmoothBlinkConfigureButton]),
                                   indent: 20,
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(cursorSmoothSlide, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(shadow, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(hideOnLostFocus, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(animateMovement, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(animateMovementOnlyInInteractiveApps, trailing: []), indent: 20)
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Typography"),
                rows: [
                    ProfileFormRow(label: asciiFontLabel,
                                   content: .fontPicker(asciiFontPicker),
                                   fullCardWidth: true,
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(asciiAntiAliased, trailing: [normalFontWantsAntialiasing]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(asciiLigatures, trailing: [ligatureWarning])),
                    ProfileFormRow(label: thinStrokesLabel,
                                   content: .single(thinStrokes, fillsWidth: true, minWidth: 160, maxWidth: 320))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: nonAsciiFontLabel, fallback: "Non-ASCII Font"),
                rows: [
                    ProfileFormRow(label: nonAsciiFontLabel,
                                   content: .checkbox(useNonAsciiFont, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .fontPicker(nonASCIIFontPicker),
                                   fullCardWidth: true,
                                   suppressSeparatorAfter: true,
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.nonAsciiFontView.isHidden
                                   }),
                    ProfileFormRow(content: .checkbox(nonasciiAntiAliased, trailing: [nonasciiFontWantsAntialiasing]),
                                   suppressSeparatorAfter: true,
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.nonAsciiFontView.isHidden
                                   }),
                    ProfileFormRow(content: .checkbox(nonAsciiLigatures, trailing: [ligatureWarningNonAscii]),
                                   suppressSeparatorAfter: true,
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.nonAsciiFontView.isHidden
                                   }),
                    ProfileFormRow(content: .wrappingLine([
                                       .natural(manageCharacterFontsButton, minWidth: 120, maxWidth: 280, wraps: true)
                                   ]),
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.nonAsciiFontView.isHidden
                                   })
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: textRenderingLabel, fallback: "Text Rendering"),
                rows: [
                    ProfileFormRow(label: textRenderingLabel,
                                   content: .checkbox(useBoldFont, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(blinkAllowed, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(useItalicFont, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(powerline, trailing: [])),
                    ProfileFormRow(label: unicodeLabel,
                                   content: .checkbox(unicodeVersion9, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(ambiguousIsDoubleWidth, trailing: [])),
                    ProfileFormRow(label: normalizationLabel,
                                   content: .single(normalization, fillsWidth: true, minWidth: 160, maxWidth: 320))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections,
                                           on: view,
                                           stateContainersToKeep: [nonAsciiFontView])
    }
}

// MARK: - 4. Window

extension ProfilesWindowPreferencesViewController {
    @objc func installProfileLayout() {
        let sizeHostedViews: [NSView] = [
            columnsField, percentageWidthField, columnsUnitsButton, widthLabel,
            byLabel, rowsField, percentageHeightField, rowsUnitsButton, heightLabel
        ]

        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: transparencyLabel, fallback: "Transparency"),
                rows: [
                    ProfileFormRow(
                        label: transparencyLabel,
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: transparency),
                                         minLabel: transparencyMinLabel,
                                         maxLabel: transparencyMaxLabel,
                                         trailingNote: transparencyOverrideNotice,
                                         maxWidth: 340),
                        suppressSeparatorAfter: true
                    ),
                    ProfileFormRow(content: .checkbox(transparencyAffectsOnlyDefaultBackgroundColor, trailing: [])),
                    ProfileFormRow(label: blurLabel,
                                   content: .checkbox(useBlur, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: blurRadius),
                                         minLabel: blurMinLabel,
                                         maxLabel: blurMaxLabel,
                                         trailingNote: largeBlurRadiusWarning,
                                         maxWidth: 340)
                    )
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: backgroundImageSectionLabel, fallback: "Background Image"),
                rows: [
                    ProfileFormRow(content: .checkbox(useBackgroundImage, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(label: backgroundImageSourceLabel,
                                   content: .single(backgroundImageSourceMode, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: backgroundImageLabel,
                                   content: .wrappingLine([
                                       .fill(backgroundImageTextField, minWidth: 160, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .fill(backgroundImageFolderTextField, minWidth: 160, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: backgroundImageFolderIntervalLabel,
                                   content: .wrappingLine([
                                       .fixed(backgroundImageFolderIntervalField, width: 76, wraps: false),
                                       .natural(rotationIntervalUnitsLabel, minWidth: 40, maxWidth: 160, wraps: false)
                                   ]),
                                   isVisible: { [weak self] in
                                       guard let self else { return false }
                                       return !self.backgroundImageFolderIntervalField.isHidden
                                   }),
                    ProfileFormRow(
                        content: .custom(hostedViews: [backgroundImagePreview]) { x, availableWidth, y, _ in
                            let h: CGFloat = 76
                            let w = min(availableWidth, 360)
                            self.backgroundImagePreview.frame = NSRect(x: x, y: y, width: w, height: h)
                            return h
                        },
                        isVisible: { [weak self] in
                            guard let self else { return false }
                            return !self.backgroundImagePreview.isHidden
                        }
                    ),
                    ProfileFormRow(label: backgroundImageScalingLabel,
                                   content: .single(backgroundImageMode, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(
                        label: backgroundImageBlendingLabel,
                        content: .slider(container: ProfilePageHelpers.sliderContainer(for: blendAmount),
                                         minLabel: blendBackgroundColorLabel,
                                         maxLabel: blendImageLabel,
                                         trailingNote: nil,
                                         maxWidth: 340)
                    )
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: newWindowsSizeLabel, fallback: "New Windows"),
                backingEnclosure: settingsForNewWindows,
                rows: [
                    ProfileFormRow(label: newTabsLabel,
                                   content: .checkbox(useCustomTabTitle, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .single(customTabTitle, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(
                        label: newWindowsSizeLabel,
                        content: .custom(hostedViews: sizeHostedViews) { x, availableWidth, y, _ in
                            var flowViews: [NSView] = []
                            if !self.columnsField.isHidden { flowViews.append(self.columnsField) }
                            if !self.percentageWidthField.isHidden { flowViews.append(self.percentageWidthField) }
                            if !self.columnsUnitsButton.isHidden {
                                flowViews.append(self.columnsUnitsButton)
                            } else if !self.widthLabel.isHidden {
                                ProfileFormMeasurement.configureStaticLabel(self.widthLabel, alignment: .left)
                                flowViews.append(self.widthLabel)
                            }
                            if !self.byLabel.isHidden {
                                ProfileFormMeasurement.configureStaticLabel(self.byLabel, alignment: .left)
                                flowViews.append(self.byLabel)
                            }
                            if !self.rowsField.isHidden { flowViews.append(self.rowsField) }
                            if !self.percentageHeightField.isHidden { flowViews.append(self.percentageHeightField) }
                            if !self.rowsUnitsButton.isHidden {
                                flowViews.append(self.rowsUnitsButton)
                            } else if !self.heightLabel.isHidden {
                                ProfileFormMeasurement.configureStaticLabel(self.heightLabel, alignment: .left)
                                flowViews.append(self.heightLabel)
                            }

                            let gap: CGFloat = 6
                            var cursorX = x
                            var lineY = y
                            var lineH: CGFloat = 24
                            for v in flowViews {
                                let w: CGFloat
                                let h: CGFloat
                                if v is NSTextField && (v as? NSTextField)?.isEditable == true {
                                    w = 54
                                    h = 22
                                } else if let popup = v as? NSPopUpButton {
                                    let selectedTitle = popup.selectedItem?.title ?? popup.title
                                    let titleW = ceil((selectedTitle as NSString).size(withAttributes: [
                                        .font: popup.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                                    ]).width)
                                    w = min(availableWidth, max(68, min(ceil(popup.fittingSize.width), titleW + 40)))
                                    h = 24
                                } else {
                                    let fit = v.fittingSize
                                    w = min(availableWidth, max(16, ceil(fit.width)))
                                    h = max(16, ceil(fit.height))
                                }
                                if cursorX > x && cursorX + w > x + availableWidth {
                                    lineY += lineH + 6
                                    cursorX = x
                                    lineH = h
                                } else {
                                    lineH = max(lineH, h)
                                }
                                let itemY = lineY + floor((lineH - h) / 2.0)
                                v.frame = NSRect(x: cursorX, y: itemY, width: w, height: h)
                                cursorX += w + gap
                            }
                            return lineY + lineH - y
                        }
                    ),
                    ProfileFormRow(label: windowStyleLabel,
                                   content: .single(windowStyle, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: screenLabel,
                                   content: .single(screen, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: spaceLabel,
                                   content: .single(space, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(content: .checkbox(hideAfterOpening, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(lockSizeAutomatically, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(openToolbelt, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(preventTab, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(initialUseTransparency, trailing: [])),
                    ProfileFormRow(content: .checkbox(useCustomWindowTitle, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .single(customWindowTitle, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections,
                                           on: view,
                                           stateContainersToKeep: [settingsForNewWindows])
    }
}

// MARK: - 5. Terminal

extension ProfilesTerminalPreferencesViewController {
    @objc func installProfileLayout() {
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: historySectionLabel, fallback: "History"),
                rows: [
                    ProfileFormRow(label: numScrollbackLinesLabel,
                                   content: .wrappingLine([
                                       .fixed(numScrollbackLines, width: 112, wraps: false),
                                       .natural(unlimitedScrollback, minWidth: 110, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(scrollbackWithStatusBar, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(scrollbackInAlternateScreen, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(dragToScrollInAlternateScreenModeDisabled, trailing: []))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: emulationSectionLabel, fallback: "Emulation features"),
                rows: [
                    ProfileFormRow(label: characterEncodingLabel,
                                   content: .single(characterEncoding, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: terminalTypeLabel,
                                   content: .single(terminalType, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: answerBackStringLabel,
                                   content: .single(answerBackString, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(content: .checkbox(allowTitleReporting, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(allowCursorBlinkControlSequence, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(allowPasteBracketing, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(disablePrinting, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(disableAltScreen, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(disableWindowResizing, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(disableUnfocusedWindowResizing, trailing: []), indent: 20)
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: mouseReportingSectionLabel, fallback: "Mouse reporting"),
                rows: [
                    ProfileFormRow(content: .checkbox(xtermMouseReporting, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(xtermMouseReportingAllowMouseWheel, trailing: []), indent: 20, suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(xtermMouseReportingAllowClicksAndDrags, trailing: []), indent: 20, suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(restrictMouseReportingToAlternateScreenMode, trailing: []), indent: 20),
                    ProfileFormRow(content: .checkbox(allowAlternateMouseScroll, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(automaticallyEnableAlternatemouseScroll, trailing: []), indent: 20, suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(restrictAlternateMouseScrollToVertical, trailing: []), indent: 20)
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: notificationsSectionLabel, fallback: "Notifications"),
                rows: [
                    ProfileFormRow(label: bellSectionLabel,
                                   content: .checkbox(flashingBell, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(bellIconInTabs, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(silenceBell, trailing: [])),
                    ProfileFormRow(label: notificationsSectionLabel,
                                   content: .checkbox(postNotifications, trailing: [filterAlertsButton]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: environmentSectionLabel, fallback: "Environment"),
                rows: [
                    ProfileFormRow(label: environmentSectionLabel,
                                   content: .wrappingLine([
                                       .fill(localeVars, minWidth: 160, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .natural(changeLocale, minWidth: 78, maxWidth: 140, wraps: true)
                                   ]),
                                   helperViews: [localeName]),
                    ProfileFormRow(label: terminalMetadataSectionLabel,
                                   content: .checkbox(forceCommandPromptToFirstColumn, trailing: [shellIntegrationRequiredButton]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(showOffscreenCommandLine, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(showOffscreenCommandLineForCurrentCommand, trailing: []), indent: 20, suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(promptPathClickOpensNavigator, trailing: [])),
                    ProfileFormRow(label: tmuxIntegrationSectionLabel,
                                   content: .checkbox(tmuxNewline, trailing: []))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: view)
    }
}

// MARK: - 6. Session

extension ProfilesSessionPreferencesViewController {
    @objc func installProfileLayout() {
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: closingSectionLabel, fallback: "Closing"),
                rows: [
                    ProfileFormRow(content: .checkbox(warnAboutShortLivedSessions, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .wrappingLine([
                        .natural(undoRevivePrefixLabel, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true),
                        .fixed(undoTimeout, width: 64, wraps: false),
                        .natural(undoSecondsLabel, minWidth: 40, maxWidth: 120, wraps: false)
                    ])),
                    ProfileFormRow(label: afterSessionEndsLabel,
                                   content: .single(onEndAction, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: promptBeforeClosingLabel,
                                   content: .single(promptBeforeClosing, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfilePageHelpers.tableWithAddRemoveRow(
                        scrollView: ProfilePageHelpers.embeddedScrollView(for: jobsTable),
                        addButton: addJob,
                        removeButton: removeJob,
                        tableHeight: 118
                    )
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: loggingSectionLabel, fallback: "Logging"),
                rows: [
                    ProfileFormRow(content: .checkbox(autoLog, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(label: logFormatLabel,
                                   content: .single(loggingStyle, fillsWidth: false, minWidth: 130, maxWidth: 240)),
                    ProfileFormRow(label: logFolderLabel,
                                   content: .wrappingLine([
                                       .fill(logDir, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .fixed(logDirWarning, width: 18, wraps: false),
                                       .natural(changeLogDir, minWidth: 74, maxWidth: 130, wraps: true)
                                   ])),
                    ProfileFormRow(label: logFilenameLabel,
                                   content: .single(logFilenameFormat, fillsWidth: true, minWidth: 150, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: archivingSectionLabel,
                                   content: .checkbox(archive, trailing: [archivingHelpButton]),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(label: archiveFolderLabel,
                                   content: .wrappingLine([
                                       .fill(archiveDir, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true),
                                       .fixed(archiveDirWarning, width: 18, wraps: false),
                                       .natural(changeArchiveDir, minWidth: 74, maxWidth: 130, wraps: true)
                                   ]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: statusBarSectionLabel, fallback: "Status Bar"),
                rows: [
                    ProfileFormRow(label: showTimestampsLabel,
                                   content: .checkbox(timestampsEnabled, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .single(showTimestampsPopup, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: statusBarSectionLabel,
                                   content: .checkbox(statusBarEnabled, trailing: [configureStatusBar]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: progressBarsSectionLabel, fallback: "Progress Bars"),
                rows: [
                    ProfileFormRow(content: .checkbox(enableProgressBars, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(label: progressBarHeightLabel,
                                   content: .wrappingLine([
                                       .fixed(progressBarHeight, width: 54, wraps: false),
                                       .fixed(progressBarHeightStepper, width: 19, wraps: false)
                                   ])),
                    ProfileFormRow(label: progressBarColorSchemeLabel,
                                   content: .single(progressBarColorScheme, fillsWidth: true, minWidth: 160, maxWidth: .greatestFiniteMagnitude)),
                    ProfileFormRow(label: passwordManagerLabel,
                                   content: .checkbox(openPasswordManagerAutomatically, trailing: []))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: miscSectionLabel, fallback: "Miscellaneous"),
                rows: [
                    ProfileFormRow(content: .wrappingLine([
                        .natural(sendCodeWhenIdle, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true),
                        .fixed(idleCode, width: 58, wraps: false),
                        .natural(idleEveryLabel, minWidth: 28, maxWidth: 80, wraps: false),
                        .fixed(idlePeriod, width: 58, wraps: false),
                        .natural(idleSecondsLabel, minWidth: 36, maxWidth: 80, wraps: false)
                    ])),
                    ProfileFormRow(content: .checkbox(reduceFlicker, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(defaultPaneLocked, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(bufferByDefault, trailing: [bufferHelpButton]),
                                   helperViews: [bufferWarning])
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: view)
    }
}

// MARK: - 7. Keys (Flattened into a single scrollable form)

extension ProfilesKeysPreferencesViewController {
    @objc func installProfileLayout() {
        let placeholder = keyMappingViewController.placeholderView
        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: keyReportingLabel, fallback: "Key reporting"),
                rows: [
                    ProfileFormRow(content: .checkbox(applicationKeypadAllowed, trailing: []), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(useLibTickit, trailing: [csiuHelpButton]), suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(allowModifyOtherKeys, trailing: [])),
                    ProfileFormRow(label: keyBehaviorLabel,
                                   content: .checkbox(movementKeysScrollOutsideInteractiveApps, trailing: []),
                                   suppressSeparatorAfter: true),
                    ProfileFormRow(content: .checkbox(treatOptionAsAlt, trailing: [optionAsMetaHelpButton]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Modifier Keys"),
                rows: [
                    ProfileFormRow(label: optionKeySendsLabel,
                                   content: .wrappingLine([
                                       .fill(leftOptionKeyButton, minWidth: 160, maxWidth: 260, wraps: true),
                                       .natural(leftOptionKeyChangeable, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: rightOptionKeySendsLabel,
                                   content: .wrappingLine([
                                       .fill(rightOptionKeyButton, minWidth: 160, maxWidth: 260, wraps: true),
                                       .natural(rightOptionKeyChangeable, minWidth: 120, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: leftControlLabel,
                                   content: .wrappingLine([
                                       .fill(leftControlButton, minWidth: 160, maxWidth: 260, wraps: false),
                                       .fixed(controlRemapHelpButton, width: 22, wraps: false)
                                   ])),
                    ProfileFormRow(label: rightControlLabel,
                                   content: .single(rightControlButton, fillsWidth: true, minWidth: 160, maxWidth: 260)),
                    ProfileFormRow(label: leftCommandLabel,
                                   content: .single(leftCommandButton, fillsWidth: true, minWidth: 160, maxWidth: 260)),
                    ProfileFormRow(label: rightCommandLabel,
                                   content: .single(rightCommandButton, fillsWidth: true, minWidth: 160, maxWidth: 260)),
                    ProfileFormRow(label: functionLabel,
                                   content: .single(functionButton, fillsWidth: true, minWidth: 160, maxWidth: 260))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: hotkeyWindowLabel, fallback: "Hotkey window"),
                backingEnclosure: hotKeyContainerView,
                rows: [
                    ProfileFormRow(content: .checkbox(hasHotkey, trailing: [configureHotKey]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Key Bindings"),
                rows: [
                    ProfileFormRow(
                        content: .custom(hostedViews: placeholder.map { [$0] } ?? []) { x, availableWidth, y, _ in
                            guard let placeholder else { return 0 }
                            let height = ProfilePageHelpers.naturalTableContainerHeight(
                                in: placeholder,
                                minHeight: 240,
                                maxHeight: 480,
                                extraChrome: 46
                            )
                            placeholder.frame = NSRect(x: x, y: y, width: availableWidth, height: height)
                            return height
                        },
                        fullCardWidth: true
                    ),
                    ProfileFormRow(content: .wrappingLine([
                        .natural(deleteSendsCtrlHButton, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true),
                        .natural(repairKeyMappingsButton, minWidth: 120, maxWidth: 260, wraps: true)
                    ]))
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections,
                                           on: view,
                                           stateContainersToKeep: [hotKeyContainerView])
    }
}

// MARK: - 8. Advanced

extension ProfilesAdvancedPreferencesViewController {
    @objc func installProfileLayout() {
        var semanticItems: [ProfileFormInlineItem] = []
        var semanticHelpers: [NSView] = [disabledTip]
        if let semController = semanticHistoryPrefController {
            semanticItems = [
                .natural(semController.actionPopup, minWidth: 140, maxWidth: 240, wraps: true),
                .fill(semController.textField, minWidth: 150, maxWidth: .greatestFiniteMagnitude, wraps: true),
                .fill(semController.editorsPopup, minWidth: 150, maxWidth: .greatestFiniteMagnitude, wraps: true),
                .fixed(semanticHistoryHelp, width: 22, wraps: false)
            ]
            semanticHelpers.insert(semController.caveatField, at: 0)
        } else {
            semanticItems = [
                .fixed(semanticHistoryHelp, width: 22, wraps: false)
            ]
        }

        let sections: [ProfileSectionCard] = [
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Triggers & Smart Selection"),
                rows: [
                    ProfileFormRow(label: triggersLabel,
                                   content: .wrappingLine([
                                       .natural(triggersButton, minWidth: 72, maxWidth: 150, wraps: false),
                                       .fixed(triggersHelp, width: 22, wraps: false),
                                       .natural(enableTriggersInInteractiveApps, minWidth: 140, maxWidth: .greatestFiniteMagnitude, wraps: true)
                                   ])),
                    ProfileFormRow(label: smartSelectionLabel,
                                   content: .wrappingLine([
                                       .natural(smartSelectionButton, minWidth: 72, maxWidth: 150, wraps: false),
                                       .fixed(smartSelectionHelp, width: 22, wraps: false)
                                   ]))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.sectionTitle(from: boundHostLabel as? NSTextField,
                                                       fallback: "Automatic Profile Switching"),
                headerAccessory: boundHostHelp,
                rows: [
                    ProfilePageHelpers.tableWithAddRemoveRow(
                        scrollView: ProfilePageHelpers.embeddedScrollView(for: boundHostsTableView),
                        addButton: addBoundHost,
                        removeButton: removeBoundHost,
                        trailingViews: [boundHostShellIntegrationWarning],
                        tableHeight: 132
                    ),
                    ProfileFormRow(content: .checkbox(enableAPSLogging, trailing: []))
                ]
            ),
            ProfileSectionCard(
                title: ProfilePageHelpers.localizedSection("Snippets & Semantic History"),
                rows: [
                    ProfileFormRow(label: snippetsFilterLabel,
                                   content: .wrappingLine([
                                       .fill(snippetsFilter, minWidth: 150, maxWidth: .greatestFiniteMagnitude, wraps: false),
                                       .fixed(snippetsFilterHelp, width: 22, wraps: false)
                                   ])),
                    ProfileFormRow(label: semanticHistoryLabel,
                                   content: .wrappingLine(semanticItems),
                                   helperViews: semanticHelpers)
                ]
            )
        ]

        ProfilePageHelpers.installDocument(sections, on: view)
    }
}


/// Uses the same responsive SwiftUI form for the global keyboard preferences.
@objc(iTermKeyboardFormLayout)
final class KeyboardFormLayout: NSObject {
    @objc static func install(in tabs: NSTabView, controls: [String: NSView]) {
        func control<T: NSView>(_ key: String) -> T {
            guard let view = controls[key] as? T else {
                it_fatalError("Missing keyboard editor: \(key)")
            }
            return view
        }
        func field(_ title: String) -> NSTextField {
            NSTextField(labelWithString: NSLocalizedString(title, comment: "Keyboard form label"))
        }
        func single(_ key: String, label: String? = nil, fillsWidth: Bool = true, maxWidth: CGFloat = 320) -> ProfileFormRow {
            ProfileFormRow(label: label.map { control($0) },
                           content: .single(control(key), fillsWidth: fillsWidth, minWidth: 60, maxWidth: maxWidth))
        }
        func button(_ key: String, label: NSTextField? = nil) -> ProfileFormRow {
            ProfileFormRow(label: label,
                           content: .single(control(key), fillsWidth: false, minWidth: 60, maxWidth: 320))
        }
        func checkbox(_ key: String, trailing: [NSView] = [], indent: CGFloat = 0, suppressSeparatorAfter: Bool = false) -> ProfileFormRow {
            ProfileFormRow(content: .checkbox(control(key), trailing: trailing),
                           indent: indent,
                           suppressSeparatorAfter: suppressSeparatorAfter)
        }
        let known = Set(controls.values.map(ObjectIdentifier.init))
        func unownedHelpButtons(in root: NSView?) -> [NSButton] {
            guard let root, !known.contains(ObjectIdentifier(root)) else { return [] }
            if let btn = root as? NSButton, btn.bezelStyle == .helpButton || btn is PopoverHelpButton {
                return [btn]
            }
            return root.subviews.flatMap { unownedHelpButtons(in: $0) }
        }
        func unownedNotes(in root: NSView?) -> [NSTextField] {
            guard let root, !known.contains(ObjectIdentifier(root)) else { return [] }
            if let lbl = root as? NSTextField, !lbl.isEditable, lbl.stringValue.count > 40 {
                return [lbl]
            }
            return root.subviews.flatMap { unownedNotes(in: $0) }
        }

        let mapping: NSView = control("mapping")
        let global: NSView = control("global")
        let globalViews = global is NSButton ? [global] : global.subviews
        let navHelp = tabs.tabViewItems.indices.contains(1) ? unownedHelpButtons(in: tabs.tabViewItems[1].view) : []
        let hotkeyNotes = tabs.tabViewItems.indices.contains(2) ? unownedNotes(in: tabs.tabViewItems[2].view) : []
        let remapHelp = tabs.tabViewItems.indices.contains(3) ? unownedHelpButtons(in: tabs.tabViewItems[3].view) : []
        let systemNotes = tabs.tabViewItems.indices.contains(4) ? unownedNotes(in: tabs.tabViewItems[4].view) : []

        var claimed = known
        navHelp.forEach { claimed.insert(ObjectIdentifier($0)) }
        hotkeyNotes.forEach { claimed.insert(ObjectIdentifier($0)) }
        remapHelp.forEach { claimed.insert(ObjectIdentifier($0)) }
        systemNotes.forEach { claimed.insert(ObjectIdentifier($0)) }

        var groups: [[ProfileFormRow]] = [
            [ProfileFormRow(content: .custom(hostedViews: [mapping]) { x, width, y, _ in
                let height = ProfilePageHelpers.naturalTableContainerHeight(in: mapping,
                    minHeight: 240, maxHeight: 400, extraChrome: 40)
                mapping.frame = NSRect(x: x, y: y, width: width, height: height)
                return height
            }, fullCardWidth: true),
             checkbox("physical"),
             button("repair"),
             ProfileFormRow(label: field("Leader:"), content: .wrappingLine([
                .fill(control("leader"), minWidth: 120, maxWidth: 260),
                .fixed(control("leaderHelp"), width: 22)]))],
            [single("window", label: "windowLabel", fillsWidth: false, maxWidth: 260),
             single("tab", label: "tabLabel", fillsWidth: false, maxWidth: 260),
             single("pane", label: "paneLabel", fillsWidth: false, maxWidth: 260),
             checkbox("emulate", trailing: navHelp)],
            [checkbox("hotkeyEnabled", suppressSeparatorAfter: true),
             ProfileFormRow(label: control("hotkeyLabel"),
                            content: .single(control("hotkey"), fillsWidth: true, minWidth: 120, maxWidth: 280),
                            helperViews: [control("warning")]),
             ProfileFormRow(label: field("Open Quickly hotkey:"),
                            content: .single(control("quickly"), fillsWidth: true, minWidth: 120, maxWidth: 280),
                            helperViews: hotkeyNotes),
             button("configure", label: field("Hotkey Window:"))],
            [single("leftControl", label: "leftControlLabel", fillsWidth: false, maxWidth: 260),
             single("rightControl", label: "rightControlLabel", fillsWidth: false, maxWidth: 260),
             single("leftOption", label: "leftOptionLabel", fillsWidth: false, maxWidth: 260),
             single("rightOption", label: "rightOptionLabel", fillsWidth: false, maxWidth: 260),
             single("leftCommand", label: "leftCommandLabel", fillsWidth: false, maxWidth: 260),
             single("rightCommand", label: "rightCommandLabel", fillsWidth: false, maxWidth: 260),
             single("function", label: "functionLabel", fillsWidth: false, maxWidth: 260),
             ProfileFormRow(content: .wrappingLine(globalViews.map { .natural($0) } + remapHelp.map { .fixed($0, width: 22) }),
                            suppressSeparatorAfter: true),
             button("reset")],
            [ProfileFormRow(content: .wrappingLine([
                .natural(control("force")),
                .natural(control("locale"), minWidth: 140, maxWidth: 280)
             ]), helperViews: systemNotes, suppressSeparatorAfter: true),
             checkbox("once", indent: 20),
             checkbox("symbolic")]
        ]
        // Preserve any remaining help actions or explanatory text that have no controller outlet.
        func supplementalRows(in root: NSView) -> [ProfileFormRow] {
            if claimed.contains(ObjectIdentifier(root)) { return [] }
            if let btn = root as? NSButton,
               btn.bezelStyle == .helpButton || btn is PopoverHelpButton {
                return [ProfileFormRow(content: .single(btn, fillsWidth: false, minWidth: 22, maxWidth: 22))]
            }
            if let label = root as? NSTextField, !label.isEditable, label.stringValue.count > 60 {
                return [ProfileFormRow(content: .note(label))]
            }
            return root.subviews.flatMap { supplementalRows(in: $0) }
        }
        for (index, item) in tabs.tabViewItems.enumerated() {
            if let root = item.view, groups.indices.contains(index) {
                groups[index].append(contentsOf: supplementalRows(in: root))
            }
        }
        it_assert(tabs.numberOfTabViewItems == groups.count, "Keyboard form categories must match their controllers")
        for (item, rows) in zip(tabs.tabViewItems, groups) {
            guard let root = item.view else { continue }
            ProfilePageHelpers.installDocument([ProfileSectionCard(title: nil, rows: rows)], on: root)
        }
    }
}
