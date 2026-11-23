import XCTest
@testable import iTerm2SharedARC

@MainActor
final class TmuxSplitGridSizeTests: XCTestCase {
    private func pane(width: CGFloat, height: CGFloat) -> SessionView {
        SessionView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    private func split(vertical: Bool, views: [NSView]) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin
        let sizes = views.map { $0.frame.size }
        for view in views { split.addSubview(view) }
        var size = NSSize.zero
        for (index, view) in views.enumerated() {
            let childSize = sizes[index]
            if vertical {
                if index > 0 { size.width += split.dividerThickness }
                view.frame = NSRect(origin: NSPoint(x: size.width, y: 0), size: childSize)
                size.width += childSize.width
                size.height = max(size.height, childSize.height)
            } else {
                if index > 0 { size.height += split.dividerThickness }
                view.frame = NSRect(origin: NSPoint(x: 0, y: size.height), size: childSize)
                size.height += childSize.height
                size.width = max(size.width, childSize.width)
            }
        }
        split.frame.size = size
        return split
    }

    func testStaggeredNestedSplitsUseOnlyPanesCrossingTheSameRow() {
        let a = pane(width: 160, height: 30)
        let b = pane(width: 160, height: 70)
        let c = pane(width: 155, height: 60)
        let d = pane(width: 155, height: 40)
        let left = split(vertical: false, views: [a, b])
        let right = split(vertical: false, views: [c, d])
        let root = split(vertical: true, views: [left, right])
        let cells = [a: NSSize(width: 80, height: 10), b: NSSize(width: 35, height: 20),
                     c: NSSize(width: 20, height: 25), d: NSSize(width: 90, height: 8)]
        let size = TmuxSplitGridSize.fixedGrid(root) { cells[$0, default: .zero] }
        // The widest row crosses B and D. The tallest column crosses C and D.
        XCTAssertEqual(size, NSSize(width: 35 + 1 + 90, height: 25 + 1 + 8))
    }

    func testAlignedHalfPointEdgesAndEmptyGrid() {
        let topLeft = pane(width: 45, height: 30.5)
        let bottomLeft = pane(width: 45, height: 20.5)
        let topRight = pane(width: 50, height: 30.5)
        let bottomRight = pane(width: 50, height: 20.5)
        let root = split(vertical: true, views: [split(vertical: false, views: [topLeft, bottomLeft]),
                                                 split(vertical: false, views: [topRight, bottomRight])])
        let size = TmuxSplitGridSize.fixedGrid(root) { pane in
            NSSize(width: pane === topLeft || pane === bottomRight ? 40 : 10, height: 8)
        }
        XCTAssertEqual(size, NSSize(width: 51, height: 17))
        XCTAssertEqual(TmuxSplitGridSize.fixedGrid(NSSplitView()) { _ in .zero }, .zero)
    }

    func testVariableGridFitsTheMostDecoratedRowAndColumn() {
        let panes = [
            TmuxSplitGridSize.Pane(frame: NSRect(x: 0, y: 0, width: 100, height: 160),
                                   decorations: NSSize(width: 10, height: 0)),
            TmuxSplitGridSize.Pane(frame: NSRect(x: 101, y: 0, width: 99, height: 79),
                                   decorations: NSSize(width: 5, height: 20)),
            TmuxSplitGridSize.Pane(frame: NSRect(x: 101, y: 80, width: 99, height: 80),
                                   decorations: NSSize(width: 10, height: 10))
        ]
        let grid = TmuxSplitGridSize.variableGrid(size: NSSize(width: 200, height: 160),
                                                  cellSize: NSSize(width: 10, height: 10),
                                                  dividerThickness: 1, panes: panes,
                                                  horizontalDividers: [NSRect(x: 101, y: 79, width: 99, height: 1)],
                                                  verticalDividers: [NSRect(x: 100, y: 0, width: 1, height: 160)])
        XCTAssertEqual(grid, NSSize(width: 18, height: 13))
    }

    func testVariableGridCountsOnlyTheVisiblePaneWhenMaximized() {
        let pane = TmuxSplitGridSize.Pane(frame: NSRect(x: 0, y: 0, width: 90, height: 100),
                                          decorations: NSSize(width: 10, height: 35))
        let grid = TmuxSplitGridSize.variableGrid(size: pane.frame.size, cellSize: NSSize(width: 8, height: 16),
                                                  dividerThickness: 1, panes: [pane],
                                                  horizontalDividers: [], verticalDividers: [])
        XCTAssertEqual(grid, NSSize(width: 10, height: 4))
    }

    func testTabReportsBothClientSizesAndReservesOneBorderRow() throws {
        let fixture = TerminalWindowTestFixture()
        defer { fixture.close() }
        let tab = try XCTUnwrap(fixture.terminal.currentTab())
        let first = try XCTUnwrap(tab.activeSession)
        _ = fixture.split(first, vertically: true)
        fixture.window.layoutIfNeeded()
        let controller = try XCTUnwrap(TmuxController(gateway: nil, clientName: "split-grid-size-test",
                                                      profile: first.profile, profileModel: nil))
        tab.setValue(controller, forKey: "tmuxController_")
        defer {
            tab.setValue(nil, forKey: "tmuxController_")
            TmuxControllerRegistry.sharedInstance().setController(nil, forClient: controller.clientName)
        }
        for variable in [false, true] {
            controller.setValue(variable, forKey: "variableWindowSize")
            controller.setPaneBorderStatus(.off, forWindow: tab.tmuxWindow())
            let unbordered = tab.tmuxSize
            XCTAssertGreaterThan(unbordered.width, 0)
            XCTAssertGreaterThan(unbordered.height, 0)
            controller.setPaneBorderStatus(.top, forWindow: tab.tmuxWindow())
            XCTAssertEqual(tab.tmuxSize, NSSize(width: unbordered.width, height: unbordered.height + 1))
        }
    }
}
