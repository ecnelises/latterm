import AppKit

/// A shared page heading keeps the legacy preference panes visually coherent.
@objc(iTermSettingsPageHeaderView)
final class SettingsPageHeaderView: NSView {
    @objc static let preferredHeight: CGFloat = 104
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let scope = NSTextField(labelWithString: "")
    private var scopeFrame = NSRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .minYMargin]
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        addSubview(title)
        addSubview(detail)
        scope.font = .systemFont(ofSize: 11, weight: .medium)
        scope.textColor = .secondaryLabelColor
        scope.lineBreakMode = .byTruncatingTail
        addSubview(scope)
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsPageHeaderView must be created programmatically")
    }

    @objc func showPage(_ page: SettingsPage) {
        title.stringValue = page.title
        detail.stringValue = page.subtitle
        detail.toolTip = page.subtitle
        scope.stringValue = page.scope
        scope.toolTip = page.scope
        scope.setAccessibilityIdentifier("SettingsScope")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let available = max(0, bounds.width - 56)
        // Leave room for NSTextField's text inset as well as the badge padding.
        let scopeWidth = min(ceil(scope.intrinsicContentSize.width) + 28, available * 0.4)
        scopeFrame = NSRect(x: bounds.width - 28 - scopeWidth, y: 57, width: scopeWidth, height: 24)
        scope.frame = scopeFrame.insetBy(dx: 10, dy: 4)
        title.frame = NSRect(x: 26, y: 51, width: max(0, scopeFrame.minX - 42), height: 32)
        title.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x: 28, y: 25, width: available, height: 18)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: scopeFrame, xRadius: 6, yRadius: 6).fill()
    }
}
