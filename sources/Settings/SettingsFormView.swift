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
        let leading = children.filter { !$0.isHidden }.map { $0.frame.minX }.min() ?? 0
        for view in children {
            var frame = view.frame
            frame.origin.x -= leading
            if let label = view as? NSTextField, !label.isEditable,
               label.alignment == .right {
                label.alignment = .left
                frame.size.width = frame.maxX
                frame.origin.x = 0
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
