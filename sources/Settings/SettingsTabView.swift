import AppKit

/// A flat, wrapping section picker over the existing tab items. Keeping the
/// NSTabView and its delegate preserves deep links and preference bindings.
@objc(iTermSettingsTabView)
final class SettingsTabView: NSTabView {
    private var ready = false
    private var buttons: [NSButton] = []
    private let sectionFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    override func awakeFromNib() {
        super.awakeFromNib()
        tabViewType = .noTabsNoBorder
        drawsBackground = false
        ready = true
        rebuildSections()
    }

    private func sectionFrames() -> [NSRect] {
        let inset: CGFloat = 32
        let available = max(1, bounds.width - inset * 2)
        var x = inset
        var y: CGFloat = 12
        return tabViewItems.map { item in
            let titleWidth = (item.label as NSString).size(withAttributes: [.font: sectionFont]).width
            let width = min(available, ceil(titleWidth) + 24)
            if x > inset && x + width > bounds.width - inset {
                x = inset
                y += 36
            }
            let frame = NSRect(x: x, y: isFlipped ? y : bounds.height - y - 30, width: width, height: 30)
            x += width + 4
            return frame
        }
    }

    override var contentRect: NSRect {
        guard ready else { return super.contentRect }
        let last = sectionFrames().last
        let inset = last.map { isFlipped ? $0.maxY + 12 : bounds.height - $0.minY + 12 } ?? 0
        return NSRect(x: 0, y: isFlipped ? inset : 0, width: bounds.width, height: max(0, bounds.height - inset))
    }

    private func rebuildSections() {
        guard ready else { return }
        buttons.forEach { $0.removeFromSuperview() }
        buttons = tabViewItems.enumerated().map { index, item in
            let button = NSButton(title: item.label, target: self, action: #selector(selectSection(_:)))
            button.tag = index
            button.setButtonType(.pushOnPushOff)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.toolTip = item.label
            button.setAccessibilityLabel(item.label)
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityIdentifier("SettingsSection.\(index)")
            addSubview(button)
            return button
        }
        updateSelection()
        needsLayout = true
    }

    @objc private func selectSection(_ sender: NSButton) {
        selectTabViewItem(at: sender.tag)
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() where tabViewItems.indices.contains(index) {
            let selected = tabViewItems[index] === selectedTabViewItem
            button.state = selected ? .on : .off
            button.attributedTitle = NSAttributedString(string: tabViewItems[index].label, attributes: [
                .font: sectionFont,
                .foregroundColor: selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            ])
            button.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor : nil
        }
    }

    override func selectTabViewItem(_ tabViewItem: NSTabViewItem?) {
        super.selectTabViewItem(tabViewItem)
        if ready { updateSelection(); needsLayout = true }
    }

    override func insertTabViewItem(_ tabViewItem: NSTabViewItem, at index: Int) {
        super.insertTabViewItem(tabViewItem, at: index)
        rebuildSections()
    }

    override func removeTabViewItem(_ tabViewItem: NSTabViewItem) {
        super.removeTabViewItem(tabViewItem)
        rebuildSections()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (button, frame) in zip(buttons, sectionFrames()) { button.frame = frame }
        selectedTabViewItem?.view?.frame = contentRect
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if ready { updateSelection() }
    }
}
