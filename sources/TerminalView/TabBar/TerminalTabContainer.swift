import AppKit

/// Sizes the visible prefix of NSTabView's items. The caller reserves the
/// accessory margins, including the overflow button, before asking for widths.
@objc final class TerminalTabLayout: NSObject {
    @objc(widthsForBar:cells:available:)
    static func widths(for bar: TerminalTabBarView, cells: [PSMTabBarCell], available: CGFloat) -> [NSNumber] {
        guard !cells.isEmpty, available > 0 else { return [] }
        let gap = max(0, bar.style.intercellSpacing)
        let minimum = max(1, CGFloat(bar.cellMinWidth))
        let pinned = max(1, CGFloat(bar.pinnedTabWidth))
        let optimum = max(minimum, CGFloat(bar.cellOptimumWidth))
        let maximum = max(minimum, CGFloat(bar.cellMaxWidth))
        if bar.sizeCellsToFit {
            let widths = cells.map { $0.isPinned ? pinned : min(maximum, max(minimum, CGFloat($0.desiredWidthOfCell))) }
            if widths.reduce(0, +) + CGFloat(cells.count - 1) * gap <= available {
                return widths.map { NSNumber(value: Double($0)) }
            }
        }

        var remaining = available
        var count = 0
        var pinnedCount = 0
        for cell in cells {
            let required = (cell.isPinned ? pinned : minimum) + (count == 0 ? 0 : gap)
            guard remaining >= required else { break }
            remaining -= required
            count += 1
            if cell.isPinned { pinnedCount += 1 }
        }
        let regular = count - pinnedCount
        let scale = bar.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let room = available - CGFloat(pinnedCount) * pinned - CGFloat(max(0, count - 1)) * gap
        let fill = bar.stretchCellsToFit || CGFloat(regular) * optimum > room || count < cells.count
        let pixels = Int((max(0, room) * scale).rounded())
        var ordinal = 0
        return cells.prefix(count).map { cell in
            if cell.isPinned { return NSNumber(value: Double(pinned)) }
            defer { ordinal += 1 }
            let width = fill ? CGFloat(pixels / regular + (ordinal < pixels % regular ? 1 : 0)) / scale : optimum
            return NSNumber(value: Double(width))
        }
    }

    @objc(originsForCount:top:height:bottom:showsAddButton:)
    static func origins(count: Int, top: CGFloat, height: CGFloat, bottom: CGFloat, showsAddButton: Bool = false) -> [NSNumber] {
        guard height > 0 else { return [] }
        let slots = max(0, Int(floor((bottom - top) / height)))
        let visible = min(count, max(0, slots - (showsAddButton || slots < count ? 1 : 0)))
        return (0..<visible).map { NSNumber(value: Double(top + CGFloat($0) * height)) }
    }
}

private final class TabDropMarker: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        bounds.fill()
    }
}

/// AppKit owns the drag image and its lifetime. The tab item is retained by
/// identity until the session ends, even when its source window closes.
@objc final class TerminalTabDrag: NSObject {
    @objc static let shared = TerminalTabDrag()
    @objc private(set) var item: NSTabViewItem?
    @objc private(set) var isDropping = false
    @objc var isDragging: Bool { item != nil }
    private var source: TerminalTabBarView?
    private weak var destination: TerminalTabBarView?
    private let marker = TabDropMarker()
    private var windowOffset = NSSize.zero
    private var escapeMonitor: Any?
    private var cancelled = false

    @objc(beginFrom:cell:event:)
    func begin(from bar: TerminalTabBarView, cell: PSMTabBarCell, event: NSEvent) {
        guard !isDragging, let tabItem = cell.representedObject as? NSTabViewItem,
              let window = bar.window, !cell.frame.isEmpty,
              let bitmap = bar.bitmapImageRepForCachingDisplay(in: cell.frame) else { return }
        bar.cacheDisplay(in: cell.frame, to: bitmap)
        let image = NSImage(size: cell.frame.size)
        image.addRepresentation(bitmap)
        source = bar
        item = tabItem
        cancelled = false
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        windowOffset = NSSize(width: mouse.x - window.frame.minX, height: mouse.y - window.frame.maxY)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] key in
            if key.keyCode == 53 { self?.cancelled = true }
            return key
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("tab", forType: .TerminalTabPasteboardType)
        let drag = NSDraggingItem(pasteboardWriter: pasteboardItem)
        drag.setDraggingFrame(cell.frame, contents: image)
        NotificationCenter.default.post(name: .PSMTabDragDidBegin, object: nil)
        bar.beginDraggingSession(with: [drag], event: event, source: bar).animatesToStartingPositionsOnCancelOrFail = true
    }

    private func isTab(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(.TerminalTabPasteboardType) == true
    }

    private func insertion(in bar: TerminalTabBarView, sender: NSDraggingInfo) -> Int {
        let point = bar.convert(sender.draggingLocation, from: nil)
        let vertical = bar.orientation == .verticalOrientation
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        let visible = cells.prefix { !$0.isInOverflowMenu }
        let index = visible.firstIndex { vertical ? point.y < $0.frame.midY : point.x < $0.frame.midX } ?? visible.endIndex
        let boundary = cells.prefix { $0.isPinned }.count
        if let item, let source, source.isPinned(for: item) {
            return min(index, boundary)
        }
        if let pane = MovePaneController.sharedInstance().session, let view = pane.view,
           sender.draggingSource as? SessionView === view,
           let tab = pane.delegate as? PTYTab, tab.isPinned, tab.sessions()?.count == 1,
           let tabs = bar.tabView, tab.tabViewItem?.tabView === tabs {
            return min(index, boundary)
        }
        return max(index, boundary)
    }

    @objc(updateDestination:sender:)
    func update(destination bar: TerminalTabBarView, sender: NSDraggingInfo) -> NSDragOperation {
        guard let tabs = bar.tabView else { return [] }
        if isTab(sender) {
            guard let source, sender.draggingSource as? TerminalTabBarView === source,
                  let from = source.tabView, let item,
                  from.indexOfTabViewItem(item) != NSNotFound,
                  bar.delegate?.tabView?(from, shouldDrop: item, inTabBar: bar, moveSourceWindow: nil) != false else {
                exit(destination: bar)
                return []
            }
        } else {
            guard sender.draggingSource != nil,
                  sender.draggingPasteboard.types?.contains(.iTermMovePaneDragType) == true,
                  bar.delegate?.tabView?(tabs, shouldAcceptDragFromSender: sender) == true,
                  bar.delegate?.tabView?(tabs, draggingEnteredTabBarForSender: sender) != [] else { return [] }
        }
        destination = bar
        let index = insertion(in: bar, sender: sender)
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        let next = cells.indices.contains(index) && !cells[index].isInOverflowMenu ? cells[index].frame : nil
        let last = cells.last { !$0.isInOverflowMenu }?.frame ?? .zero
        if bar.orientation == .verticalOrientation {
            marker.frame = NSRect(x: 0, y: max(0, (next?.minY ?? last.maxY) - 1), width: bar.bounds.width, height: 2)
        } else {
            marker.frame = NSRect(x: max(0, (next?.minX ?? last.maxX) - 1), y: 0, width: 2, height: bar.height)
        }
        if marker.superview !== bar { bar.addSubview(marker) }
        return .move
    }

    @objc(exitDestination:)
    func exit(destination bar: TerminalTabBarView) {
        guard destination === bar else { return }
        destination = nil
        marker.removeFromSuperview()
        if source === bar { bar.dragWillExitTabBar() }
    }

    @objc(dropIn:sender:)
    func drop(in bar: TerminalTabBarView, sender: NSDraggingInfo) -> Bool {
        guard update(destination: bar, sender: sender) == .move, let tabs = bar.tabView else { return false }
        let index = insertion(in: bar, sender: sender)
        isDropping = true
        defer {
            isDropping = false
            marker.removeFromSuperview()
            destination = nil
        }
        if let source, let from = source.tabView, let item, isTab(sender) {
            let at = from.indexOfTabViewItem(item)
            guard at != NSNotFound else { return false }
            if source === bar {
                let target = index > at ? index - 1 : index
                if target != at {
                    source.delegate?.tabView?(from, willDrop: item, inTabBar: bar)
                    source.moveTab(at: at, to: target)
                    source.delegate?.tabView?(from, didDrop: item, inTabBar: bar)
                }
                tabs.selectTabViewItem(item)
            } else {
                source.moveTab(at: at, toTabBar: bar, at: index)
            }
        } else {
            // Detaching the last pane can remove its old tab synchronously.
            // Anchor to the following tab identities before invoking the delegate.
            let following = tabs.tabViewItems.dropFirst(index)
            guard let newItem = bar.delegate?.tabView?(tabs, unknownObjectWasDropped: sender) else {
                // tmux arranges the new tab asynchronously.
                return true
            }
            let current = tabs.tabViewItems
            let target = following.first(where: current.contains).flatMap(current.firstIndex(of:)) ?? current.count
            tabs.insertTabViewItem(newItem, at: target)
            tabs.selectTabViewItem(newItem)
        }
        return true
    }

    @objc(endAt:operation:)
    func end(at point: NSPoint, operation: NSDragOperation) {
        guard let source, let item else { return }
        defer {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            marker.removeFromSuperview()
            source.dragDidFinish()
            self.source = nil
            self.item = nil
            destination = nil
            NotificationCenter.default.post(name: .PSMTabDragDidEnd, object: nil)
        }
        guard let tabs = source.tabView, operation.isEmpty, !cancelled, NSEvent.pressedMouseButtons == 0,
              destination == nil, !source.isPinned(for: item) else { return }
        if let window = source.window,
           source.bounds.contains(source.convert(window.convertPoint(fromScreen: point), from: nil)) { return }
        let index = tabs.indexOfTabViewItem(item)
        guard index != NSNotFound else { return }
        let origin = NSPoint(x: point.x - windowOffset.width, y: point.y - windowOffset.height)
        var moveWindow = ObjCBool(false)
        if source.delegate?.tabView?(tabs, shouldDrop: item, inTabBar: nil, moveSourceWindow: &moveWindow) == true,
           let target = source.delegate?.tabView?(tabs, newTabBarForDraggedTabViewItem: item, at: origin) {
            isDropping = true
            source.moveTab(at: index, toTabBar: target, at: 0)
            isDropping = false
            target.window?.makeKeyAndOrderFront(nil)
        } else if moveWindow.boolValue {
            source.window?.setFrameTopLeftPoint(origin)
        }
    }
}

/// The titlebar and the terminal root host this same view. A side-mounted
/// bar inserts the selected tab’s split hierarchy immediately below its tab.
@objc(TerminalTabContainerView)
final class TerminalTabContainerView: iTermTabBarControlView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Branch: NSObject {
        let title: String
        let identity: ObjectIdentifier
        weak var session: PTYSession?
        weak var port: PTYSessionPeerPort?
        let peerID: String?
        let children: [Branch]

        init(_ title: String, owner: AnyObject, session: PTYSession? = nil,
             port: PTYSessionPeerPort? = nil, peerID: String? = nil, children: [Branch] = []) {
            self.title = title
            identity = ObjectIdentifier(owner)
            self.session = session
            self.port = port
            self.peerID = peerID
            self.children = children
        }

        func matches(_ other: Branch) -> Bool {
            identity == other.identity && title == other.title && peerID == other.peerID &&
                port === other.port && children.elementsEqual(other.children) { $0.matches($1) }
        }
    }

    private var roots = [Branch]()
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var syncing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.focusRingType = .none
        outline.indentationPerLevel = 10
        outline.rowHeight = 20
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.backgroundColor = .clear
        outline.delegate = self
        outline.dataSource = self
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = outline
        scroll.isHidden = true
        addSubview(scroll)
        for name in [Notification.Name("iTermNumberOfSessionsDidChange"), Notification.Name(iTermSessionBecameKey)] {
            NotificationCenter.default.addObserver(self, selector: #selector(panesChanged), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func panesChanged() {
        if orientation == .verticalOrientation { setNeedsUpdate(true) }
    }

    private func branches(in view: NSView, tab: PTYTab, root: Bool = false) -> [Branch] {
        if let pane = view as? SessionView, let session = tab.session(for: pane) {
            let port = session.peerPort
            let group = port as? iTermWorkgroupPeerPort
            let peers = port?.realizedMembers.sorted {
                let a = group?.position(forPeerID: $0.id) ?? 0
                let b = group?.position(forPeerID: $1.id) ?? 0
                return a == b ? $0.id < $1.id : a < b
            }.map {
                Branch(group?.label(forPeerID: $0.id) ?? $0.session.name, owner: $0.session,
                       session: $0.session, port: port, peerID: $0.id)
            } ?? []
            return [Branch(session.name, owner: pane, session: session, children: peers.count > 1 ? peers : [])]
        }
        guard let split = view as? NSSplitView else { return [] }
        let children = split.subviews.flatMap { branches(in: $0, tab: tab) }
        if root || children.count < 2 { return children }
        let title = split.isVertical ? NSLocalizedString("Columns", comment: "Side-by-side terminal panes") :
            NSLocalizedString("Rows", comment: "Stacked terminal panes")
        return [Branch(title, owner: split, children: children)]
    }

    override func update(_ animated: Bool) {
        if orientation != .verticalOrientation { scroll.isHidden = true }
        super.update(animated)
    }

    override func verticalOrigins(for cells: [PSMTabBarCell]) -> [NSNumber] {
        let normal = super.verticalOrigins(for: cells)
        guard let selected = tabView?.selectedTabViewItem, let tab = selected.identifier as? PTYTab,
              let index = cells.firstIndex(where: { $0.representedObject as AnyObject? === selected }),
              index < normal.count, let root = tab.rootView else {
            scroll.isHidden = true
            return normal
        }
        let branches = branches(in: root, tab: tab, root: true)
        syncing = true
        defer { syncing = false }
        if !roots.elementsEqual(branches, by: { $0.matches($1) }) {
            let collapsed = Set((0..<outline.numberOfRows).compactMap { row -> ObjectIdentifier? in
                guard let node = outline.item(atRow: row) as? Branch, !node.children.isEmpty,
                      !outline.isItemExpanded(node) else { return nil }
                return node.identity
            })
            roots = branches
            outline.reloadData()
            outline.expandItem(nil, expandChildren: true)
            for row in (0..<outline.numberOfRows).reversed() {
                if let node = outline.item(atRow: row) as? Branch, collapsed.contains(node.identity) {
                    outline.collapseItem(node)
                }
            }
        }
        guard branches.count > 1 || branches.first?.children.isEmpty == false else {
            scroll.isHidden = true
            return normal
        }
        let top = CGFloat(normal[index].doubleValue) + height
        let rowHeight = outline.rowHeight + outline.intercellSpacing.height
        let wanted = min(CGFloat(outline.numberOfRows) * rowHeight, bounds.height / 2)
        let lastTabEnd = CGFloat(normal.last?.doubleValue ?? 0) + height
        let needsAccessory = showAddTabButton || normal.count < cells.count || lastTabEnd + wanted > bounds.height
        let bottom = bounds.height - (needsAccessory ? height : 0)
        let size = min(wanted, bottom - top)
        guard size >= rowHeight else {
            scroll.isHidden = true
            return normal
        }
        scroll.frame = NSRect(x: 4, y: top, width: max(0, bounds.width - 8), height: size)
        scroll.isHidden = false
        let focused = (0..<outline.numberOfRows).last {
            guard let node = outline.item(atRow: $0) as? Branch else { return false }
            return node.session != nil && node.session === tab.activeSession
        }
        if let focused, outline.selectedRow != focused {
            outline.selectRowIndexes(IndexSet(integer: focused), byExtendingSelection: false)
        }
        return normal.enumerated().compactMap { offset, y in
            let origin = y.doubleValue + (offset <= index ? 0 : Double(size))
            return origin + height <= bottom ? NSNumber(value: origin) : nil
        }
    }

    override func accessibilityChildren() -> [Any]? {
        let tabs = super.accessibilityChildren() ?? []
        return scroll.isHidden ? tabs : tabs + [outline]
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Branch)?.children.count ?? roots.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Branch)?.children ?? roots)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Branch)?.children.isEmpty == false
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Branch else { return nil }
        let id = NSUserInterfaceItemIdentifier("paneLabel")
        let label = outlineView.makeView(withIdentifier: id, owner: self) as? NSTextField ??
            NSTextField(labelWithString: "")
        label.identifier = id
        label.stringValue = node.title
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? Branch)?.session != nil
    }
    func outlineViewItemDidExpand(_ notification: Notification) {
        if !syncing { setNeedsUpdate(true) }
    }
    func outlineViewItemDidCollapse(_ notification: Notification) {
        if !syncing { setNeedsUpdate(true) }
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let tab = tabView?.selectedTabViewItem?.identifier as? PTYTab,
              let node = outline.item(atRow: outline.selectedRow) as? Branch,
              let session = node.session else { return }
        if let id = node.peerID {
            guard let port = node.port, tab.sessions().contains(where: { $0.peerPort === port }),
                  port.activate(identifier: id) else { return }
        }
        if tab.sessions().contains(where: { $0 === session }) {
            tab.activeSession = session
            tab.restoreFirstResponderAfterViewHierarchyRebuild()
        }
    }
}

@objc final class TerminalTabOrdering: NSObject {
    @objc(synchronize:with:)
    static func synchronize(_ bar: TerminalTabBarView, with tabs: NSTabView) {
        let items = tabs.tabViewItems
        let current = Set(items)
        let cells = bar.cells() as? [PSMTabBarCell] ?? []
        var represented = Set<NSTabViewItem>()
        for cell in cells {
            guard let item = cell.representedObject as? NSTabViewItem else { continue }
            if current.contains(item) {
                represented.insert(item)
            } else {
                bar.delegate?.tabView?(tabs, didClose: item)
                bar.removeTab(for: cell)
            }
        }
        for (index, item) in items.enumerated() where !represented.contains(item) {
            bar.addCell(for: item, at: UInt(index))
        }
        bar.delegate?.tabViewDidChangeNumberOfTabViewItems?(tabs)
    }

    @objc(moveIn:from:to:)
    static func move(in bar: TerminalTabBarView, from index: Int, to destination: Int) {
        guard let tabs = bar.tabView, index != destination,
              tabs.tabViewItems.indices.contains(index), tabs.tabViewItems.indices.contains(destination),
              bar.cells().count == tabs.numberOfTabViewItems else { return }
        let item = tabs.tabViewItem(at: index)
        let selected = tabs.selectedTabViewItem
        let delegate = tabs.delegate
        // A reorder is one change. PTYTabView's insertion/removal callbacks
        // transfer window ownership and must only run for cross-window moves.
        tabs.delegate = nil
        tabs.removeTabViewItem(item)
        tabs.insertTabViewItem(item, at: destination)
        let cells = bar.cells()
        let cell = cells.object(at: index)
        cells.removeObject(at: index)
        cells.insert(cell, at: destination)
        tabs.delegate = delegate
        if let selected, tabs.selectedTabViewItem !== selected { tabs.selectTabViewItem(selected) }
        bar.update(true)
    }

    @objc(transferFrom:index:to:index:)
    static func transfer(from source: TerminalTabBarView, index: Int, to target: TerminalTabBarView, at position: Int) {
        guard source !== target, let from = source.tabView, let to = target.tabView,
              from.tabViewItems.indices.contains(index), (0...to.numberOfTabViewItems).contains(position),
              source.cells().count == from.numberOfTabViewItems, target.cells().count == to.numberOfTabViewItems,
              let cell = source.cells()[index] as? PSMTabBarCell else { return }
        let item = from.tabViewItem(at: index)
        target.cells().insert(cell, at: position)
        cell.controlView = target
        source.removeTab(for: cell)
        source.delegate?.tabView?(from, willDrop: item, inTabBar: target)
        from.removeTabViewItem(item)
        to.insertTabViewItem(item, at: position)
        target.initializeState(for: cell)
        target.bindProperties(for: cell, andTabViewItem: item)
        to.selectTabViewItem(item)
        source.delegate?.tabView?(from, didDrop: item, inTabBar: target)
        if from.numberOfTabViewItems == 0 {
            source.delegate?.tabView?(from, closeWindowForLast: item)
        }
    }
}
