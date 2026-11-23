import AppKit
import XCTest
@testable import iTerm2SharedARC

final class TerminalTabContainerTests: XCTestCase {
    private func makeBar() -> TerminalTabContainerView {
        let bar = TerminalTabContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let tabs = NSTabView(frame: bar.bounds)
        bar.tabView = tabs
        tabs.delegate = bar
        return bar
    }

    private func pane() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return session
    }

    @discardableResult private func add(_ tab: PTYTab, to bar: TerminalTabContainerView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: tab)
        tab.tabViewItem = item
        bar.tabView!.addTabViewItem(item)
        return item
    }

    func testDetachRebindsTheTabAndItsSessionToTheNewWindow() throws {
        let fixture = TerminalWindowTestFixture()
        defer { fixture.close() }
        let session = fixture.addTab()
        let tab = try XCTUnwrap(session.delegate as? PTYTab)
        let destination = try XCTUnwrap(fixture.terminal.moveTabToDetachedWindow(tab))
        defer { destination.window?.close() }
        XCTAssertEqual(fixture.terminal.tabs()?.count, 1)
        XCTAssertTrue(destination.tabs()?.first === tab)
        let item = try XCTUnwrap(tab.tabViewItem)
        XCTAssertTrue(destination.tabView()?.tabViewItems.first === item)
        XCTAssertTrue(destination.currentSession() === session)
    }

    func testReorderAndTransferPreserveTabAndCellIdentity() throws {
        let bar = makeBar()
        let other = makeBar()
        let first = add(PTYTab(session: pane(), parentWindow: nil), to: bar)
        let second = add(PTYTab(session: pane(), parentWindow: nil), to: bar)
        let third = add(PTYTab(session: pane(), parentWindow: nil), to: bar)
        let cell = try XCTUnwrap(bar.cells().firstObject as? PSMTabBarCell)
        bar.tabView!.selectTabViewItem(second)

        bar.moveTab(at: 0, to: 2)
        XCTAssertEqual(bar.tabView!.tabViewItems, [second, third, first])
        XCTAssertTrue(bar.tabView!.selectedTabViewItem === second)
        bar.moveTab(at: 2, toTabBar: other, at: 0)
        XCTAssertEqual(bar.tabView!.tabViewItems, [second, third])
        XCTAssertTrue(other.tabView!.selectedTabViewItem === first)
        XCTAssertTrue(other.cells().firstObject as? PSMTabBarCell === cell)
        XCTAssertTrue(cell.controlView === other)
        bar.moveTab(at: 8, toTabBar: other, at: 1)
        XCTAssertEqual(other.tabView!.numberOfTabViewItems, 1)
    }

    func testVerticalTreeFollowsSelectionAndSplitHierarchy() throws {
        let bar = makeBar()
        bar.orientation = .verticalOrientation
        let root = NSSplitView(frame: bar.bounds)
        let column = NSSplitView(frame: bar.bounds)
        column.isVertical = true
        let panes = [pane(), pane(), pane()]
        let mapping = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        for (index, session) in panes.enumerated() {
            let view = try XCTUnwrap(session.view)
            mapping.setObject(session, forKey: view)
            (index == 0 ? root : column).addSubview(view)
        }
        root.addSubview(column)
        let tab = try XCTUnwrap(PTYTab(root: root, sessions: mapping))
        let selected = add(tab, to: bar)
        let single = add(PTYTab(session: pane(), parentWindow: nil), to: bar)
        bar.tabView!.selectTabViewItem(selected)
        bar.update(false)
        let scroll = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSScrollView }.first)
        let outline = try XCTUnwrap(scroll.documentView as? NSOutlineView)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(outline.numberOfRows, 4)
        XCTAssertEqual(outline.level(forRow: 3), 1)
        let group = try XCTUnwrap(outline.item(atRow: 1))
        outline.collapseItem(group)
        bar.update(false)
        XCTAssertEqual(outline.numberOfRows, 2)
        let collapsedHeight = scroll.frame.height
        outline.expandItem(group)
        bar.update(false)
        XCTAssertGreaterThan(scroll.frame.height, collapsedHeight)
        outline.selectRowIndexes([3], byExtendingSelection: false)
        XCTAssertTrue(tab.activeSession === panes[2])
        let cells = try XCTUnwrap(bar.cells() as? [PSMTabBarCell])
        XCTAssertLessThanOrEqual(scroll.frame.maxY, cells[1].frame.minY)
        bar.tabView!.selectTabViewItem(single)
        XCTAssertTrue(scroll.isHidden)
        bar.tabView!.selectTabViewItem(selected)
        bar.orientation = .horizontalOrientation
        XCTAssertTrue(scroll.isHidden)
    }

    func testPeerTreeUsesPeerPortToRevealBuriedMember() throws {
        let bar = makeBar()
        bar.orientation = .verticalOrientation
        let leader = pane()
        let peer = pane()
        let tab = try XCTUnwrap(PTYTab(session: leader, parentWindow: nil))
        let port = PTYSessionPeerPort(peers: ["a": iTermPromise(value: leader), "b": iTermPromise(value: peer)],
                                      activeSessionIdentifier: "a", leaderIdentifier: "a")
        add(tab, to: bar)
        bar.update(false)
        let scroll = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSScrollView }.first)
        let outline = try XCTUnwrap(scroll.documentView as? NSOutlineView)
        XCTAssertFalse(scroll.isHidden)
        XCTAssertEqual(outline.numberOfRows, 3)
        outline.selectRowIndexes([2], byExtendingSelection: false)
        XCTAssertEqual(port.activeSessionIdentifier, "b")
    }

    func testWidthsKeepPinnedTabsAndReserveOverflow() {
        let bar = makeBar()
        bar.cellMinWidth = 80
        bar.pinnedTabWidth = 32
        bar.stretchCellsToFit = true
        let cells = (0..<4).map { _ in PSMTabBarCell(controlView: bar)! }
        cells[0].isPinned = true
        let widths = TerminalTabLayout.widths(for: bar, cells: cells, available: 210).map(\.doubleValue)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths.first, 32)
        XCTAssertEqual(widths.reduce(0, +) + 2 * bar.style.intercellSpacing, 210, accuracy: 1)
        XCTAssertEqual(TerminalTabLayout.origins(count: 5, top: 10, height: 20, bottom: 90), [10, 30, 50])
        XCTAssertEqual(TerminalTabLayout.origins(count: 4, top: 10, height: 20, bottom: 90), [10, 30, 50, 70])
        XCTAssertEqual(TerminalTabLayout.origins(count: 4, top: 10, height: 20, bottom: 90,
                                                 showsAddButton: true), [10, 30, 50])
    }
}
