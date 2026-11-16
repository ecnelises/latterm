import AppKit

/// Reorganizes existing preference controls without replacing their bindings,
/// actions, accessibility, or search targets. Compound rows stay intact.
@objc(iTermSettingsFormView)
final class SettingsFormView: NSView {
    private final class Section: NSView {
        let heading: NSTextField
        let body: NSView
        let preferredHeight: CGFloat

        init(title: String, body: NSView) {
            self.body = body
            heading = NSTextField(labelWithString: title)
            preferredHeight = body.frame.height + 44
            super.init(frame: .zero)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            addSubview(heading)
            addSubview(body)
        }

        required init?(coder: NSCoder) {
            it_fatalError("Settings form sections require existing controls")
        }

        override func layout() {
            super.layout()
            heading.frame = NSRect(x: 0, y: bounds.height - 24, width: bounds.width, height: 18)
            body.frame = NSRect(x: 0, y: 8, width: bounds.width, height: preferredHeight - 44)
        }
    }

    private var sections: [Section] = []
    @objc var preferredHeight: CGFloat { sections.reduce(16) { $0 + $1.preferredHeight + 16 } }

    @objc init(container: NSView, titles: [String], groups: [[NSView]]) {
        super.init(frame: container.bounds)
        autoresizingMask = [.width, .height]
        it_assert(titles.count == groups.count, "Every settings group needs a heading")
        // Capture all positions before moving any view out of its NIB parent.
        let frames = groups.map { group in group.map { $0.convert($0.bounds, to: container) } }
        for (index, controls) in groups.enumerated() {
            let rects = frames[index]
            let union = rects.reduce(NSRect.null) { $0.union($1) }
            let body = NSView(frame: NSRect(x: 0, y: 0, width: container.bounds.width, height: union.height))
            for (control, rect) in zip(controls, rects) {
                control.removeFromSuperview()
                control.frame = rect.offsetBy(dx: -16, dy: -union.minY)
                body.addSubview(control)
            }
            Self.alignControls(in: body)
            let section = Section(title: titles[index], body: body)
            sections.append(section)
            addSubview(section)
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsFormView requires existing controls")
    }

    /// Normalize the old NIB label gutter once, retaining control widths and
    /// relative positions within compound rows.
    @objc static func alignControls(in body: NSView) {
        let children = body.subviews
        let hasWideScrollView = children.contains { $0 is NSScrollView && $0.frame.width > body.bounds.width * 0.7 }
        let leading = children.filter { !$0.isHidden }.map { $0.frame.minX }.min() ?? 0
        for view in children {
            var frame = view.frame
            frame.origin.x -= leading
            if !hasWideScrollView && view.autoresizingMask.contains(.minXMargin) {
                // Prevent NIB-era right-pinned controls from drifting horizontally on resize.
                view.autoresizingMask.remove(.minXMargin)
                view.autoresizingMask.insert(.maxXMargin)
            }
            if let label = view as? NSTextField, !label.isEditable {
                let isLeftLabel = label.alignment == .right ||
                    (frame.minX <= 4 && (label.stringValue.hasSuffix(":") || label.stringValue.hasSuffix("：")))
                if isLeftLabel {
                    label.alignment = .left
                    frame.size.width = max(ceil(label.fittingSize.width) + 2, frame.maxX)
                    frame.origin.x = 0
                }
            }
            if let button = view as? NSButton,
               button.bezelStyle != .helpButton,
               !(button is PopoverHelpButton),
               button.frame.height <= 22,
               button.title.count > 0 {
                // Trim padded XIB checkbox widths that would otherwise bloat section widths.
                let fitWidth = ceil(button.fittingSize.width) + 4
                if frame.width > fitWidth && fitWidth > 24 {
                    frame.size.width = fitWidth
                }
            }
            if view is NSScrollView, frame.width > body.bounds.width * 0.7 {
                frame.size.width = max(0, body.bounds.width - frame.minX)
                view.autoresizingMask.insert(.width)
            }
            view.frame = frame
            if view is ModalEnclosure, !view.isHidden {
                // Enclosures preserve visibility/binding behavior, but their
                // old label gutters should not indent a section's labels.
                let inset = view.frame.minX
                let resizesChildren = view.autoresizesSubviews
                view.autoresizesSubviews = false
                view.frame = NSRect(x: 0, y: frame.minY, width: frame.maxX, height: frame.height)
                for child in view.subviews {
                    child.frame.origin.x += inset
                    if let label = child as? NSTextField, !label.isEditable, label.alignment == .right {
                        label.alignment = .left
                        let right = label.frame.maxX
                        label.frame.origin.x = 0
                        label.frame.size.width = right
                    }
                }
                view.autoresizesSubviews = resizesChildren
            }
        }
        guard !hasWideScrollView else { return }
        // Resolve overlapping inline warning icons and wide static labels before popups.
        for view in children {
            if let imageView = view as? NSImageView, imageView.frame.width <= 24 {
                for case let field as NSTextField in children where field.isEditable &&
                        abs(field.frame.midY - imageView.frame.midY) < 10 &&
                        imageView.frame.minX >= field.frame.minX + 60 &&
                        imageView.frame.minX < field.frame.maxX + 4 {
                    var fieldFrame = field.frame
                    fieldFrame.size.width = max(80, imageView.frame.minX - 6 - fieldFrame.minX)
                    field.frame = fieldFrame
                }
            }
            if let label = view as? NSTextField, !label.isEditable, label.frame.minX > 4 {
                for case let popup as NSPopUpButton in children where
                        abs(popup.frame.midY - label.frame.midY) < 10 &&
                        popup.frame.minX > label.frame.minX {
                    let fitLabelW = ceil(label.fittingSize.width) + 2
                    if fitLabelW < label.frame.width - 12 {
                        var labelFrame = label.frame
                        labelFrame.size.width = fitLabelW
                        label.frame = labelFrame
                        var popupFrame = popup.frame
                        popupFrame.origin.x = labelFrame.maxX + 8
                        popupFrame.size.width = min(popupFrame.width, max(120, ceil(popup.fittingSize.width) + 12))
                        popup.frame = popupFrame
                    }
                }
            }
        }
        // Pull overly wide trailing action rows (e.g. External settings) inside narrow panes.
        let rightEdgeLimit: CGFloat = 540
        for view in children where view.frame.maxX > rightEdgeLimit {
            if let button = view as? NSButton, button.frame.height >= 26 {
                let shift = view.frame.maxX - rightEdgeLimit
                var buttonFrame = button.frame
                buttonFrame.origin.x -= shift
                button.frame = buttonFrame
                for sibling in children where sibling !== button &&
                        abs(sibling.frame.midY - buttonFrame.midY) < 12 &&
                        sibling.frame.maxX > buttonFrame.minX - 24 {
                    var f = sibling.frame
                    if sibling is NSImageView && f.width <= 24 {
                        f.origin.x = buttonFrame.minX - 6 - f.width
                        sibling.frame = f
                    } else if let tf = sibling as? NSTextField, tf.isEditable {
                        f.size.width = max(140, buttonFrame.minX - 28 - f.minX)
                        sibling.frame = f
                    } else if sibling is NSPopUpButton {
                        f.size.width = max(120, buttonFrame.minX - 8 - f.minX)
                        sibling.frame = f
                    }
                }
            }
        }
    }

    /// Align the control column across sibling legacy form sections so labels and
    /// controls share a single vertical axis down the page.
    @objc static func unifyFormColumns(in bodies: [NSView]) {
        struct BodyMetrics {
            let body: NSView
            let labels: [NSTextField]
            let controlViews: [NSView]
            let controlMinX: CGFloat
        }
        var parsed: [BodyMetrics] = []
        var maxLabelWidth: CGFloat = 0

        for body in bodies {
            let children = body.subviews
            var labels: [NSTextField] = []
            for case let label as NSTextField in children where !label.isEditable && label.frame.minX <= 2 {
                let hasSiblingControlOnRow = children.contains { sibling in
                    sibling !== label &&
                    abs(sibling.frame.midY - label.frame.midY) < 12 &&
                    sibling.frame.minX >= 60
                }
                if hasSiblingControlOnRow {
                    labels.append(label)
                    maxLabelWidth = max(maxLabelWidth, ceil(label.fittingSize.width))
                }
            }
            let labelIds = Set(labels.map(ObjectIdentifier.init))
            let controlViews = children.filter { !labelIds.contains(ObjectIdentifier($0)) }
            let primaryControls = controlViews.filter { view in
                guard let btn = view as? NSButton else { return true }
                return btn.bezelStyle != .rounded
            }
            guard let controlMinX = (primaryControls.isEmpty ? controlViews : primaryControls)
                    .map({ $0.frame.minX }).min() else {
                continue
            }
            parsed.append(BodyMetrics(body: body,
                                      labels: labels,
                                      controlViews: controlViews,
                                      controlMinX: controlMinX))
        }
        guard !parsed.isEmpty, maxLabelWidth > 0 else { return }

        let targetControlX = max(136, maxLabelWidth + 16)
        for entry in parsed {
            let delta = targetControlX - entry.controlMinX
            for label in entry.labels {
                var frame = label.frame
                frame.origin.x = 0
                frame.size.width = max(ceil(label.fittingSize.width), targetControlX - 12)
                label.frame = frame
            }
            for view in entry.controlViews {
                var frame = view.frame
                frame.origin.x += delta
                view.frame = frame
            }
            let maxX = entry.body.subviews.map { $0.frame.maxX }.max() ?? entry.body.frame.width
            var bodyFrame = entry.body.frame
            bodyFrame.size.width = max(targetControlX + 120, ceil(maxX) + 8)
            entry.body.frame = bodyFrame
        }
    }

    override func layout() {
        super.layout()
        var top = bounds.height - 8
        for section in sections {
            section.frame = NSRect(x: 0, y: top - section.preferredHeight,
                                   width: min(720, bounds.width),
                                   height: section.preferredHeight)
            top -= section.preferredHeight + 16
        }
    }
}

/// A saved layout is a reusable snapshot, rather than a live window preview.
@objc(iTermSettingsArrangementsView)
final class SettingsArrangementsView: NSView {
    private weak var list: NSScrollView?
    private weak var preview: NSView?
    private var actions: [NSView] = []
    private let help = NSTextField(wrappingLabelWithString: NSLocalizedString(
        "Save windows, tabs, and split panes from Window > Save Window Arrangement. Select a layout below to preview it or set the default. To restore it at launch, choose Open Default Window Arrangement in Startup & Exit.",
        comment: "Saved window layout instructions"))
    @objc let preferredHeight: CGFloat = 340

    @objc func configure(list: NSScrollView, preview: NSView, actions: [NSView]) {
        self.list = list
        self.preview = preview
        self.actions = actions
        autoresizesSubviews = false
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        addSubview(help)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let list, let preview else { return }
        let listWidth: CGFloat = 220
        help.frame = NSRect(x: 0, y: bounds.height - 56, width: bounds.width, height: 48)
        let height = max(0, bounds.height - 104)
        list.frame = NSRect(x: 0, y: 40, width: listWidth, height: height)
        preview.frame = NSRect(x: listWidth + 24, y: 40,
                               width: max(0, bounds.width - listWidth - 24), height: height)
        var x: CGFloat = 0
        for action in actions {
            action.frame = NSRect(x: x, y: 0, width: max(72, action.frame.width), height: 28)
            x = action.frame.maxX + 8
        }
    }
}
