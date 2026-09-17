import AppKit

/// Keeps preference pages at their required size without resizing the window.
/// On small screens the viewport scrolls; on larger ones it fills the space.
@objc(iTermSettingsContentView)
final class SettingsContentView: NSScrollView {
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }
    private let content: NSView
    private let document = Document()
    private var minimumContentSize = NSSize(width: 760, height: 600)

    @objc init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        documentView = document
        content.removeFromSuperview()
        content.autoresizingMask = []
        document.addSubview(content)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsContentView requires its content")
    }

    @objc func setMinimumContentSize(_ size: NSSize) {
        minimumContentSize = size
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc func scrollToTop() {
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        let size = NSSize(width: max(contentSize.width, minimumContentSize.width),
                          height: max(contentSize.height, minimumContentSize.height))
        document.frame = NSRect(origin: .zero, size: size)
        content.frame = document.bounds
        // A selected page must fill the tab even when the outer size did not
        // change (for example, after a legacy controller resized the page).
        if let tabs = content as? NSTabView {
            tabs.selectedTabViewItem?.view?.frame = tabs.contentRect
        }
    }
}
