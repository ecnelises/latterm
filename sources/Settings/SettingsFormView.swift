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
            preferredHeight = body.frame.height + 60
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
            heading.frame = NSRect(x: 16, y: bounds.height - 32, width: max(0, bounds.width - 32), height: 18)
            body.frame = NSRect(x: 16, y: 16, width: max(0, bounds.width - 32), height: preferredHeight - 60)
        }

        override func draw(_ dirtyRect: NSRect) {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
            let fill = NSColor.controlBackgroundColor.blended(withFraction: 0.025, of: .labelColor) ?? .controlBackgroundColor
            fill.setFill()
            shape.fill()
            NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
            shape.stroke()
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
            let body = NSView(frame: NSRect(x: 0, y: 0, width: container.bounds.width - 32, height: union.height))
            for (control, rect) in zip(controls, rects) {
                control.removeFromSuperview()
                control.frame = rect.offsetBy(dx: -16, dy: -union.minY)
                body.addSubview(control)
            }
            let section = Section(title: titles[index], body: body)
            sections.append(section)
            addSubview(section)
        }
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsFormView requires existing controls")
    }

    override func layout() {
        super.layout()
        var top = bounds.height - 16
        for section in sections {
            section.frame = NSRect(x: 16, y: top - section.preferredHeight,
                                   width: max(0, bounds.width - 32), height: section.preferredHeight)
            top -= section.preferredHeight + 16
        }
    }
}
