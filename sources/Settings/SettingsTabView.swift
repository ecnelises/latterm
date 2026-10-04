import AppKit

/// Keeps tab identities for controller routing and search, while presenting
/// every item as a section in one document. Selection becomes a scroll target.
@objc(iTermSettingsTabView)
final class SettingsTabView: NSTabView {
    private final class Document: NSView {
        override var isFlipped: Bool { true }
    }

    private struct Section {
        let item: NSTabViewItem
        let heading: NSTextField
        let height: CGFloat
        let compactBody: NSView?
        let preferredBodyWidth: CGFloat
        let minimumWidth: CGFloat
    }

    private let scrollView = NSScrollView()
    private let document = Document()
    private var sections: [Section] = []
    @objc private(set) var presentsSections = false

    override func awakeFromNib() {
        super.awakeFromNib()
        tabViewType = .noTabsNoBorder
        drawsBackground = false
    }

    @objc static func presentSections(in root: NSView) {
        if let tabs = root as? SettingsTabView {
            tabs.presentSections()
            return
        }
        for child in root.subviews { presentSections(in: child) }
    }

    /// Run after controllers finish installing their forms and scroll wrappers.
    @objc func presentSections() {
        guard !presentsSections else { return }
        presentsSections = true
        if let parent = superview, parent.subviews.count == 1 {
            frame = parent.bounds
            autoresizingMask = [.width, .height]
        }
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = document
        scrollView.setAccessibilityIdentifier("SettingsSections")
        addSubview(scrollView)
        rebuildSections()
    }

    static func expandSections(in view: NSView) -> CGFloat {
        if let layouts = view as? SettingsArrangementsView { return layouts.preferredHeight }
        if let scroll = view as? SettingsContentView {
            return scroll.expandForSection()
        }
        if let tabs = view as? SettingsTabView {
            tabs.presentSections()
            return tabs.preferredHeight
        }
        var extra: CGFloat = 0
        for child in view.subviews {
            let height = expandSections(in: child)
            extra = max(extra, height - child.frame.height)
        }
        return view.frame.height + extra
    }

    private var preferredHeight: CGFloat {
        sections.reduce(16) { $0 + $1.height + 64 }
    }

    private var preferredWidth: CGFloat {
        (sections.map(\.minimumWidth).max() ?? 0) + 64
    }

    /// Expanded legacy forms must contribute their minimum width to the one
    /// enclosing document. Hiding their own scrollers must not clip controls.
    static func minimumWidth(in view: NSView) -> CGFloat {
        if let scroll = view as? SettingsContentView { return scroll.requiredWidth }
        if let tabs = view as? SettingsTabView { return tabs.preferredWidth }
        return view.subviews.map { $0.frame.minX + minimumWidth(in: $0) }.max() ?? 0
    }

    private func rebuildSections() {
        guard presentsSections else { return }
        let previous = sections
        sections = tabViewItems.compactMap { item in
            guard let view = item.view else { return nil }
            let existing = previous.first { $0.item === item }
            let heading = existing?.heading ?? NSTextField(labelWithString: item.label)
            heading.stringValue = item.label
            heading.font = .systemFont(ofSize: 17, weight: .semibold)
            heading.setAccessibilityIdentifier("SettingsSection.\(indexOfTabViewItem(item))")
            let body = existing?.compactBody ?? compactBody(in: view)
            let height = existing?.height ?? body.map { $0.frame.height + 16 } ?? Self.expandSections(in: view)
            view.autoresizingMask = []
            if let body, existing == nil { SettingsFormView.alignControls(in: body) }
            body?.autoresizingMask = []
            document.addSubview(heading)
            document.addSubview(view)
            let fillsWidth = ["ActionCustomView", "SnippetCustomView"].contains(body?.identifier?.rawValue ?? "")
            let bodyWidth = fillsWidth ? CGFloat.greatestFiniteMagnitude : (body?.frame.width ?? 0)
            let minimumWidth = fillsWidth ? 0 : (body?.frame.width ?? Self.minimumWidth(in: view))
            return Section(item: item, heading: heading, height: height, compactBody: body,
                           preferredBodyWidth: existing?.preferredBodyWidth ?? bodyWidth,
                           minimumWidth: existing?.minimumWidth ?? minimumWidth)
        }
        for old in previous where !tabViewItems.contains(where: { $0 === old.item }) {
            old.heading.removeFromSuperview()
            old.item.view?.removeFromSuperview()
        }
        needsLayout = true
    }

    private func compactBody(in view: NSView) -> NSView? {
        guard view.subviews.count == 1, let body = view.subviews.first else { return nil }
        // These NIB canvases only center a fixed-height group at the top of
        // a full tab page. Drop the unused page padding, keeping every control.
        guard body.isMember(of: NSView.self) ||
                NSStringFromClass(type(of: body)) == "iTermPreferencesInnerTabContainerView" else { return nil }
        return body
    }

    override var contentRect: NSRect {
        presentsSections ? bounds : super.contentRect
    }

    override func selectTabViewItem(_ tabViewItem: NSTabViewItem?) {
        // NSTabView expects to detach its previous item from itself.
        if presentsSections, let previous = selectedTabViewItem?.view,
           previous.superview !== self {
            addSubview(previous)
        }
        super.selectTabViewItem(tabViewItem)
        guard presentsSections else { return }
        // AppKit moves the selected item's view back into the tab view.
        // Restore all sections before laying out or revealing a search target.
        for section in sections {
            if let view = section.item.view, view.superview !== document {
                document.addSubview(view)
            }
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let heading = sections.first(where: { $0.item === tabViewItem })?.heading {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, heading.frame.minY - 16)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
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
        guard presentsSections else { return }
        scrollView.frame = bounds
        document.frame = NSRect(x: 0, y: 0, width: max(scrollView.contentSize.width, preferredWidth),
                                height: max(scrollView.contentSize.height, preferredHeight))
        var top: CGFloat = 16
        for section in sections {
            // A wide legacy section may require horizontal scrolling, but it
            // must not stretch responsive sibling forms beyond the viewport.
            let resizesToViewport = section.item.view?.subviews.first is SettingsContentView
            let sectionWidth = resizesToViewport ? max(section.minimumWidth, scrollView.contentSize.width - 64) :
                max(0, document.bounds.width - 64)
            section.heading.frame = NSRect(x: 32, y: top, width: sectionWidth, height: 24)
            section.item.view?.frame = NSRect(x: 32, y: top + 36,
                                              width: sectionWidth, height: section.height)
            if let body = section.compactBody, let page = section.item.view {
                body.frame = NSRect(x: 0, y: 8,
                                    width: min(section.preferredBodyWidth, page.bounds.width),
                                    height: section.height - 16)
            }
            top += section.height + 64
        }
    }
}
