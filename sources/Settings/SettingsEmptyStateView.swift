import AppKit

/// Guidance inside an empty list, sized with the scroll viewport rather than
/// the table document. The hidden view never intercepts populated rows.
@objc(iTermSettingsEmptyStateView)
final class SettingsEmptyStateView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    @objc var onAction: (() -> Void)?

    @objc init(scrollView: NSScrollView) {
        super.init(frame: scrollView.contentView.bounds)
        autoresizingMask = [.width, .height]
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.alignment = .center
        heading.lineBreakMode = .byTruncatingTail
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(activate)
        [heading, message, button].forEach { addSubview($0) }
        isHidden = true
        scrollView.contentView.addSubview(self)
        setAccessibilityIdentifier("SettingsEmptyState")
    }

    required init?(coder: NSCoder) { it_fatalError("Empty list guidance requires a scroll view") }

    @objc func show(title: String, message: String, actionTitle: String?) {
        heading.stringValue = title
        heading.toolTip = title
        self.message.stringValue = message
        button.title = actionTitle ?? ""
        button.isHidden = actionTitle == nil
        isHidden = false
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(0, min(400, bounds.width - 32))
        let x = bounds.midX - width / 2
        let height: CGFloat = button.isHidden ? 68 : 108
        let top = bounds.midY + height / 2
        heading.frame = NSRect(x: x, y: top - 22, width: width, height: 22)
        message.frame = NSRect(x: x, y: top - 66, width: width, height: 38)
        button.frame = NSRect(x: bounds.midX - 90, y: top - 108, width: 180, height: 32)
    }

    @objc private func activate() { onAction?() }
}
