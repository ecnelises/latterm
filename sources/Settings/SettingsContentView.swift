import AppKit

/// Fits preference pages to the window above a readable minimum width.
/// Smaller viewports scroll while the window keeps its chosen size.
@objc(iTermSettingsContentView)
final class SettingsContentView: NSScrollView {
    @objc static let minimumPageWidth: CGFloat = 760
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }
    private let content: NSView
    private let document = Document()
    private var minimumContentSize = NSSize(width: minimumPageWidth, height: 600)
    private var fitsViewport = false
    var requiredWidth: CGFloat { fitsViewport ? 0 : minimumContentSize.width }

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

    @objc func setFitsViewport(_ fits: Bool) {
        fitsViewport = fits
        hasVerticalScroller = !fits
        hasHorizontalScroller = !fits
        horizontalScrollElasticity = fits ? .none : .automatic
        verticalScrollElasticity = fits ? .none : .automatic
        if fits {
            minimumContentSize = .zero
            scrollToTop()
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        if fitsViewport {
            return
        }
        super.scrollWheel(with: event)
    }

    @objc func setMinimumContentSize(_ size: NSSize) {
        if fitsViewport {
            minimumContentSize = .zero
            needsLayout = true
            return
        }
        minimumContentSize = size
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func expandForSection() -> CGFloat {
        hasVerticalScroller = false
        hasHorizontalScroller = false
        let height = SettingsTabView.expandSections(in: content)
        minimumContentSize.width = max(minimumContentSize.width, SettingsTabView.minimumWidth(in: content))
        minimumContentSize.height = max(minimumContentSize.height, height)
        return minimumContentSize.height
    }

    @objc func scrollToTop() {
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        let size: NSSize
        if fitsViewport {
            size = contentSize
        } else {
            size = NSSize(width: max(contentSize.width, minimumContentSize.width),
                          height: max(contentSize.height, minimumContentSize.height))
        }
        document.frame = NSRect(origin: .zero, size: size)
        content.frame = document.bounds
        // A selected page must fill the tab even when the outer size did not
        // change (for example, after a legacy controller resized the page).
        if let tabs = content as? NSTabView {
            tabs.selectedTabViewItem?.view?.frame = tabs.contentRect
        }
    }
}
