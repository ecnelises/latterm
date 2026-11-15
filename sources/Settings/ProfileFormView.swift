//
//  ProfileFormView.swift
//  iTerm2SharedARC
//
//  Profile form descriptors, editor adapters, and scroll primitives for Settings > Profiles.
//

import AppKit
import SwiftUI
import BetterFontPicker
import ColorPicker

@objc(iTermProfileFormDocumentProtocol)
protocol ProfileFormDocumentProtocol: AnyObject {
    @objc func updateFormLayout(forWidth width: CGFloat)
    @objc func invalidateFormLayout()
    @objc func markDirtyWithoutPropagating()
    @objc var computedHeight: CGFloat { get }
}

enum ProfileFormMetrics {
    static let wideThreshold: CGFloat = 580
    static let maxFormWidth: CGFloat = 800
    static let outerPaddingWide: CGFloat = 20
    static let outerPaddingCompact: CGFloat = 14
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
            if let scroll = view as? ProfileUnifiedScrollView { return scroll }
            if let scroll = view as? NSScrollView,
               scroll.accessibilityIdentifier() == "SettingsSections" { return scroll }
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
    let id = UUID()
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

    func prepareForRendering(inVisibleSection visibleSection: Bool) {
        let visible = visibleSection && currentlyVisible()
        hostView.isHidden = !visible
        if !visible {
            // Removed SwiftUI rows still retain their editors for the next reveal.
            // Keep those editors under a hidden owner for focus and accessibility.
            attachOwnedViews()
        }
    }

    private func attachOwnedViews() {
        for view in allViews where view.superview !== hostView {
            view.removeFromSuperview()
            view.autoresizingMask = []
            hostView.addSubview(view)
        }
    }

}

// MARK: - Section Card Container

/// Data for one SwiftUI form group; it no longer owns an AppKit layout.
final class ProfileSectionCard: NSObject {

    let titleLabel: NSTextField?
    let headerAccessory: NSView?
    let footerLabel: NSTextField?
    let backingEnclosure: NSView?
    let visibilityPredicate: (() -> Bool)?
    let rows: [ProfileFormRow]

    var isFormVisible: Bool {
        (visibilityPredicate?() ?? true) && !(backingEnclosure?.isHidden ?? false) && rows.contains { $0.currentlyVisible() }
    }

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
        super.init()
    }
}

// MARK: - Form Document View

@objc(iTermProfileFormDocumentView)
final class ProfileFormDocumentView: NSView, ProfileFormDocumentProtocol {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    private let sections: [ProfileSectionCard]
    var formSections: [ProfileSectionCard] { sections }
    var workspaceGroups: [ProfileTaskSection] = []
    var usesWorkspacePresentation = false {
        didSet {
            guard usesWorkspacePresentation, !oldValue else { return }
            hosting.rootView = ProfileSwiftUIForm(sections: [], width: 1)
            hosting.view.removeFromSuperview()
        }
    }
    var onInvalidation: (() -> Void)?
    var hasVisibleFormRows: Bool { sections.contains { $0.isFormVisible } }
    private let hosting: NSHostingController<ProfileSwiftUIForm>
    private var legacyViewsToHide: [NSView]
    private(set) var computedHeight: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = -1
    private var layoutDirty = true
    private var formRevision = 0

    init(sections: [ProfileSectionCard], legacyViewsToHide: [NSView] = []) {
        self.sections = sections
        self.hosting = NSHostingController(rootView: ProfileSwiftUIForm(sections: sections, width: 600))
        self.legacyViewsToHide = legacyViewsToHide
        super.init(frame: .zero)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = false
        hosting.view.autoresizingMask = []
        hosting.view.setAccessibilityIdentifier("ProfileSwiftUIForm")
        addSubview(hosting.view)
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
        onInvalidation?()
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
            if let tabs = view as? SettingsTabView { tabs.needsLayout = true }
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
        if usesWorkspacePresentation {
            hosting.view.isHidden = true
            computedHeight = 0
            return
        }
        if !layoutDirty && abs(width - lastLaidOutWidth) <= 0.25 {
            return
        }
        layoutDirty = false
        lastLaidOutWidth = width

        for section in sections {
            let visible = section.isFormVisible
            for row in section.rows { row.prepareForRendering(inVisibleSection: visible) }
        }
        formRevision += 1
        hosting.rootView = ProfileSwiftUIForm(sections: sections, width: width, revision: formRevision)
        let size = hosting.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude))
        computedHeight = sections.contains { $0.isFormVisible } ? ceil(size.height) : 0
        hosting.view.frame = NSRect(x: 0, y: 0, width: width, height: computedHeight)
        hosting.view.layoutSubtreeIfNeeded()
        window?.recalculateKeyViewLoop()
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
    func it_workspacePath(forControl control: NSView) -> [String]? {
        guard let doc = it_childProfileFormDocument() else { return nil }
        for record in doc.workspaceGroups {
            for row in record.section.rows where row.allViews.contains(where: { $0 === control || control.isDescendant(of: $0) }) {
                return [record.task.title, record.section.titleLabel?.stringValue ?? ""].filter { !$0.isEmpty }
            }
        }
        return nil
    }

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
