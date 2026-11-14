//
//  ProfileFormView.swift
//  iTerm2SharedARC
//
//  Responsive vertical-only card form and scroll primitives for Settings > Profiles.
//

import AppKit
import BetterFontPicker
import ColorPicker

@objc(iTermProfileFormDocumentProtocol)
protocol ProfileFormDocumentProtocol: AnyObject {
    @objc func updateFormLayout(forWidth width: CGFloat)
    @objc func invalidateFormLayout()
    @objc func markDirtyWithoutPropagating()
    @objc var computedHeight: CGFloat { get }
}

private enum ProfileFormPalette {
    static let cardBackground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.048)
            : NSColor(calibratedWhite: 1.0, alpha: 0.72)
    }

    static let cardBorder = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
            : NSColor(calibratedWhite: 0.0, alpha: 0.08)
    }

    static let rowSeparator = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.075)
            : NSColor(calibratedWhite: 0.0, alpha: 0.06)
    }

    static let insetSurfaceBackground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 1.0, alpha: 0.03)
            : NSColor(calibratedWhite: 0.0, alpha: 0.03)
    }
}

enum ProfileFormMetrics {
    static let wideThreshold: CGFloat = 580
    static let compactCardThreshold: CGFloat = 435
    static let maxFormWidth: CGFloat = 800
    static let outerPaddingWide: CGFloat = 20
    static let outerPaddingCompact: CGFloat = 14
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 24
    static let sectionGap: CGFloat = 18
    static let headerBottomGap: CGFloat = 6
    static let footerTopGap: CGFloat = 5
    static let cardCornerRadius: CGFloat = 10
    // 16pt horizontal card padding leaves room for NonDefaultIndicator bars at xOffset = -5..-6.
    static let cardPaddingH: CGFloat = 16
    static let cardPaddingV: CGFloat = 10
    static let rowPaddingV: CGFloat = 8
    static let labelGap: CGFloat = 12
    static let controlGap: CGFloat = 8
    static let lineSpacing: CGFloat = 6
    static let minLabelColumn: CGFloat = 136
    static let maxLabelColumn: CGFloat = 176
}

protocol ProfileUnifiedDocumentHost: AnyObject {
    func invalidateUnifiedLayout()
}

// MARK: - Native Continuous Profile ScrollView

/// Pure native NSScrollView for the continuous single-page Profile editor.
/// Never clamps or mutates clipView boundsOrigin during layout or scroll ticks,
/// preserving 100% native macOS trackpad momentum and rubber-band elasticity.
@objc(iTermProfileUnifiedScrollView)
final class ProfileUnifiedScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureScrollView()
    }

    private func configureScrollView() {
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .automatic
    }

    override func layout() {
        super.layout()
        syncDocumentSizeIfNeeded()
    }

    @objc func syncDocumentSizeIfNeeded() {
        guard let doc = documentView else { return }
        let clipWidth = max(0, floor(contentSize.width))
        guard clipWidth > 0 else { return }

        var desiredHeight = max(contentSize.height, doc.frame.height)
        if let formDoc = doc as? ProfileFormDocumentProtocol {
            formDoc.updateFormLayout(forWidth: clipWidth)
            desiredHeight = max(contentSize.height, ceil(formDoc.computedHeight))
        }
        let targetSize = NSSize(width: clipWidth, height: desiredHeight)
        if abs(doc.frame.width - targetSize.width) > 0.5 ||
            abs(doc.frame.height - targetSize.height) > 0.5 ||
            doc.frame.origin != .zero {
            doc.frame = NSRect(origin: .zero, size: targetSize)
        }
    }

    @objc func scrollControlToVisible(_ control: NSView) {
        guard let doc = documentView else { return }
        syncDocumentSizeIfNeeded()
        doc.layoutSubtreeIfNeeded()
        guard control.isDescendant(of: doc) else { return }
        let controlRect = doc.convert(control.bounds, from: control)
        let padded = controlRect.insetBy(dx: 0, dy: -28).intersection(doc.bounds)
        let target = padded.isNull ? controlRect.intersection(doc.bounds) : padded
        guard !target.isEmpty else { return }
        contentView.scrollToVisible(target)
        reflectScrolledClipView(contentView)
    }
}

// MARK: - Embedded Table ScrollView (Seamless Gesture Passthrough)

/// Embedded NSScrollView for inline settings tables (Jobs, Bound Hosts, Key Bindings).
/// Latches gesture passthrough at gesture start whenever non-overflowing or at edge
/// so trackpad momentum and rubber-banding flow unbroken into the outer page scroll view.
@objc(iTermSettingsEmbeddedScrollView)
final class SettingsEmbeddedScrollView: NSScrollView {
    private var forwardingCurrentGesture = false

    override func awakeFromNib() {
        super.awakeFromNib()
        configureEmbeddedBehavior()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureEmbeddedBehavior()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureEmbeddedBehavior()
    }

    private func configureEmbeddedBehavior() {
        hasHorizontalScroller = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        autohidesScrollers = true
    }

    override func layout() {
        super.layout()
        if let doc = documentView, contentSize.width > 0, doc.frame.width > contentSize.width + 0.5 {
            doc.setFrameSize(NSSize(width: contentSize.width, height: doc.frame.height))
        }
    }

    private func enclosingPageScrollView() -> NSScrollView? {
        var current: NSView? = superview
        while let view = current {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller {
                return scroll
            }
            current = view.superview
        }
        return nil
    }

    private func canScrollInternally(deltaY: CGFloat) -> Bool {
        let docHeight = documentView?.bounds.height ?? 0
        let clipBounds = contentView.bounds
        guard docHeight > clipBounds.height + 1.5 else {
            return false
        }
        let isFlipped = documentView?.isFlipped ?? true
        let atTop = isFlipped ? (clipBounds.minY <= 0.5) : (clipBounds.maxY >= docHeight - 0.5)
        let atBottom = isFlipped ? (clipBounds.maxY >= docHeight - 0.5) : (clipBounds.minY <= 0.5)
        if deltaY > 0.01 && atTop { return false }
        if deltaY < -0.01 && atBottom { return false }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let outer = enclosingPageScrollView() else {
            super.scrollWheel(with: event)
            return
        }

        let isNewGesture = event.phase == .mayBegin ||
            event.phase == .began ||
            (event.phase == [] && event.momentumPhase == [])

        if isNewGesture {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.2 {
                forwardingCurrentGesture = true
            } else {
                forwardingCurrentGesture = !canScrollInternally(deltaY: event.scrollingDeltaY)
            }
        }

        if forwardingCurrentGesture {
            outer.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }

        if event.phase == .ended || event.phase == .cancelled ||
            event.momentumPhase == .ended || event.momentumPhase == .cancelled {
            if event.momentumPhase == .ended || event.momentumPhase == .cancelled {
                forwardingCurrentGesture = false
            }
        }
    }
}

// MARK: - Control Measurement & Wrapping Configuration

enum ProfileFormMeasurement {
    static func configureStaticLabel(_ field: NSTextField,
                                     alignment: NSTextAlignment = .left,
                                     trimTrailingSpaces: Bool = false) {
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.alignment = alignment
        if let cell = field.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.usesSingleLineMode = false
            cell.isScrollable = false
            cell.lineBreakMode = .byWordWrapping
        }
        if trimTrailingSpaces {
            let trimmed = field.stringValue.replacingOccurrences(of: "\\s+$",
                                                                 with: "",
                                                                 options: .regularExpression)
            if trimmed != field.stringValue {
                field.stringValue = trimmed
            }
        }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    static func configureWrappingCheckbox(_ button: NSButton) {
        button.usesSingleLineMode = false
        button.lineBreakMode = .byWordWrapping
        if let cell = button.cell as? NSButtonCell {
            cell.wraps = true
            cell.usesSingleLineMode = false
            cell.lineBreakMode = .byWordWrapping
        }
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    static func makeSectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        configureStaticLabel(label, alignment: .left)
        return label
    }

    static func makeCaptionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        configureStaticLabel(label, alignment: .left)
        return label
    }

    static func measureStaticText(_ field: NSTextField, maxWidth: CGFloat) -> NSSize {
        let width = max(20, floor(maxWidth))
        let sized = field.sizeThatFits(NSSize(width: width, height: 10_000))
        return NSSize(width: min(width, ceil(sized.width)), height: max(16, ceil(sized.height)))
    }

    static func measureCheckbox(_ button: NSButton, maxWidth: CGFloat) -> NSSize {
        configureWrappingCheckbox(button)
        let width = max(36, floor(maxWidth))
        let fitting = button.fittingSize
        if fitting.width <= width {
            return NSSize(width: ceil(fitting.width), height: max(18, ceil(fitting.height)))
        }
        if let cell = button.cell as? NSButtonCell {
            let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000))
            if cellSize.height > 20 {
                return NSSize(width: min(width, ceil(cellSize.width)), height: ceil(cellSize.height))
            }
        }
        let textWidth = max(24, width - 22)
        let font = button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributed = NSAttributedString(string: button.title, attributes: [.font: font])
        let rect = attributed.boundingRect(with: NSSize(width: textWidth, height: 10_000),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: width, height: max(18, ceil(rect.height) + 4))
    }

    static func isCheckbox(_ button: NSButton) -> Bool {
        if button is SettingsCheckbox {
            return true
        }
        guard !(button is PopoverHelpButton), button.bezelStyle != .helpButton else {
            return false
        }
        // Checkboxes in PreferencePanel.xib are borderless with non-empty text labels,
        // whereas push buttons are bordered and icon/emoji warning buttons are very short.
        return !button.isBordered && button.title.count > 2
    }

    static func measureControl(_ view: NSView, maxWidth: CGFloat) -> NSSize {
        let clampedMax = max(24, floor(maxWidth))
        if let picker = view as? FontPickerCompositeView {
            return NSSize(width: clampedMax, height: picker.preferredHeight(forWidth: clampedMax))
        }
        if let label = view as? NSTextField, !label.isEditable {
            return measureStaticText(label, maxWidth: clampedMax)
        }
        if let popUp = view as? NSPopUpButton {
            let fit = popUp.fittingSize
            return NSSize(width: min(clampedMax, max(72, ceil(fit.width))),
                          height: max(24, ceil(fit.height)))
        }
        if let button = view as? NSButton {
            if button is PopoverHelpButton || button.bezelStyle == .helpButton {
                return NSSize(width: 22, height: 22)
            }
            if isCheckbox(button) {
                return measureCheckbox(button, maxWidth: clampedMax)
            }
            let fit = button.fittingSize
            return NSSize(width: min(clampedMax, max(24, ceil(fit.width))),
                          height: max(22, ceil(fit.height)))
        }
        if let sliderContainer = view as? iTermSlider {
            let height = max(22, sliderContainer.frame.height > 0 ? sliderContainer.frame.height : 22)
            return NSSize(width: min(clampedMax, 240), height: height)
        }
        if view is SettingsColorWell || view is CPKColorWell || view is NSColorWell {
            return NSSize(width: min(clampedMax, 40), height: 22)
        }
        if let field = view as? NSTextField {
            if let expanding = field as? ExpandingTextField, expanding.bounds.width > 0 {
                let fit = expanding.fittingSize
                return NSSize(width: min(clampedMax, max(60, ceil(fit.width))),
                              height: max(22, ceil(fit.height)))
            }
            let fit = field.fittingSize
            return NSSize(width: min(clampedMax, max(60, ceil(fit.width))),
                          height: max(22, ceil(fit.height)))
        }
        let fit = view.fittingSize
        let w = fit.width > 0 ? fit.width : view.frame.width
        let h = fit.height > 0 ? fit.height : view.frame.height
        return NSSize(width: min(clampedMax, max(16, ceil(w))), height: max(18, ceil(h)))
    }
}

// MARK: - Form Rows & Section Cards

enum ProfileFormRowContent {
    case single(NSView, fillsWidth: Bool, minWidth: CGFloat, maxWidth: CGFloat)
    case checkbox(NSButton, trailing: [NSView])
    case wrappingLine([ProfileFormInlineItem])
    case slider(container: NSView, minLabel: NSTextField?, maxLabel: NSTextField?, trailingNote: NSView?, maxWidth: CGFloat)
    case fontPicker(NSView)
    case note(NSTextField)
    case custom(hostedViews: [NSView], layout: (_ contentOriginX: CGFloat, _ availableWidth: CGFloat, _ topY: CGFloat, _ isStacked: Bool) -> CGFloat)
}

struct ProfileFormInlineItem {
    enum Sizing {
        case natural(minWidth: CGFloat, maxWidth: CGFloat)
        case fill(minWidth: CGFloat, maxWidth: CGFloat)
        case fixed(CGFloat)
    }

    let view: NSView
    let sizing: Sizing
    let wrapsOntoNewLineWhenTight: Bool

    static func natural(_ view: NSView,
                        minWidth: CGFloat = 24,
                        maxWidth: CGFloat = .greatestFiniteMagnitude,
                        wraps: Bool = true) -> ProfileFormInlineItem {
        ProfileFormInlineItem(view: view,
                              sizing: .natural(minWidth: minWidth, maxWidth: maxWidth),
                              wrapsOntoNewLineWhenTight: wraps)
    }

    static func fill(_ view: NSView,
                     minWidth: CGFloat = 110,
                     maxWidth: CGFloat = .greatestFiniteMagnitude,
                     wraps: Bool = true) -> ProfileFormInlineItem {
        ProfileFormInlineItem(view: view,
                              sizing: .fill(minWidth: minWidth, maxWidth: maxWidth),
                              wrapsOntoNewLineWhenTight: wraps)
    }

    static func fixed(_ view: NSView, width: CGFloat, wraps: Bool = true) -> ProfileFormInlineItem {
        ProfileFormInlineItem(view: view, sizing: .fixed(width), wrapsOntoNewLineWhenTight: wraps)
    }
}

final class ProfileRowHostView: NSView {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }
}

final class ProfileFormRow {
    let hostView = ProfileRowHostView()
    let label: NSTextField?
    let content: ProfileFormRowContent
    let helperViews: [NSView]
    let indent: CGFloat
    let fullCardWidth: Bool
    let suppressSeparatorAfter: Bool
    let visibilityPredicate: (() -> Bool)?
    let alignmentOverride: NSTextAlignment?

    init(label: NSTextField? = nil,
         content: ProfileFormRowContent,
         helperViews: [NSView] = [],
         indent: CGFloat = 0,
         fullCardWidth: Bool = false,
         suppressSeparatorAfter: Bool = false,
         isVisible: (() -> Bool)? = nil,
         alignmentOverride: NSTextAlignment? = nil) {
        self.label = label
        self.content = content
        self.helperViews = helperViews
        self.indent = indent
        self.fullCardWidth = fullCardWidth
        self.suppressSeparatorAfter = suppressSeparatorAfter
        self.visibilityPredicate = isVisible
        self.alignmentOverride = alignmentOverride
        if let label {
            ProfileFormMeasurement.configureStaticLabel(label, alignment: .right, trimTrailingSpaces: true)
        }
        for helper in helperViews {
            if let field = helper as? NSTextField, !field.isEditable {
                ProfileFormMeasurement.configureStaticLabel(field, alignment: .left)
            }
        }
        attachOwnedViews()
    }

    var allViews: [NSView] {
        var result: [NSView] = []
        if let label { result.append(label) }
        switch content {
        case .single(let v, _, _, _):
            result.append(v)
        case .checkbox(let button, let trailing):
            result.append(button)
            result.append(contentsOf: trailing)
        case .wrappingLine(let items):
            result.append(contentsOf: items.map(\.view))
        case .slider(let container, let minLabel, let maxLabel, let trailingNote, _):
            result.append(container)
            if let minLabel { result.append(minLabel) }
            if let maxLabel { result.append(maxLabel) }
            if let trailingNote { result.append(trailingNote) }
        case .fontPicker(let picker):
            result.append(picker)
        case .note(let field):
            result.append(field)
        case .custom(let hostedViews, _):
            result.append(contentsOf: hostedViews)
        }
        result.append(contentsOf: helperViews)
        return result
    }

    func currentlyVisible() -> Bool {
        if let visibilityPredicate, !visibilityPredicate() {
            return false
        }
        switch content {
        case .single(let view, _, _, _):
            return !view.isHidden
        case .checkbox(let button, _):
            return !button.isHidden
        case .wrappingLine(let items):
            return items.contains { !$0.view.isHidden }
        case .slider(let container, _, _, _, _):
            return !container.isHidden
        case .fontPicker(let picker):
            return !picker.isHidden
        case .note(let field):
            return !field.isHidden
        case .custom(let hostedViews, _):
            return hostedViews.isEmpty || hostedViews.contains { !$0.isHidden }
        }
    }

    private func attachOwnedViews() {
        for view in allViews where view.superview !== hostView {
            view.removeFromSuperview()
            view.autoresizingMask = []
            hostView.addSubview(view)
        }
    }

    func attach(to cardContentView: NSView) {
        if hostView.superview !== cardContentView {
            hostView.removeFromSuperview()
            cardContentView.addSubview(hostView)
        }
    }

    func setVisibleInCard(_ visible: Bool) {
        hostView.isHidden = !visible
        if !visible {
            hostView.frame = .zero
        }
    }

    func layout(topY: CGFloat,
                cardWidth: CGFloat,
                labelWidth: CGFloat?,
                isStacked: Bool) -> CGFloat {
        attachOwnedViews()
        hostView.isHidden = false
        let paddingH = ProfileFormMetrics.cardPaddingH
        let innerWidth = max(120, cardWidth - paddingH * 2)

        var contentX = paddingH + indent
        var contentWidth = max(80, innerWidth - indent)
        var labelHeight: CGFloat = 0

        if let label, !fullCardWidth {
            if isStacked || labelWidth == nil {
                label.isHidden = false
                ProfileFormMeasurement.configureStaticLabel(label,
                                                            alignment: alignmentOverride ?? .left,
                                                            trimTrailingSpaces: true)
                let labelSize = ProfileFormMeasurement.measureStaticText(label, maxWidth: innerWidth)
                label.frame = NSRect(x: paddingH, y: 0, width: innerWidth, height: labelSize.height)
                labelHeight = labelSize.height + 5
            } else if let lw = labelWidth {
                label.isHidden = false
                ProfileFormMeasurement.configureStaticLabel(label,
                                                            alignment: alignmentOverride ?? .right,
                                                            trimTrailingSpaces: true)
                let labelSize = ProfileFormMeasurement.measureStaticText(label, maxWidth: lw)
                let valueStart = paddingH + lw + ProfileFormMetrics.labelGap + indent
                contentX = valueStart
                contentWidth = max(80, cardWidth - paddingH - valueStart)
                let verticalOffset: CGFloat = labelSize.height <= 20 ? 3 : 0
                label.frame = NSRect(x: paddingH,
                                     y: verticalOffset,
                                     width: lw,
                                     height: labelSize.height)
            }
        } else if let label, fullCardWidth {
            label.isHidden = false
            ProfileFormMeasurement.configureStaticLabel(label, alignment: .left, trimTrailingSpaces: true)
            let labelSize = ProfileFormMeasurement.measureStaticText(label, maxWidth: innerWidth)
            label.frame = NSRect(x: paddingH, y: 0, width: innerWidth, height: labelSize.height)
            labelHeight = labelSize.height + 6
        } else if !fullCardWidth, !isStacked, let lw = labelWidth {
            // Checkbox/note rows without a left label still align neatly on the value spine.
            let valueStart = paddingH + lw + ProfileFormMetrics.labelGap + indent
            contentX = valueStart
            contentWidth = max(80, cardWidth - paddingH - valueStart)
        }

        let controlTopY = (isStacked || fullCardWidth) ? labelHeight : 0
        var contentHeight = layoutContent(x: contentX,
                                          y: controlTopY,
                                          availableWidth: contentWidth,
                                          isStacked: isStacked)

        if !isStacked, let label, !fullCardWidth, labelWidth != nil {
            contentHeight = max(contentHeight, label.frame.height + 4)
        }

        var currentY = controlTopY + contentHeight
        for helper in helperViews where !helper.isHidden {
            currentY += 5
            let size = ProfileFormMeasurement.measureControl(helper, maxWidth: contentWidth)
            helper.frame = NSRect(x: contentX, y: currentY, width: size.width, height: size.height)
            currentY += size.height
        }

        let rowHeight = max(1, currentY)
        hostView.frame = NSRect(x: 0, y: topY, width: cardWidth, height: rowHeight)
        return rowHeight
    }

    private func layoutContent(x: CGFloat,
                               y: CGFloat,
                               availableWidth: CGFloat,
                               isStacked: Bool) -> CGFloat {
        switch content {
        case .single(let view, let fillsWidth, let minWidth, let maxWidth):
            let measured = ProfileFormMeasurement.measureControl(view, maxWidth: availableWidth)
            let targetWidth: CGFloat
            if fillsWidth {
                targetWidth = min(availableWidth, maxWidth)
            } else {
                targetWidth = min(availableWidth, max(minWidth, min(maxWidth, measured.width)))
            }
            view.frame = NSRect(x: x, y: y, width: targetWidth, height: measured.height)
            return measured.height

        case .checkbox(let button, let trailing):
            let visibleTrailing = trailing.filter { !$0.isHidden }
            if visibleTrailing.isEmpty {
                let size = ProfileFormMeasurement.measureCheckbox(button, maxWidth: availableWidth)
                button.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
                return size.height
            }
            let items: [ProfileFormInlineItem] =
                [.natural(button, minWidth: 40, maxWidth: availableWidth, wraps: false)] +
                visibleTrailing.map { .natural($0, wraps: true) }
            return layoutWrappingItems(items, x: x, y: y, availableWidth: availableWidth)

        case .wrappingLine(let items):
            return layoutWrappingItems(items.filter { !$0.view.isHidden },
                                       x: x,
                                       y: y,
                                       availableWidth: availableWidth)

        case .slider(let container, let minLabel, let maxLabel, let trailingNote, let maxWidth):
            let sliderWidth = min(availableWidth, maxWidth)
            let sliderHeight = max(22, container.frame.height > 0 ? container.frame.height : 22)
            container.frame = NSRect(x: x, y: y, width: sliderWidth, height: sliderHeight)
            var bottomY = y + sliderHeight
            if minLabel != nil || maxLabel != nil {
                bottomY += 2
                var captionH: CGFloat = 0
                if let minLabel, !minLabel.isHidden {
                    ProfileFormMeasurement.configureStaticLabel(minLabel, alignment: .left)
                    let minSize = ProfileFormMeasurement.measureStaticText(minLabel, maxWidth: sliderWidth * 0.48)
                    minLabel.frame = NSRect(x: x, y: bottomY, width: minSize.width, height: minSize.height)
                    captionH = max(captionH, minSize.height)
                }
                if let maxLabel, !maxLabel.isHidden {
                    ProfileFormMeasurement.configureStaticLabel(maxLabel, alignment: .right)
                    let maxSize = ProfileFormMeasurement.measureStaticText(maxLabel, maxWidth: sliderWidth * 0.48)
                    let rightEdge = max(x + sliderWidth * 0.52, x + sliderWidth - maxSize.width - 42)
                    maxLabel.frame = NSRect(x: max(x, rightEdge),
                                            y: bottomY,
                                            width: min(maxSize.width, sliderWidth),
                                            height: maxSize.height)
                    captionH = max(captionH, maxSize.height)
                }
                bottomY += captionH
            }
            if let trailingNote, !trailingNote.isHidden {
                bottomY += 5
                if let field = trailingNote as? NSTextField, !field.isEditable {
                    ProfileFormMeasurement.configureStaticLabel(field, alignment: .left)
                }
                let noteSize = ProfileFormMeasurement.measureControl(trailingNote, maxWidth: availableWidth)
                trailingNote.frame = NSRect(x: x, y: bottomY, width: noteSize.width, height: noteSize.height)
                bottomY += noteSize.height
            }
            return bottomY - y

        case .fontPicker(let picker):
            let height: CGFloat
            if let fontPicker = picker as? FontPickerCompositeView {
                height = fontPicker.preferredHeight(forWidth: availableWidth)
            } else {
                height = max(24, ProfileFormMeasurement.measureControl(picker, maxWidth: availableWidth).height)
            }
            picker.frame = NSRect(x: x, y: y, width: availableWidth, height: height)
            return height

        case .note(let field):
            ProfileFormMeasurement.configureStaticLabel(field, alignment: .left)
            let size = ProfileFormMeasurement.measureStaticText(field, maxWidth: availableWidth)
            field.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            return size.height

        case .custom(_, let layoutBlock):
            return layoutBlock(x, availableWidth, y, isStacked)
        }
    }

    private func layoutWrappingItems(_ items: [ProfileFormInlineItem],
                                     x: CGFloat,
                                     y: CGFloat,
                                     availableWidth: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let gap = ProfileFormMetrics.controlGap

        struct MeasuredEntry {
            let item: ProfileFormInlineItem
            let naturalSize: NSSize
            let minWidth: CGFloat
            let maxWidth: CGFloat
            let isFill: Bool
        }

        let entries: [MeasuredEntry] = items.map { item in
            let measured = ProfileFormMeasurement.measureControl(item.view, maxWidth: availableWidth)
            switch item.sizing {
            case .fixed(let w):
                let clamped = min(availableWidth, w)
                return MeasuredEntry(item: item,
                                     naturalSize: NSSize(width: clamped, height: measured.height),
                                     minWidth: clamped,
                                     maxWidth: clamped,
                                     isFill: false)
            case .natural(let minW, let maxW):
                let clampedMax = min(availableWidth, maxW)
                let targetW = min(clampedMax, max(min(minW, availableWidth), measured.width))
                return MeasuredEntry(item: item,
                                     naturalSize: NSSize(width: targetW, height: measured.height),
                                     minWidth: min(targetW, minW),
                                     maxWidth: clampedMax,
                                     isFill: false)
            case .fill(let minW, let maxW):
                let clampedMax = min(availableWidth, maxW)
                let clampedMin = min(availableWidth, minW)
                return MeasuredEntry(item: item,
                                     naturalSize: NSSize(width: max(clampedMin, min(clampedMax, measured.width)),
                                                         height: measured.height),
                                     minWidth: clampedMin,
                                     maxWidth: clampedMax,
                                     isFill: true)
            }
        }

        // Split entries into visual lines so items never overflow availableWidth.
        var lines: [[MeasuredEntry]] = [[]]
        var currentLineWidth: CGFloat = 0

        for entry in entries {
            let requiredWidth = entry.isFill ? max(entry.minWidth, 120) : entry.naturalSize.width
            let addedGap = lines[lines.count - 1].isEmpty ? 0 : gap
            if !lines[lines.count - 1].isEmpty &&
                entry.item.wrapsOntoNewLineWhenTight &&
                currentLineWidth + addedGap + requiredWidth > availableWidth {
                lines.append([entry])
                currentLineWidth = requiredWidth
            } else {
                lines[lines.count - 1].append(entry)
                currentLineWidth += addedGap + requiredWidth
            }
        }

        var lineY = y
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                lineY += ProfileFormMetrics.lineSpacing
            }
            let gapTotal = CGFloat(max(0, line.count - 1)) * gap
            let fixedAndNaturalTotal = line.reduce(CGFloat(0)) { sum, e in
                sum + (e.isFill ? 0 : e.naturalSize.width)
            }
            let fillEntries = line.filter(\.isFill)
            let remainingForFill = max(0, availableWidth - fixedAndNaturalTotal - gapTotal)
            let perFill = fillEntries.isEmpty ? 0 : floor(remainingForFill / CGFloat(fillEntries.count))

            // If fixed/natural items alone overflow (narrow window with single non-wrapping pair),
            // shrink the widest natural item to keep all items inside availableWidth.
            var assignedWidths: [CGFloat] = line.map { entry in
                if entry.isFill {
                    return min(entry.maxWidth, max(entry.minWidth, perFill))
                }
                return entry.naturalSize.width
            }
            let totalAssigned = assignedWidths.reduce(0, +) + gapTotal
            if totalAssigned > availableWidth, line.count > 0 {
                var excess = totalAssigned - availableWidth
                for idx in line.indices.reversed() where excess > 0 {
                    let floorW: CGFloat = line[idx].isFill ? 60 : min(line[idx].minWidth, 72)
                    let reducible = max(0, assignedWidths[idx] - floorW)
                    let cut = min(excess, reducible)
                    assignedWidths[idx] -= cut
                    excess -= cut
                }
            }

            var resolvedSizes: [NSSize] = []
            resolvedSizes.reserveCapacity(line.count)
            for (idx, entry) in line.enumerated() {
                let w = max(16, min(availableWidth, floor(assignedWidths[idx])))
                let remeasured = ProfileFormMeasurement.measureControl(entry.item.view, maxWidth: w)
                resolvedSizes.append(NSSize(width: w, height: max(remeasured.height, entry.naturalSize.height)))
            }

            let lineHeight = resolvedSizes.map(\.height).max() ?? 22
            var cursorX = x
            for (idx, entry) in line.enumerated() {
                let size = resolvedSizes[idx]
                let itemY = lineY + floor((lineHeight - size.height) / 2.0)
                entry.item.view.frame = NSRect(x: cursorX, y: itemY, width: size.width, height: size.height)
                cursorX += size.width + gap
            }
            lineY += lineHeight
        }

        return lineY - y
    }
}

// MARK: - Section Card Container

final class ProfileSectionCard: NSView {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    let titleLabel: NSTextField?
    let headerAccessory: NSView?
    let footerLabel: NSTextField?
    let backingEnclosure: NSView?
    let visibilityPredicate: (() -> Bool)?
    let rows: [ProfileFormRow]

    private let cardBox = NonClippingCardSurface()
    private var separators: [NSView] = []
    private(set) var computedHeight: CGFloat = 0

    init(title: String?,
         headerAccessory: NSView? = nil,
         footerText: String? = nil,
         backingEnclosure: NSView? = nil,
         isVisible: (() -> Bool)? = nil,
         rows: [ProfileFormRow]) {
        self.titleLabel = title.map { ProfileFormMeasurement.makeSectionTitle($0) }
        self.headerAccessory = headerAccessory
        self.footerLabel = footerText.map { ProfileFormMeasurement.makeCaptionLabel($0) }
        self.backingEnclosure = backingEnclosure
        self.visibilityPredicate = isVisible
        self.rows = rows
        super.init(frame: .zero)
        autoresizesSubviews = false

        if let titleLabel {
            addSubview(titleLabel)
        }
        if let headerAccessory {
            addSubview(headerAccessory)
        }
        addSubview(cardBox)
        for row in rows {
            row.attach(to: cardBox)
        }
        if let footerLabel {
            addSubview(footerLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    func updateLayout(forWidth width: CGFloat) -> CGFloat {
        if let visibilityPredicate, !visibilityPredicate() {
            isHidden = true
            for row in rows { row.setVisibleInCard(false) }
            computedHeight = 0
            return 0
        }
        if let backingEnclosure, backingEnclosure.isHidden {
            isHidden = true
            for row in rows { row.setVisibleInCard(false) }
            computedHeight = 0
            return 0
        }

        var visibleRows: [ProfileFormRow] = []
        for row in rows {
            row.attach(to: cardBox)
            let visible = row.currentlyVisible()
            row.setVisibleInCard(visible)
            if visible {
                visibleRows.append(row)
            }
        }
        if visibleRows.isEmpty {
            isHidden = true
            computedHeight = 0
            return 0
        }
        isHidden = false

        var y: CGFloat = 0
        if let titleLabel {
            let accessorySize: NSSize
            if let headerAccessory, !headerAccessory.isHidden {
                accessorySize = ProfileFormMeasurement.measureControl(headerAccessory, maxWidth: width * 0.4)
            } else {
                accessorySize = .zero
            }
            let titleMaxW = accessorySize.width > 0 ? max(80, width - accessorySize.width - 8) : width
            let titleSize = ProfileFormMeasurement.measureStaticText(titleLabel, maxWidth: titleMaxW)
            let headerH = max(titleSize.height, accessorySize.height)
            titleLabel.frame = NSRect(x: 4,
                                      y: y + floor((headerH - titleSize.height) / 2.0),
                                      width: titleMaxW,
                                      height: titleSize.height)
            if let headerAccessory, !headerAccessory.isHidden {
                headerAccessory.frame = NSRect(x: width - accessorySize.width,
                                               y: y + floor((headerH - accessorySize.height) / 2.0),
                                               width: accessorySize.width,
                                               height: accessorySize.height)
            }
            y += headerH + ProfileFormMetrics.headerBottomGap
        }

        let isStacked = width < ProfileFormMetrics.compactCardThreshold
        let labelWidth: CGFloat? = isStacked
            ? nil
            : min(ProfileFormMetrics.maxLabelColumn,
                  max(ProfileFormMetrics.minLabelColumn, floor(width * 0.28)))

        let cardTop = y
        var innerY: CGFloat = ProfileFormMetrics.cardPaddingV
        ensureSeparatorCount(max(0, visibleRows.count - 1))
        for sep in separators {
            sep.isHidden = true
        }

        for (index, row) in visibleRows.enumerated() {
            if index > 0 {
                let prev = visibleRows[index - 1]
                if !prev.suppressSeparatorAfter {
                    innerY += 4
                    let sep = separators[index - 1]
                    sep.isHidden = false
                    sep.frame = NSRect(x: ProfileFormMetrics.cardPaddingH,
                                       y: innerY,
                                       width: max(0, width - ProfileFormMetrics.cardPaddingH * 2),
                                       height: 1)
                    innerY += 5
                } else {
                    innerY += 4
                }
            }
            let rowHeight = row.layout(topY: innerY,
                                       cardWidth: width,
                                       labelWidth: labelWidth,
                                       isStacked: isStacked)
            innerY += rowHeight
            if index < visibleRows.count - 1 {
                innerY += 4
            }
        }
        innerY += ProfileFormMetrics.cardPaddingV

        cardBox.frame = NSRect(x: 0, y: cardTop, width: width, height: innerY)
        y = cardTop + innerY

        if let footerLabel {
            y += ProfileFormMetrics.footerTopGap
            let footerMaxW = max(80, width - 8)
            let size = ProfileFormMeasurement.measureStaticText(footerLabel, maxWidth: footerMaxW)
            footerLabel.frame = NSRect(x: 4, y: y, width: max(0, width - 8), height: size.height)
            y += size.height
        }

        computedHeight = y
        return y
    }

    private func ensureSeparatorCount(_ needed: Int) {
        while separators.count < needed {
            let line = SeparatorView()
            cardBox.addSubview(line)
            separators.append(line)
        }
    }
}

private final class NonClippingCardSurface: NSView {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    private let backgroundBackdrop = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = false
        backgroundBackdrop.wantsLayer = true
        backgroundBackdrop.layer?.cornerRadius = ProfileFormMetrics.cardCornerRadius
        backgroundBackdrop.layer?.borderWidth = 1
        addSubview(backgroundBackdrop, positioned: .below, relativeTo: nil)
        refreshAppearanceColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        backgroundBackdrop.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearanceColors()
    }

    private func refreshAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundBackdrop.layer?.backgroundColor = ProfileFormPalette.cardBackground.cgColor
            backgroundBackdrop.layer?.borderColor = ProfileFormPalette.cardBorder.cgColor
        }
    }
}

private final class SeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
        wantsLayer = true
        refreshColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColor()
    }

    private func refreshColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = ProfileFormPalette.rowSeparator.cgColor
        }
    }
}

// MARK: - Form Document View

@objc(iTermProfileFormDocumentView)
final class ProfileFormDocumentView: NSView, ProfileFormDocumentProtocol {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    private let sections: [ProfileSectionCard]
    private var legacyViewsToHide: [NSView]
    private(set) var computedHeight: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = -1
    private var layoutDirty = true

    init(sections: [ProfileSectionCard], legacyViewsToHide: [NSView] = []) {
        self.sections = sections
        self.legacyViewsToHide = legacyViewsToHide
        super.init(frame: .zero)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = false
        for section in sections {
            addSubview(section)
        }
        hideLegacyViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    func adoptHiddenLegacyViews(_ views: [NSView]) {
        for view in views {
            if view.superview !== self {
                view.removeFromSuperview()
                view.autoresizingMask = []
                addSubview(view)
            }
            if !legacyViewsToHide.contains(where: { $0 === view }) {
                legacyViewsToHide.append(view)
            }
        }
        hideLegacyViews()
    }

    private func hideLegacyViews() {
        for view in legacyViewsToHide {
            view.isHidden = true
            view.frame = .zero
        }
    }

    @objc func markDirtyWithoutPropagating() {
        layoutDirty = true
    }

    @objc func invalidateFormLayout() {
        layoutDirty = true
        needsLayout = true
        var cursor: NSView? = superview
        while let view = cursor {
            if let unified = view as? ProfileUnifiedDocumentHost {
                unified.invalidateUnifiedLayout()
            }
            if let scroll = view as? ProfileUnifiedScrollView {
                scroll.needsLayout = true
            }
            cursor = view.superview
        }
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, (layoutDirty || abs(bounds.width - lastLaidOutWidth) > 0.25) {
            updateFormLayout(forWidth: bounds.width)
        }
    }

    @objc func updateFormLayout(forWidth width: CGFloat) {
        guard width > 0 else { return }
        if !layoutDirty && abs(width - lastLaidOutWidth) <= 0.25 {
            return
        }
        layoutDirty = false
        lastLaidOutWidth = width

        let outerPadding = width >= ProfileFormMetrics.wideThreshold
            ? ProfileFormMetrics.outerPaddingWide
            : ProfileFormMetrics.outerPaddingCompact
        let usableWidth = max(120, width - outerPadding * 2)
        let cardWidth = min(ProfileFormMetrics.maxFormWidth, usableWidth)
        let originX = max(0, floor((width - cardWidth) / 2.0))

        var y: CGFloat = 6
        var visibleCardCount = 0
        for section in sections {
            let sectionHeight = section.updateLayout(forWidth: cardWidth)
            guard sectionHeight > 0 else { continue }
            if visibleCardCount > 0 {
                y += ProfileFormMetrics.sectionGap
            }
            section.frame = NSRect(x: originX, y: y, width: cardWidth, height: sectionHeight)
            y += sectionHeight
            visibleCardCount += 1
        }
        computedHeight = visibleCardCount == 0 ? 0 : (y + 8)
    }

    /// Creates a subtle inset box inside a card (useful for previews or secondary groups).
    static func makeInsetBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.masksToBounds = true
        return box
    }
}

// MARK: - View Installation & Invalidation Helpers

@objc extension NSView {
    func it_enclosingProfileFormDocument() -> ProfileFormDocumentView? {
        if let doc = self as? ProfileFormDocumentView {
            return doc
        }
        var current: NSView? = superview
        while let view = current {
            if let doc = view as? ProfileFormDocumentView {
                return doc
            }
            current = view.superview
        }
        return nil
    }

    func it_childProfileFormDocument() -> ProfileFormDocumentView? {
        if let doc = self as? ProfileFormDocumentView {
            return doc
        }
        for subview in subviews {
            if let found = subview.it_childProfileFormDocument() {
                return found
            }
        }
        return nil
    }

    @objc var it_hasProfileForm: Bool {
        it_childProfileFormDocument() != nil
    }

    @objc func it_invalidateProfileFormLayout() {
        if let doc = it_enclosingProfileFormDocument() {
            doc.invalidateFormLayout()
            return
        }
        if let doc = it_childProfileFormDocument() {
            doc.invalidateFormLayout()
        }
    }

    @objc func it_findProfileUnifiedScrollView() -> ProfileUnifiedScrollView? {
        if let scroll = self as? ProfileUnifiedScrollView {
            return scroll
        }
        for subview in subviews {
            if let found = subview.it_findProfileUnifiedScrollView() {
                return found
            }
        }
        return nil
    }

    func it_installInlineProfileForm(_ documentView: ProfileFormDocumentView) {
        autoresizesSubviews = true
        documentView.frame = bounds
        documentView.autoresizingMask = [.width, .height]
        addSubview(documentView)
    }
}
