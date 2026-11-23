import XCTest
@testable import iTerm2SharedARC

@MainActor
final class MovePaneControllerTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private let controller = MovePaneController.sharedInstance()

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        controller.exitMovePaneMode()
        fixture.close()
        fixture = nil
        super.tearDown()
    }

    func testMoveBetweenTabsClosesEmptySourceAndConsumesDropOnce() throws {
        let destination = try XCTUnwrap(fixture.terminal.currentSession())
        let tab = try XCTUnwrap(destination.delegate as? PTYTab)
        let source = fixture.addTab()
        let view = try XCTUnwrap(source.view)
        view.progressBarHeight = 12
        let textView = try XCTUnwrap(source.textview)
        let moved = expectation(forNotification: .iTermSessionDidChangeTab, object: source)
        controller.movePane(source)
        XCTAssertTrue(controller.drop(in: destination, half: .westHalf, at: .zero))
        XCTAssertFalse(controller.drop(in: destination, half: .westHalf, at: .zero))
        XCTAssertFalse(controller.drop(in: nil, half: .noHalf, at: .zero))
        wait(for: [moved], timeout: 1)
        XCTAssertEqual(fixture.terminal.numberOfTabs(), 1)
        XCTAssertEqual(tab.sessions()?.count, 2)
        XCTAssertTrue(source.delegate === tab)
        XCTAssertTrue(source.textview === textView)
        XCTAssertEqual(source.view?.progressBarHeight, 12)
    }

    func testCancelAndRejectedDropLeaveBothTabsAvailableForNextMove() throws {
        let destination = try XCTUnwrap(fixture.terminal.currentSession())
        let source = fixture.addTab()
        let sourceTab = try XCTUnwrap(source.delegate as? PTYTab)
        controller.movePane(source)
        controller.didSelectDestinationSession(nil, half: .noHalf)
        XCTAssertNil(controller.session)
        XCTAssertTrue(source.delegate === sourceTab)
        controller.movePane(source)
        XCTAssertFalse(controller.drop(in: source, half: .fullPane, at: .zero))
        XCTAssertFalse(controller.drop(in: nil, half: .noHalf, at: .zero))
        controller.exitMovePaneMode()
        controller.movePane(source)
        controller.didSelectDestinationSession(destination, half: .eastHalf)
        XCTAssertEqual(fixture.terminal.numberOfTabs(), 1)
        XCTAssertTrue(source.delegate === destination.delegate)
    }

    func testSwappingPanesAcrossTabsKeepsBothTabs() throws {
        let first = try XCTUnwrap(fixture.terminal.currentSession())
        let firstTab = try XCTUnwrap(first.delegate as? PTYTab)
        let second = fixture.addTab()
        let secondTab = try XCTUnwrap(second.delegate as? PTYTab)
        controller.swapPane(first)
        controller.didSelectDestinationSession(second, half: .fullPane)
        XCTAssertTrue(first.delegate === secondTab)
        XCTAssertTrue(second.delegate === firstTab)
        XCTAssertEqual(fixture.terminal.numberOfTabs(), 2)
        XCTAssertNil(controller.session)
    }

    func testDesktopDropCreatesOneWindowForExistingSession() throws {
        let first = try XCTUnwrap(fixture.terminal.currentSession())
        let source = fixture.split(first, vertically: true)
        controller.movePane(source)
        XCTAssertTrue(controller.drop(in: nil, half: .noHalf, at: fixture.window.frame.origin))
        let window = try XCTUnwrap(source.delegate?.realParentWindow() as? PseudoTerminal)
        XCTAssertFalse(window === fixture.terminal)
        defer { if window !== fixture.terminal { window.window?.close() } }
        XCTAssertFalse(controller.drop(in: nil, half: .noHalf, at: .zero))
        XCTAssertTrue(window.currentSession() === source)
        XCTAssertTrue(fixture.terminal.currentSession() === first)
    }

    func testLockedSourceAndMultiplePaneTabCannotStartMove() throws {
        let first = try XCTUnwrap(fixture.terminal.currentSession())
        let second = fixture.split(first, vertically: true)
        let sourceTab = try XCTUnwrap(first.delegate as? PTYTab)
        first.locked = true
        defer { first.locked = false }
        controller.swapPane(first)
        XCTAssertNil(controller.session)
        let third = fixture.addTab()
        XCTAssertFalse(controller.dropTab(sourceTab, in: third, half: .northHalf, at: .zero))
        XCTAssertNil(controller.session)
        XCTAssertTrue(second.delegate === sourceTab)
        XCTAssertEqual(fixture.terminal.numberOfTabs(), 2)
    }

    func testDraggingOnlyPaneToOwnTabBarPreservesTabIdentity() throws {
        let source = try XCTUnwrap(fixture.terminal.currentSession())
        let tab = try XCTUnwrap(source.delegate as? PTYTab)
        let originalItem = try XCTUnwrap(tab.tabViewItem)
        let tabs = try XCTUnwrap(fixture.terminal.tabView())
        controller.movePane(source)
        XCTAssertFalse(fixture.terminal.acceptsPaneDrag(from: tabs))
        let result = try XCTUnwrap(fixture.terminal.tabItemForPaneDrop(from: source.view, in: tabs))
        tabs.insertTabViewItem(result, at: 0)
        tabs.selectTabViewItem(result)
        XCTAssertTrue(result === originalItem)
        XCTAssertTrue(fixture.terminal.currentTab() === tab)
        XCTAssertTrue(tab.activeSession === source)
        XCTAssertNil(controller.session)
    }

    func testDraggingSplitPaneToAnotherWindowKeepsSourceTab() throws {
        let first = try XCTUnwrap(fixture.terminal.currentSession())
        let source = fixture.split(first, vertically: true)
        let view = try XCTUnwrap(source.view)
        let other = TerminalWindowTestFixture()
        defer { other.close() }
        let tabs = try XCTUnwrap(other.terminal.tabView())
        controller.movePane(source)
        let item = try XCTUnwrap(other.terminal.tabItemForPaneDrop(from: view, in: tabs))
        tabs.addTabViewItem(item)
        tabs.selectTabViewItem(item)
        XCTAssertTrue(other.terminal.currentSession() === source)
        XCTAssertTrue(source.view === view)
        XCTAssertTrue(fixture.terminal.currentTab()?.activeSession === first)
        XCTAssertEqual(fixture.terminal.currentTab()?.sessions()?.count, 1)
        XCTAssertNil(controller.session)
    }
}

private final class PaneDragImageSession: PTYSession {
    override var dragImage: NSImage? { NSImage(size: NSSize(width: 40, height: 25)) }
}

private final class RecordingPaneView: SessionView {
    var capturedItem: NSDraggingItem?
    weak var capturedSource: AnyObject?

    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
                                       source: NSDraggingSource) -> NSDraggingSession {
        capturedItem = items.first
        capturedSource = source
        return NSDraggingSession()
    }
}

extension MovePaneControllerTests {
    func testCancelledNativeDragRestoresTabBarsAndReleasesSource() throws {
        let source = try XCTUnwrap(PaneDragImageSession(synthetic: false))
        source.delegate = fixture.terminal.currentTab()
        let view = RecordingPaneView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        source.view = view
        fixture.window.contentView?.addSubview(view)
        defer { view.removeFromSuperview() }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero,
                                                    modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber,
                                                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        controller.beginDrag(source, event: event)
        XCTAssertTrue(controller.isDragInProgress)
        XCTAssertTrue(controller.session === source)
        XCTAssertTrue(iTermPreferences.hideTabBarSuppressedDuringDrag())
        XCTAssertTrue(view.capturedSource === view)
        let writer = try XCTUnwrap(view.capturedItem?.item as? NSPasteboardItem)
        XCTAssertTrue(writer.types.contains(.iTermMovePaneDragType))
        controller.dragFailed = true
        controller.endDrag(from: view, at: .zero, operation: [])
        XCTAssertNil(controller.session)
        XCTAssertFalse(controller.isDragInProgress)
        XCTAssertFalse(iTermPreferences.hideTabBarSuppressedDuringDrag())
    }

    func testSplitTargetRetainsPreviousEdgeInsideCenterAndDiagonalDeadZone() {
        let overlay = SplitSelectionView(frame: NSRect(x: 20, y: 30, width: 200, height: 100))
        overlay.update(at: NSPoint(x: 100, y: 50))
        XCTAssertEqual(overlay.half, .noHalf)
        overlay.update(at: NSPoint(x: 5, y: 50))
        XCTAssertEqual(overlay.half, .westHalf)
        overlay.update(at: NSPoint(x: 10, y: 4))
        XCTAssertEqual(overlay.half, .westHalf)
        overlay.update(at: NSPoint(x: 60, y: 4))
        XCTAssertEqual(overlay.half, .southHalf)
        overlay.update(at: NSPoint(x: 100, y: 50))
        XCTAssertEqual(overlay.half, .southHalf)
        overlay.setFrameSize(NSSize(width: 400, height: 100))
        overlay.update(at: NSPoint(x: 395, y: 50))
        XCTAssertEqual(overlay.half, .eastHalf)
        overlay.update(at: NSPoint(x: 200, y: 98))
        XCTAssertEqual(overlay.half, .northHalf)
        let swap = SplitSelectionView(mode: .targetSwap, frame: overlay.frame, session: nil, delegate: nil)
        swap.update(at: NSPoint(x: 100, y: 50))
        XCTAssertEqual(swap.half, .fullPane)
    }
}
