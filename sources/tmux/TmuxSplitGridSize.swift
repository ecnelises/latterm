import AppKit

/// Measures AppKit splits in the grid cells tmux uses for panes and dividers.
enum TmuxSplitGridSize {
    private struct Axis {
        // Contributions change only at the ends of half-open pane spans.
        var deltas = [CGFloat: Int]()

        mutating func add(_ cells: Int, at start: CGFloat, length: CGFloat) {
            guard length > 0, cells > 0 else { return }
            deltas[start, default: 0] += cells
            deltas[start + length, default: 0] -= cells
        }

        var maximum: Int {
            var current = 0
            var maximum = 0
            for edge in deltas.keys.sorted() {
                current += deltas[edge, default: 0]
                maximum = max(maximum, current)
            }
            return maximum
        }
    }

    static func fixedGrid(_ root: NSSplitView, cells: (SessionView) -> NSSize) -> NSSize {
        var widths = Axis()
        var heights = Axis()

        func visit(_ split: NSSplitView, at start: NSPoint) {
            var origin = start
            for (index, child) in split.subviews.enumerated() {
                let size = child.frame.size
                if let nested = child as? NSSplitView {
                    visit(nested, at: origin)
                } else if let view = child as? SessionView {
                    let pane = cells(view)
                    widths.add(Int(pane.width), at: origin.y, length: size.height)
                    heights.add(Int(pane.height), at: origin.x, length: size.width)
                }
                // tmux uses one grid cell per divider, independent of its AppKit thickness.
                if split.isVertical {
                    if index > 0 { widths.add(1, at: origin.y, length: size.height) }
                    origin.x += size.width + split.dividerThickness
                } else {
                    if index > 0 { heights.add(1, at: origin.x, length: size.width) }
                    origin.y += size.height + split.dividerThickness
                }
            }
        }

        visit(root, at: .zero)
        return NSSize(width: widths.maximum, height: heights.maximum)
    }

    struct Pane {
        let frame: NSRect
        let decorations: NSSize
    }

    static func variableGrid(size: NSSize, cellSize: NSSize, dividerThickness: CGFloat,
                             panes: [Pane], horizontalDividers: [NSRect], verticalDividers: [NSRect]) -> NSSize {
        // Each divider or divider endpoint starts a slice with a different stack of panes.
        // tmux needs a size that fits every such stack, including its titles and scrollbars.
        func capacity(rows: Bool) -> CGFloat {
            let across = rows ? size.width : size.height
            let along = rows ? size.height : size.width
            let pointsPerCell = rows ? cellSize.height : cellSize.width
            let parallel = rows ? horizontalDividers : verticalDividers
            let perpendicular = rows ? verticalDividers : horizontalDividers
            var edges: Set<CGFloat> = [0, across]
            for frame in parallel {
                edges.insert(rows ? frame.minX : frame.minY)
                edges.insert(rows ? frame.maxX : frame.maxY)
            }
            for frame in perpendicular { edges.insert(rows ? frame.minX : frame.minY) }

            var minimum: CGFloat?
            let sorted = edges.filter { $0 >= 0 && $0 <= across }.sorted()
            for (start, end) in zip(sorted, sorted.dropFirst()) {
                let slice = rows ? NSRect(x: start, y: 0, width: end - start, height: size.height)
                                 : NSRect(x: 0, y: start, width: size.width, height: end - start)
                var count = 0
                var decoration: CGFloat = 0
                for pane in panes where NSIntersectsRect(pane.frame, slice) {
                    count += 1
                    decoration += rows ? pane.decorations.height : pane.decorations.width
                }
                guard count > 0 else { continue }
                let dividers = CGFloat(count - 1)
                let cells = dividers + floor((along - decoration - dividers * dividerThickness) / pointsPerCell)
                minimum = min(minimum ?? cells, cells)
            }
            return max(0, minimum ?? 0)
        }

        return NSSize(width: capacity(rows: false), height: capacity(rows: true))
    }
}

extension PTYTab {
    @objc func tmuxContentGridSize() -> NSSize {
        guard let root = rootView as? NSSplitView, let controller = tmuxController(),
              let profile = controller.profile(forWindow: tmuxWindow()) else { return .zero }
        let cellSize = PTYTab.cellSize(forBookmark: profile)
        guard cellSize.width > 0, cellSize.height > 0 else { return .zero }
        let window = realParentWindow()
        let margins = NSSize(width: 2 * CGFloat(iTermPreferences.sideMargins()),
                             height: 2 * CGFloat(iTermPreferences.topBottomMargins()))
        let grid: NSSize
        if controller.variableWindowSize {
            guard let root = root as? PTYSplitView else { return .zero }
            let views = isMaximized ? [activeSession?.view].compactMap { $0 } : sessionViews() ?? []
            let panes = views.map { view in
                let scroll = view.scrollview
                let scroller = scroll.hasVerticalScroller ? scroll.verticalScroller.map { type(of: $0) } : nil
                let chrome = PTYScrollView.frameSize(forContentSize: .zero, horizontalScrollerClass: nil,
                                                     verticalScrollerClass: scroller, borderType: scroll.borderType,
                                                     controlSize: .regular, scrollerStyle: scroll.scrollerStyle,
                                                     rightExtra: view.desiredRightExtra)
                let title = view.showTitle() ? SessionView.titleHeight() : 0
                let status = view.showBottomStatusBar() ? iTermGetStatusBarHeight() : 0
                let decorations = NSSize(width: margins.width + chrome.width,
                                         height: margins.height + title + status + view.toolbarReservedHeight)
                return TmuxSplitGridSize.Pane(frame: root.convert(view.bounds, from: view), decorations: decorations)
            }
            grid = TmuxSplitGridSize.variableGrid(size: root.frame.size, cellSize: cellSize,
                                                  dividerThickness: root.dividerThickness, panes: panes,
                                                  horizontalDividers: root.transitiveDividerLocationsVertical(false).map(\.frame),
                                                  verticalDividers: root.transitiveDividerLocationsVertical(true).map(\.frame))
        } else {
            let hasScrollbar = window?.scrollbarShouldBeVisible() == true
            grid = TmuxSplitGridSize.fixedGrid(root) { view in
                guard let pane = session(for: view), let scroll = pane.view?.scrollview else { return .zero }
                let scroller = hasScrollbar ? scroll.verticalScroller.map { type(of: $0) } : nil
                let content = PTYScrollView.contentSize(forFrameSize: scroll.frame.size, horizontalScrollerClass: nil,
                                                        verticalScrollerClass: scroller, borderType: scroll.borderType,
                                                        controlSize: .regular, scrollerStyle: scroll.scrollerStyle,
                                                        rightExtra: pane.desiredRightExtra())
                return NSSize(width: (content.width - margins.width) / cellSize.width,
                              height: (content.height - margins.height) / cellSize.height)
            }
        }
        // Background tabs can have stale frames. Adjust by the expected size of the current tab.
        // Round shrinkage down too, so the requested grid can still fit after AppKit resizes it.
        let target = (window?.currentTab() ?? self).delegate?.tabExpectedSize() ?? .zero
        let result = NSSize(width: grid.width + floor((target.width - root.frame.width) / cellSize.width),
                            height: grid.height + floor((target.height - root.frame.height) / cellSize.height))
        DLog("Tmux grid \(grid), root \(root.frame.size), target \(target), cell \(cellSize), result \(result)")
        return result
    }
}
