//
//  SettingsControlFactory.swift
//  Latterm
//

import AppKit
import ColorPicker

/// Programmatic AppKit control factory for Settings controllers.
/// Replaces legacy XIB control definitions while preserving exact PreferenceInfo,
/// search indexing, non-default value indicator, and expression-binding behavior.
@objc(iTermSettingsControlFactory)
final class SettingsControlFactory: NSObject {
    @objc static func localized(_ key: String) -> String {
        if key.isEmpty {
            return ""
        }
        return NSLocalizedString(key, comment: "Settings UI")
    }

    @objc static func label(_ key: String) -> NSTextField {
        let field = NSTextField(labelWithString: localized(key))
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.sizeToFit()
        return field
    }

    @objc static func wrappingLabel(_ key: String, smallSecondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: localized(key))
        if smallSecondary {
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
        } else {
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
        }
        return field
    }

    @objc static func checkbox(_ key: String,
                               target: AnyObject?,
                               action: Selector?,
                               toolTip: String? = nil) -> SettingsCheckbox {
        let button = SettingsCheckbox(frame: NSRect(x: 0, y: 0, width: 220, height: 18))
        button.setButtonType(.switch)
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageLeft
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.title = localized(key)
        button.target = target
        button.action = action
        if let toolTip, !toolTip.isEmpty {
            button.toolTip = localized(toolTip)
        }
        button.sizeToFit()
        return button
    }

    @objc static func radioButton(_ key: String,
                                  tag: Int,
                                  target: AnyObject?,
                                  action: Selector?,
                                  toolTip: String? = nil) -> NSButton {
        let button = NSButton(radioButtonWithTitle: localized(key), target: target, action: action)
        button.tag = tag
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        if let toolTip, !toolTip.isEmpty {
            button.toolTip = localized(toolTip)
        }
        button.sizeToFit()
        return button
    }

    @objc static func pushButton(_ key: String,
                                 target: AnyObject?,
                                 action: Selector?) -> NSButton {
        let button = NSButton(title: localized(key), target: target, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.sizeToFit()
        return button
    }

    static func symbolButton(_ symbol: SFSymbol,
                             accessibilityDescription: String,
                             target: AnyObject?,
                             action: Selector?) -> NSButton {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: localized(accessibilityDescription))
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = target
        button.action = action
        return button
    }

    @objc static func addButton(target: AnyObject?, action: Selector?) -> NSButton {
        symbolButton(.plus, accessibilityDescription: "Add", target: target, action: action)
    }

    @objc static func removeButton(target: AnyObject?, action: Selector?) -> NSButton {
        symbolButton(.minus, accessibilityDescription: "Remove", target: target, action: action)
    }

    @objc static func warningButton(target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.title = "⚠️"
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.target = target
        button.action = action
        button.sizeToFit()
        return button
    }

    @objc static func helpButton(target: AnyObject?, action: Selector?) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.title = ""
        button.bezelStyle = .helpButton
        button.setButtonType(.momentaryPushIn)
        button.target = target
        button.action = action
        button.sizeToFit()
        return button
    }

    @objc static func popoverHelpButton(_ helpTextKey: String) -> PopoverHelpButton {
        let button = PopoverHelpButton(helpText: localized(helpTextKey))
        button.sizeToFit()
        return button
    }

    @objc static func textField(placeholder: String? = nil,
                                width: CGFloat = 180,
                                target: AnyObject? = nil,
                                action: Selector? = nil,
                                delegate: NSTextFieldDelegate? = nil) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        if let placeholder, !placeholder.isEmpty {
            field.placeholderString = localized(placeholder)
        }
        field.target = target
        field.action = action
        field.delegate = delegate
        return field
    }

    @objc static func expandingTextField(placeholder: String? = nil,
                                         width: CGFloat = 320,
                                         target: AnyObject? = nil,
                                         action: Selector? = nil,
                                         delegate: NSTextFieldDelegate? = nil) -> ExpandingTextField {
        let field = ExpandingTextField(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        if let placeholder, !placeholder.isEmpty {
            field.placeholderString = localized(placeholder)
        }
        field.target = target
        field.action = action
        field.delegate = delegate
        return field
    }

    @objc static func tokenField(placeholder: String? = nil,
                                 width: CGFloat = 320,
                                 target: AnyObject? = nil,
                                 action: Selector? = nil,
                                 delegate: NSTokenFieldDelegate? = nil) -> NSTokenField {
        let field = NSTokenField(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.drawsBackground = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        if let placeholder, !placeholder.isEmpty {
            field.placeholderString = localized(placeholder)
        }
        field.target = target
        field.action = action
        field.delegate = delegate
        return field
    }

    /// `items`: array of `[titleKey, tagNumber]` or `["---"]` for separator items.
    @objc static func popupButton(pullsDown: Bool = false,
                                  width: CGFloat = 200,
                                  target: AnyObject? = nil,
                                  action: Selector? = nil,
                                  items: [[Any]]) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 26), pullsDown: pullsDown)
        popup.bezelStyle = .rounded
        popup.font = .systemFont(ofSize: NSFont.systemFontSize)
        popup.menu?.removeAllItems()
        for entry in items {
            guard let rawTitle = entry.first as? String else { continue }
            if rawTitle == "---" {
                popup.menu?.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: localized(rawTitle), action: nil, keyEquivalent: "")
            if entry.count >= 2, let number = entry[1] as? NSNumber {
                menuItem.tag = number.intValue
            }
            popup.menu?.addItem(menuItem)
        }
        popup.target = target
        popup.action = action
        popup.sizeToFit()
        if popup.frame.width < width {
            popup.frame.size.width = width
        }
        return popup
    }

    @objc static func comboBox(defaultTitle: String,
                               items: [String],
                               width: CGFloat = 260,
                               target: AnyObject? = nil,
                               action: Selector? = nil,
                               delegate: NSComboBoxDelegate? = nil) -> NSComboBox {
        let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: width, height: 25))
        combo.isEditable = true
        combo.isSelectable = true
        combo.completes = false
        combo.usesDataSource = false
        combo.numberOfVisibleItems = max(1, items.count)
        combo.addItems(withObjectValues: items)
        combo.stringValue = defaultTitle
        combo.target = target
        combo.action = action
        combo.delegate = delegate
        return combo
    }

    @objc static func slider(minValue: Double,
                             maxValue: Double,
                             doubleValue: Double,
                             width: CGFloat = 200,
                             target: AnyObject?,
                             action: Selector?,
                             toolTip: String? = nil,
                             wrappedInSteppedSlider: Bool = false) -> NSSlider {
        let slider = NSSlider(value: doubleValue, minValue: minValue, maxValue: maxValue, target: target, action: action)
        slider.frame = NSRect(x: 0, y: 0, width: width, height: 22)
        slider.isContinuous = true
        if let toolTip, !toolTip.isEmpty {
            slider.toolTip = localized(toolTip)
        }
        if wrappedInSteppedSlider {
            _ = iTermSlider(frame: NSRect(x: 0, y: 0, width: width + 64, height: 24), slider: slider)
        }
        return slider
    }

    @objc static func stepper(minValue: Double = 0,
                              maxValue: Double = 100,
                              increment: Double = 1,
                              target: AnyObject?,
                              action: Selector?) -> NSStepper {
        let stepper = NSStepper(frame: NSRect(x: 0, y: 0, width: 19, height: 27))
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.isContinuous = true
        stepper.target = target
        stepper.action = action
        stepper.sizeToFit()
        return stepper
    }

    @objc static func colorWell(alphaAllowed: Bool = false) -> SettingsColorWell {
        guard let well = SettingsColorWell(frame: NSRect(x: 0, y: 0, width: 32, height: 21), colorSpace: .sRGB) else {
            it_fatalError("Failed to create SettingsColorWell")
        }
        well.alphaAllowed = alphaAllowed
        well.noColorAllowed = false
        return well
    }

    @objc static func statusImageView() -> NSImageView {
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }

    /// `items`: array of `[titleKey, tagNumber]`, laid out horizontally or vertically as radio cells.
    @objc static func radioMatrix(items: [[Any]],
                                  horizontal: Bool,
                                  target: AnyObject?,
                                  action: Selector?) -> NSMatrix {
        let prototype = NSButtonCell()
        prototype.setButtonType(.radio)
        prototype.imagePosition = .imageLeft
        prototype.font = .systemFont(ofSize: NSFont.systemFontSize)
        let rows = horizontal ? 1 : items.count
        let cols = horizontal ? items.count : 1
        let matrix = NSMatrix(frame: .zero,
                              mode: .radioModeMatrix,
                              prototype: prototype,
                              numberOfRows: rows,
                              numberOfColumns: cols)
        matrix.allowsEmptySelection = false
        matrix.intercellSpacing = NSSize(width: horizontal ? 10 : 4, height: 4)
        for (idx, entry) in items.enumerated() {
            let r = horizontal ? 0 : idx
            let c = horizontal ? idx : 0
            guard let cell = matrix.cell(atRow: r, column: c) as? NSButtonCell else { continue }
            let rawTitle = (entry.first as? String) ?? ""
            cell.title = localized(rawTitle)
            if entry.count >= 2, let number = entry[1] as? NSNumber {
                cell.tag = number.intValue
            } else {
                cell.tag = 0
            }
        }
        matrix.target = target
        matrix.action = action
        matrix.sizeToCells()
        matrix.sizeToFit()
        return matrix
    }

    /// Creates a `SettingsTabView` populated with `[identifier, labelKey]` items.
    @objc static func sectionTabView(frame: NSRect, items: [[String]]) -> SettingsTabView {
        let tabView = SettingsTabView(frame: frame)
        for pair in items where pair.count >= 2 {
            let item = NSTabViewItem(identifier: pair[0])
            item.label = localized(pair[1])
            item.view = NSView(frame: frame)
            tabView.addTabViewItem(item)
        }
        return tabView
    }

    // MARK: - Objective-C Ergonomic Overloads

    @objc(labelWithTitle:)
    static func objcLabel(_ title: String) -> NSTextField {
        label(title)
    }

    @objc(rightAlignedLabelWithTitle:)
    static func objcRightAlignedLabel(_ title: String) -> NSTextField {
        let field = label(title)
        field.alignment = .right
        return field
    }

    @objc(secondaryLabelWithTitle:wrapping:)
    static func objcSecondaryLabel(_ title: String, wrapping: Bool) -> NSTextField {
        if wrapping {
            return wrappingLabel(title, smallSecondary: true)
        }
        let field = NSTextField(labelWithString: localized(title))
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.sizeToFit()
        return field
    }

    @objc(checkboxWithTitle:target:action:)
    static func objcCheckbox(_ title: String, target: AnyObject?, action: Selector?) -> SettingsCheckbox {
        checkbox(title, target: target, action: action)
    }

    @objc(pushButtonWithTitle:target:action:)
    static func objcPushButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        pushButton(title, target: target, action: action)
    }

    @objc(popoverHelpButtonWithHelpText:)
    static func objcPopoverHelpButton(_ helpTextKey: String) -> PopoverHelpButton {
        popoverHelpButton(helpTextKey)
    }

    @objc(textFieldWithWidth:placeholder:target:action:delegate:)
    static func objcTextField(width: CGFloat,
                              placeholder: String?,
                              target: AnyObject?,
                              action: Selector?,
                              delegate: NSTextFieldDelegate?) -> NSTextField {
        textField(placeholder: placeholder, width: width, target: target, action: action, delegate: delegate)
    }

    @objc(expandingTextFieldWithWidth:placeholder:target:action:delegate:)
    static func objcExpandingTextField(width: CGFloat,
                                       placeholder: String?,
                                       target: AnyObject?,
                                       action: Selector?,
                                       delegate: NSTextFieldDelegate?) -> ExpandingTextField {
        expandingTextField(placeholder: placeholder, width: width, target: target, action: action, delegate: delegate)
    }

    @objc(tokenFieldWithWidth:placeholder:target:action:delegate:)
    static func objcTokenField(width: CGFloat,
                               placeholder: String?,
                               target: AnyObject?,
                               action: Selector?,
                               delegate: NSTokenFieldDelegate?) -> NSTokenField {
        tokenField(placeholder: placeholder, width: width, target: target, action: action, delegate: delegate)
    }

    @objc(popUpButtonWithTitles:tags:target:action:)
    static func objcPopUpButton(titles: [String],
                                tags: [NSNumber],
                                target: AnyObject?,
                                action: Selector?) -> NSPopUpButton {
        objcPopUpButton(titles: titles, tags: tags, separators: [], target: target, action: action)
    }

    @objc(popUpButtonWithTitles:tags:separators:target:action:)
    static func objcPopUpButton(titles: [String],
                                tags: [NSNumber],
                                separators: [NSNumber],
                                target: AnyObject?,
                                action: Selector?) -> NSPopUpButton {
        let separatorSet = Set(separators.map(\.intValue))
        var entries: [[Any]] = []
        for (idx, title) in titles.enumerated() {
            if separatorSet.contains(idx) {
                entries.append(["---"])
            } else {
                let tag = idx < tags.count ? tags[idx] : NSNumber(value: 0)
                entries.append([title, tag])
            }
        }
        return popupButton(pullsDown: false, width: 160, target: target, action: action, items: entries)
    }

    @objc(pullDownButtonWithTitle:itemTitles:target:action:)
    static func objcPullDownButton(title: String,
                                   itemTitles: [String],
                                   target: AnyObject?,
                                   action: Selector?) -> NSPopUpButton {
        var entries: [[Any]] = [[title, NSNumber(value: 0)]]
        for (idx, itemTitle) in itemTitles.enumerated() {
            entries.append([itemTitle, NSNumber(value: idx)])
        }
        return popupButton(pullsDown: true, width: 200, target: target, action: action, items: entries)
    }

    @objc(comboBoxWithItems:width:target:action:delegate:)
    static func objcComboBox(items: [String],
                             width: CGFloat,
                             target: AnyObject?,
                             action: Selector?,
                             delegate: NSComboBoxDelegate?) -> NSComboBox {
        comboBox(defaultTitle: items.first ?? "", items: items, width: width, target: target, action: action, delegate: delegate)
    }

    @objc(sliderWithMinValue:maxValue:initialValue:width:wrapInSliderView:target:action:)
    static func objcSlider(minValue: Double,
                           maxValue: Double,
                           initialValue: Double,
                           width: CGFloat,
                           wrapInSliderView: Bool,
                           target: AnyObject?,
                           action: Selector?) -> NSSlider {
        slider(minValue: minValue,
               maxValue: maxValue,
               doubleValue: initialValue,
               width: width,
               target: target,
               action: action,
               wrappedInSteppedSlider: wrapInSliderView)
    }

    @objc(stepperWithMinValue:maxValue:target:action:)
    static func objcStepper(minValue: Double,
                            maxValue: Double,
                            target: AnyObject?,
                            action: Selector?) -> NSStepper {
        stepper(minValue: minValue, maxValue: maxValue, increment: 1, target: target, action: action)
    }

    @objc(radioMatrixWithTitles:tags:horizontal:target:action:)
    static func objcRadioMatrix(titles: [String],
                                tags: [NSNumber],
                                horizontal: Bool,
                                target: AnyObject?,
                                action: Selector?) -> NSMatrix {
        var entries: [[Any]] = []
        for (idx, title) in titles.enumerated() {
            let tag = idx < tags.count ? tags[idx] : NSNumber(value: 0)
            entries.append([title, tag])
        }
        return radioMatrix(items: entries, horizontal: horizontal, target: target, action: action)
    }
}
