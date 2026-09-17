import AppKit

/// A shared page heading keeps the legacy preference panes visually coherent.
@objc(iTermSettingsPageHeaderView)
final class SettingsPageHeaderView: NSView {
    @objc static let preferredHeight: CGFloat = 112
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let scope = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .minYMargin]
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        addSubview(title)
        addSubview(detail)
        scope.font = .systemFont(ofSize: 10, weight: .medium)
        scope.textColor = .secondaryLabelColor
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
        scope.setAccessibilityIdentifier("SettingsScope")
    }

    override func layout() {
        super.layout()
        scope.frame = NSRect(x: 28, y: 81, width: max(0, bounds.width - 56), height: 14)
        title.frame = NSRect(x: 26, y: 42, width: max(0, bounds.width - 52), height: 30)
        detail.frame = NSRect(x: 28, y: 20, width: max(0, bounds.width - 56), height: 17)
    }
}
