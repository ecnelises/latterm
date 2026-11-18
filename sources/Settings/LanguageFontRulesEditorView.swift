//
//  LanguageFontRulesEditorView.swift
//  iTerm2SharedARC
//
//  Inline per-language / per-script font override list for Settings > Profiles > Appearance.
//

import AppKit

@objc(iTermLanguageFontRulesEditorView)
final class LanguageFontRulesEditorView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }

    @objc var onConfigChanged: ((String?) -> Void)?
    @objc var onLayoutInvalidated: (() -> Void)?

    private(set) var config = FontTable.Config(entries: [])
    private let descriptionLabel: NSTextField
    private let emptyStateLabel: NSTextField
    private let addPullDownButton: NSPopUpButton
    private let customRangesBadgeLabel: NSTextField
    private var rowViews: [RuleRowView] = []

    private static let cachedAvailableFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }()

    @objc init() {
        descriptionLabel = ProfileFormMeasurement.makeCaptionLabel(
            NSLocalizedString("Assign dedicated fonts to languages or symbol sets. Earlier rules take priority when scripts overlap.",
                              comment: "Language font rules description")
        )
        emptyStateLabel = ProfileFormMeasurement.makeCaptionLabel(
            NSLocalizedString("No language-specific overrides configured.",
                              comment: "Language font rules empty state")
        )
        addPullDownButton = NSPopUpButton(frame: .zero, pullsDown: true)
        customRangesBadgeLabel = ProfileFormMeasurement.makeCaptionLabel("")
        super.init(frame: .zero)
        autoresizesSubviews = false
        configureControls()
        rebuildRowViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    private func configureControls() {
        addSubview(descriptionLabel)
        addSubview(emptyStateLabel)

        addPullDownButton.bezelStyle = .rounded
        addPullDownButton.controlSize = .regular
        addPullDownButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        addPullDownButton.target = self
        addPullDownButton.action = #selector(addLanguageRuleFromMenu(_:))
        addPullDownButton.setAccessibilityIdentifier("AddLanguageFontRuleButton")
        addSubview(addPullDownButton)

        customRangesBadgeLabel.isHidden = true
        addSubview(customRangesBadgeLabel)
        rebuildAddMenu()
    }

    private func rebuildAddMenu() {
        let menu = NSMenu()
        let titleItem = NSMenuItem(
            title: NSLocalizedString("Add Language Font…", comment: "Language font add menu"),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(titleItem)

        let existingScripts = Set(config.languageRules.map(\.script))
        for (index, script) in FontLanguageScript.allCases.enumerated() {
            let item = NSMenuItem(
                title: script.localizedTitle,
                action: #selector(addLanguageRuleMenuItem(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            item.isEnabled = !existingScripts.contains(script)
            menu.addItem(item)
        }
        addPullDownButton.menu = menu
    }

    @objc(loadConfigString:)
    func load(configString: String?) {
        let parsed = FontTable.Config(string: configString ?? "") ?? FontTable.Config(entries: [])
        guard parsed != config || (rowViews.isEmpty && !parsed.languageRules.isEmpty) else {
            updateCustomRangesBadge()
            return
        }
        config = parsed
        rebuildRowViews()
        rebuildAddMenu()
        updateCustomRangesBadge()
        needsLayout = true
    }

    @objc var configStringValue: String? {
        config.isEmpty ? nil : config.stringValue
    }

    private func updateCustomRangesBadge() {
        let count = config.entries.count
        if count > 0 {
            customRangesBadgeLabel.stringValue = String(
                format: NSLocalizedString("%d custom Unicode range rules active", comment: "Custom Unicode range count"),
                count
            )
            customRangesBadgeLabel.isHidden = false
        } else {
            customRangesBadgeLabel.stringValue = ""
            customRangesBadgeLabel.isHidden = true
        }
    }

    private func rebuildRowViews() {
        for rv in rowViews {
            rv.removeFromSuperview()
        }
        rowViews.removeAll()

        for (index, rule) in config.languageRules.enumerated() {
            let rowView = RuleRowView(
                rule: rule,
                index: index,
                totalCount: config.languageRules.count,
                availableFamilies: Self.cachedAvailableFamilies
            )
            rowView.onRuleMutated = { [weak self] idx, updatedRule in
                self?.updateRule(at: idx, with: updatedRule)
            }
            rowView.onMove = { [weak self] idx, delta in
                self?.moveRule(at: idx, by: delta)
            }
            rowView.onDelete = { [weak self] idx in
                self?.deleteRule(at: idx)
            }
            addSubview(rowView)
            rowViews.append(rowView)
        }
        emptyStateLabel.isHidden = !rowViews.isEmpty
    }

    private func commitAndNotify(rebuildRows: Bool) {
        if rebuildRows {
            rebuildRowViews()
        }
        rebuildAddMenu()
        updateCustomRangesBadge()
        needsLayout = true
        onConfigChanged?(configStringValue)
        onLayoutInvalidated?()
    }

    @objc private func addLanguageRuleFromMenu(_ sender: NSPopUpButton) {
        // Handled per-item in addLanguageRuleMenuItem(_:).
    }

    @objc private func addLanguageRuleMenuItem(_ sender: NSMenuItem) {
        let scripts = FontLanguageScript.allCases
        guard sender.tag >= 0, sender.tag < scripts.count else { return }
        let script = scripts[sender.tag]
        guard !config.languageRules.contains(where: { $0.script == script }) else { return }
        let family = script.preferredDefaultFontFamily(availableFamilies: Self.cachedAvailableFamilies)
        let newRule = FontTable.LanguageRule(
            script: script,
            fontName: family,
            scalePercent: 100,
            baselineOffset: 0,
            enabled: true
        )
        config.languageRules.append(newRule)
        commitAndNotify(rebuildRows: true)
    }

    private func updateRule(at index: Int, with updated: FontTable.LanguageRule) {
        guard config.languageRules.indices.contains(index) else { return }
        let scriptChanged = config.languageRules[index].script != updated.script
        config.languageRules[index] = updated
        if scriptChanged {
            rebuildAddMenu()
        }
        onConfigChanged?(configStringValue)
    }

    private func moveRule(at index: Int, by delta: Int) {
        let target = index + delta
        guard config.languageRules.indices.contains(index),
              config.languageRules.indices.contains(target) else { return }
        config.languageRules.swapAt(index, target)
        commitAndNotify(rebuildRows: true)
    }

    private func deleteRule(at index: Int) {
        guard config.languageRules.indices.contains(index) else { return }
        config.languageRules.remove(at: index)
        commitAndNotify(rebuildRows: true)
    }

    // MARK: - Responsive Frame Layout (No Auto Layout)

    @objc(layoutForWidth:trailingButtonWidth:trailingButtonOriginOut:)
    func layout(forWidth rawWidth: CGFloat,
                trailingButtonWidth: CGFloat,
                trailingButtonOriginOut: UnsafeMutablePointer<NSPoint>?) -> CGFloat {
        let width = max(160, rawWidth)
        var y: CGFloat = 0

        let descSize = ProfileFormMeasurement.measureStaticText(descriptionLabel, maxWidth: width)
        descriptionLabel.frame = NSRect(x: 0, y: y, width: width, height: descSize.height)
        y += descSize.height + 8

        if rowViews.isEmpty {
            let emptySize = ProfileFormMeasurement.measureStaticText(emptyStateLabel, maxWidth: width)
            emptyStateLabel.frame = NSRect(x: 0, y: y, width: width, height: emptySize.height)
            y += emptySize.height + 10
        } else {
            for rowView in rowViews {
                let rowH = rowView.layout(forWidth: width)
                rowView.frame = NSRect(x: 0, y: y, width: width, height: rowH)
                y += rowH + 6
            }
            y += 4
        }

        addPullDownButton.sizeToFit()
        let addW = min(width, max(150, ceil(addPullDownButton.fittingSize.width) + 6))
        let buttonH: CGFloat = 24

        var cursorX: CGFloat = 0
        addPullDownButton.frame = NSRect(x: cursorX, y: y, width: addW, height: buttonH)
        cursorX += addW + 8

        var bottomY = y + buttonH

        if !customRangesBadgeLabel.isHidden {
            let badgeSize = ProfileFormMeasurement.measureStaticText(customRangesBadgeLabel, maxWidth: max(80, width - cursorX))
            if cursorX + badgeSize.width <= width {
                let badgeY = y + floor((buttonH - badgeSize.height) * 0.5)
                customRangesBadgeLabel.frame = NSRect(x: cursorX, y: max(y, badgeY), width: badgeSize.width, height: badgeSize.height)
                cursorX += badgeSize.width + 8
            } else {
                let nextY = bottomY + 6
                let fullBadge = ProfileFormMeasurement.measureStaticText(customRangesBadgeLabel, maxWidth: width)
                customRangesBadgeLabel.frame = NSRect(x: 0, y: nextY, width: fullBadge.width, height: fullBadge.height)
                bottomY = nextY + fullBadge.height
                cursorX = fullBadge.width + 8
            }
        }

        if trailingButtonWidth > 0 {
            let trailingW = min(width, ceil(trailingButtonWidth))
            if cursorX + trailingW <= width && bottomY == y + buttonH {
                let rightX = max(cursorX, width - trailingW)
                trailingButtonOriginOut?.pointee = NSPoint(x: rightX, y: y)
            } else {
                let nextY = bottomY + 6
                trailingButtonOriginOut?.pointee = NSPoint(x: 0, y: nextY)
                bottomY = nextY + buttonH
            }
        }

        return bottomY
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 {
            _ = layout(forWidth: bounds.width, trailingButtonWidth: 0, trailingButtonOriginOut: nil)
        }
    }
}

// MARK: - Individual Language Font Rule Row

private final class RuleRowView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }

    var onRuleMutated: ((Int, FontTable.LanguageRule) -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onDelete: ((Int) -> Void)?

    private var rule: FontTable.LanguageRule
    private let index: Int

    private let enableCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let scriptPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeLabel = NSTextField(labelWithString: NSLocalizedString("Size:", comment: "Language font scale label"))
    private let scaleField = NSTextField(frame: .zero)
    private let scaleStepper = NSStepper(frame: .zero)
    private let baselineLabel = NSTextField(labelWithString: NSLocalizedString("Baseline:", comment: "Language font baseline label"))
    private let baselineField = NSTextField(frame: .zero)
    private let baselineStepper = NSStepper(frame: .zero)
    private let moveUpButton = NSButton(frame: .zero)
    private let moveDownButton = NSButton(frame: .zero)
    private let deleteButton = NSButton(frame: .zero)

    init(rule: FontTable.LanguageRule,
         index: Int,
         totalCount: Int,
         availableFamilies: [String]) {
        self.rule = rule
        self.index = index
        super.init(frame: .zero)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1

        setupControls(totalCount: totalCount, availableFamilies: availableFamilies)
        syncControlsFromRule()
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }
    }

    private func setupControls(totalCount: Int, availableFamilies: [String]) {
        enableCheckbox.target = self
        enableCheckbox.action = #selector(toggleEnabled(_:))
        enableCheckbox.toolTip = NSLocalizedString("Enable or disable this language font rule", comment: "Language font tooltip")
        addSubview(enableCheckbox)

        for script in FontLanguageScript.allCases {
            scriptPopup.addItem(withTitle: script.localizedTitle)
            scriptPopup.lastItem?.representedObject = script.rawValue
        }
        scriptPopup.target = self
        scriptPopup.action = #selector(scriptChanged(_:))
        addSubview(scriptPopup)

        var families = availableFamilies
        let resolvedFamily: String = {
            if families.contains(rule.fontName) {
                return rule.fontName
            }
            if let f = NSFont(name: rule.fontName, size: 12)?.familyName, families.contains(f) {
                return f
            }
            families.insert(rule.fontName, at: 0)
            return rule.fontName
        }()
        fontPopup.addItems(withTitles: families)
        fontPopup.selectItem(withTitle: resolvedFamily)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        addSubview(fontPopup)

        for lbl in [sizeLabel, baselineLabel] {
            lbl.font = NSFont.systemFont(ofSize: 11)
            lbl.textColor = .secondaryLabelColor
            ProfileFormMeasurement.configureStaticLabel(lbl, alignment: .right)
            addSubview(lbl)
        }

        for field in [scaleField, baselineField] {
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            field.alignment = .right
            field.controlSize = .small
            field.bezelStyle = .roundedBezel
            field.delegate = self
            addSubview(field)
        }

        scaleStepper.minValue = 50
        scaleStepper.maxValue = 200
        scaleStepper.increment = 5
        scaleStepper.valueWraps = false
        scaleStepper.controlSize = .small
        scaleStepper.target = self
        scaleStepper.action = #selector(scaleStepperChanged(_:))
        addSubview(scaleStepper)

        baselineStepper.minValue = -20
        baselineStepper.maxValue = 20
        baselineStepper.increment = 0.5
        baselineStepper.valueWraps = false
        baselineStepper.controlSize = .small
        baselineStepper.target = self
        baselineStepper.action = #selector(baselineStepperChanged(_:))
        addSubview(baselineStepper)

        configureIconButton(moveUpButton,
                            symbol: .chevronUp,
                            tooltip: NSLocalizedString("Move higher priority", comment: "Language font priority up"),
                            action: #selector(moveRuleUp(_:)),
                            enabled: index > 0)
        configureIconButton(moveDownButton,
                            symbol: .chevronDown,
                            tooltip: NSLocalizedString("Move lower priority", comment: "Language font priority down"),
                            action: #selector(moveRuleDown(_:)),
                            enabled: index + 1 < totalCount)
        configureIconButton(deleteButton,
                            symbol: .trash,
                            tooltip: NSLocalizedString("Remove language font rule", comment: "Language font remove"),
                            action: #selector(removeSelf(_:)),
                            enabled: true)
    }

    private func configureIconButton(_ button: NSButton,
                                     symbol: SFSymbol,
                                     tooltip: String,
                                     action: Selector,
                                     enabled: Bool) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: tooltip)
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.isEnabled = enabled
        addSubview(button)
    }

    private func syncControlsFromRule() {
        enableCheckbox.state = rule.enabled ? .on : .off
        if let idx = FontLanguageScript.allCases.firstIndex(of: rule.script) {
            scriptPopup.selectItem(at: idx)
        }
        scaleField.stringValue = "\(rule.scalePercent)%"
        scaleStepper.integerValue = rule.scalePercent
        baselineField.stringValue = String(format: "%+.1f pt", rule.baselineOffset)
        baselineStepper.doubleValue = Double(rule.baselineOffset)

        let controlsEnabled = rule.enabled
        scriptPopup.isEnabled = controlsEnabled
        fontPopup.isEnabled = controlsEnabled
        scaleField.isEnabled = controlsEnabled
        scaleStepper.isEnabled = controlsEnabled
        baselineField.isEnabled = controlsEnabled
        baselineStepper.isEnabled = controlsEnabled
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        rule.enabled = (sender.state == .on)
        syncControlsFromRule()
        onRuleMutated?(index, rule)
    }

    @objc private func scriptChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let all = FontLanguageScript.allCases
        guard all.indices.contains(idx) else { return }
        rule.script = all[idx]
        onRuleMutated?(index, rule)
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        guard let family = sender.selectedItem?.title, !family.isEmpty else { return }
        rule.fontName = family
        onRuleMutated?(index, rule)
    }

    @objc private func scaleStepperChanged(_ sender: NSStepper) {
        rule.scalePercent = min(200, max(50, sender.integerValue))
        syncControlsFromRule()
        onRuleMutated?(index, rule)
    }

    @objc private func baselineStepperChanged(_ sender: NSStepper) {
        let snapped = (sender.doubleValue * 2.0).rounded() / 2.0
        rule.baselineOffset = CGFloat(min(20.0, max(-20.0, snapped)))
        syncControlsFromRule()
        onRuleMutated?(index, rule)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === scaleField {
            let digits = field.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            if let v = Int(digits) {
                rule.scalePercent = min(200, max(50, v))
            }
            syncControlsFromRule()
            onRuleMutated?(index, rule)
        } else if field === baselineField {
            let cleaned = field.stringValue
                .replacingOccurrences(of: "pt", with: "")
                .replacingOccurrences(of: "+", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned), v.isFinite {
                let snapped = (v * 2.0).rounded() / 2.0
                rule.baselineOffset = CGFloat(min(20.0, max(-20.0, snapped)))
            }
            syncControlsFromRule()
            onRuleMutated?(index, rule)
        }
    }

    @objc private func moveRuleUp(_ sender: Any?) { onMove?(index, -1) }
    @objc private func moveRuleDown(_ sender: Any?) { onMove?(index, 1) }
    @objc private func removeSelf(_ sender: Any?) { onDelete?(index) }

    func layout(forWidth outerWidth: CGFloat) -> CGFloat {
        let padX: CGFloat = 10
        let padY: CGFloat = 8
        let innerW = max(120, outerWidth - padX * 2)

        let checkW: CGFloat = 18
        let iconBtnW: CGFloat = 22
        let actionsW: CGFloat = iconBtnW * 3 + 4
        let rowH: CGFloat = 24

        let sizeLblSize = ProfileFormMeasurement.measureStaticText(sizeLabel, maxWidth: 80)
        let baseLblSize = ProfileFormMeasurement.measureStaticText(baselineLabel, maxWidth: 80)
        let scaleFieldW: CGFloat = 48
        let baseFieldW: CGFloat = 54
        let stepperW: CGFloat = 15
        let metricsGroupW = sizeLblSize.width + 4 + scaleFieldW + 2 + stepperW + 12 + baseLblSize.width + 4 + baseFieldW + 2 + stepperW

        let singleLineMinW: CGFloat = checkW + 6 + 150 + 8 + 150 + 10 + metricsGroupW + 8 + actionsW
        if innerW >= singleLineMinW {
            let y = padY
            enableCheckbox.frame = NSRect(x: padX, y: y + 3, width: checkW, height: 18)
            let scriptX = padX + checkW + 6
            let scriptW: CGFloat = min(176, max(140, floor((innerW - metricsGroupW - actionsW - 40) * 0.44)))
            scriptPopup.frame = NSRect(x: scriptX, y: y, width: scriptW, height: rowH)

            let rightActionsX = padX + innerW - actionsW
            let metricsX = rightActionsX - 8 - metricsGroupW
            let fontX = scriptX + scriptW + 8
            let fontW = max(120, metricsX - 10 - fontX)
            fontPopup.frame = NSRect(x: fontX, y: y, width: fontW, height: rowH)

            layoutMetricsCluster(atX: metricsX, y: y, rowH: rowH, sizeLblSize: sizeLblSize, baseLblSize: baseLblSize, scaleFieldW: scaleFieldW, baseFieldW: baseFieldW, stepperW: stepperW)
            layoutActionButtons(atX: rightActionsX, y: y, rowH: rowH, iconBtnW: iconBtnW)
            return y + rowH + padY
        } else {
            // Two-line compact layout so neither popups nor steppers ever clip on narrow windows.
            let y1 = padY
            enableCheckbox.frame = NSRect(x: padX, y: y1 + 3, width: checkW, height: 18)
            let rightActionsX = padX + innerW - actionsW
            layoutActionButtons(atX: rightActionsX, y: y1, rowH: rowH, iconBtnW: iconBtnW)

            let availPopupsW = max(80, rightActionsX - 8 - (padX + checkW + 6))
            let scriptX = padX + checkW + 6
            if availPopupsW >= 240 {
                let scriptW = floor(availPopupsW * 0.46)
                let fontW = max(60, availPopupsW - scriptW - 8)
                scriptPopup.frame = NSRect(x: scriptX, y: y1, width: scriptW, height: rowH)
                fontPopup.frame = NSRect(x: scriptX + scriptW + 8, y: y1, width: fontW, height: rowH)

                let y2 = y1 + rowH + 6
                let indentX = scriptX
                layoutMetricsCluster(atX: indentX, y: y2, rowH: 20, sizeLblSize: sizeLblSize, baseLblSize: baseLblSize, scaleFieldW: scaleFieldW, baseFieldW: baseFieldW, stepperW: stepperW)
                return y2 + 20 + padY
            } else {
                // Ultra-narrow fallback: stack script popup, font popup, and metrics cleanly.
                scriptPopup.frame = NSRect(x: scriptX, y: y1, width: availPopupsW, height: rowH)
                let y2 = y1 + rowH + 6
                fontPopup.frame = NSRect(x: scriptX, y: y2, width: max(60, innerW - (scriptX - padX)), height: rowH)
                let y3 = y2 + rowH + 6
                layoutMetricsCluster(atX: padX, y: y3, rowH: 20, sizeLblSize: sizeLblSize, baseLblSize: baseLblSize, scaleFieldW: scaleFieldW, baseFieldW: baseFieldW, stepperW: stepperW)
                return y3 + 20 + padY
            }
        }
    }

    private func layoutMetricsCluster(atX startX: CGFloat,
                                      y: CGFloat,
                                      rowH: CGFloat,
                                      sizeLblSize: NSSize,
                                      baseLblSize: NSSize,
                                      scaleFieldW: CGFloat,
                                      baseFieldW: CGFloat,
                                      stepperW: CGFloat) {
        var cx = startX
        let fieldH: CGFloat = 19
        let fieldY = y + floor((rowH - fieldH) * 0.5)
        let lblY = y + floor((rowH - sizeLblSize.height) * 0.5)

        sizeLabel.frame = NSRect(x: cx, y: lblY, width: sizeLblSize.width, height: sizeLblSize.height)
        cx += sizeLblSize.width + 4
        scaleField.frame = NSRect(x: cx, y: fieldY, width: scaleFieldW, height: fieldH)
        cx += scaleFieldW + 2
        scaleStepper.frame = NSRect(x: cx, y: fieldY, width: stepperW, height: fieldH)
        cx += stepperW + 12

        baselineLabel.frame = NSRect(x: cx, y: lblY, width: baseLblSize.width, height: baseLblSize.height)
        cx += baseLblSize.width + 4
        baselineField.frame = NSRect(x: cx, y: fieldY, width: baseFieldW, height: fieldH)
        cx += baseFieldW + 2
        baselineStepper.frame = NSRect(x: cx, y: fieldY, width: stepperW, height: fieldH)
    }

    private func layoutActionButtons(atX startX: CGFloat,
                                     y: CGFloat,
                                     rowH: CGFloat,
                                     iconBtnW: CGFloat) {
        let btnH: CGFloat = 20
        let btnY = y + floor((rowH - btnH) * 0.5)
        moveUpButton.frame = NSRect(x: startX, y: btnY, width: iconBtnW, height: btnH)
        moveDownButton.frame = NSRect(x: startX + iconBtnW + 2, y: btnY, width: iconBtnW, height: btnH)
        deleteButton.frame = NSRect(x: startX + (iconBtnW + 2) * 2, y: btnY, width: iconBtnW, height: btnH)
    }
}
