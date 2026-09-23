import AppKit

/// A shared large title anchors each preference page.
@objc(iTermSettingsPageHeaderView)
final class SettingsPageHeaderView: NSView {
    @objc static let preferredHeight: CGFloat = 84
    private let title = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .minYMargin]
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsPageHeaderView must be created programmatically")
    }

    @objc func showPage(_ page: SettingsPage) {
        title.stringValue = page.title
        title.toolTip = page.title
        needsLayout = true
    }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 32, y: 20, width: max(0, bounds.width - 64), height: 40)
    }
}
