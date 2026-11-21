import AppKit

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
