import AppKit

@objc(MovePaneController)
final class MovePaneController: NSObject, SplitSelectionViewDelegate {
    private static let shared = MovePaneController()
    @objc static func sharedInstance() -> MovePaneController { shared }

    @objc private(set) weak var session: PTYSession?
    @objc private(set) var dropping = false
    @objc var dragFailed = false
    @objc var isDragInProgress: Bool { dragSource != nil }

    private var moving = true
    private var dropHandled = false
    private var dragSource: SessionView?
    private var initialMouseLocation = NSPoint.zero
    private var cursorWindows = [NSWindow]()
    private var escapeMonitor: Any?

    private var terminals: [PseudoTerminal] {
        iTermController.sharedInstance()?.terminals() ?? []
    }

    private func canMove(_ source: PTYSession) -> Bool {
        !source.locked && source.delegate?.realParentWindow()?.layoutLocked == false
    }

    private func selectDestination(for source: PTYSession, move: Bool) {
        let live = source.live ?? source
        guard session == nil, !isDragInProgress, !source.locked,
              source.delegate?.realParentWindow()?.layoutLocked != true, canMove(live) else { return }
        session = live
        moving = move
        dropHandled = false
        for terminal in terminals {
            terminal.setSplitSelectionMode(true, excludingSession: live, move: move)
        }
    }

    @objc func movePane(_ source: PTYSession) { selectDestination(for: source, move: true) }
    @objc func swapPane(_ source: PTYSession) { selectDestination(for: source, move: false) }

    @objc func exitMovePaneMode() {
        for terminal in terminals {
            terminal.setSplitSelectionMode(false, excludingSession: nil, move: false)
        }
        clearSession()
    }

    func didSelectDestinationSession(_ destination: PTYSession!, half: SplitSessionHalf) {
        defer { exitMovePaneMode() }
        if let destination {
            _ = drop(in: destination, half: half, at: .zero)
        }
    }

    @objc(moveSessionToTab:) func moveToTab(_ source: PTYSession) {
        guard canMove(source), let window = source.delegate?.realParentWindow() as? PseudoTerminal else { return }
        _ = moveSession(source, toNewTabIn: window, atIndex: -1)
    }

    @objc(moveSessionToNewWindow:atPoint:) func moveToNewWindow(_ source: PTYSession, at point: NSPoint) {
        _ = detachToNewWindow(source, at: point)
    }

    private func detachToNewWindow(_ source: PTYSession, at point: NSPoint) -> Bool {
        guard canMove(source) else { return false }
        if source.isTmuxClient {
            guard let controller = source.tmuxController else { return false }
            controller.breakOutWindowPane(source.tmuxPane, to: point)
            return true
        }
        guard let window = iTermController.sharedInstance()?.window(for: source),
              let destination = window.terminalDraggedFromAnotherWindow(at: point) as? PseudoTerminal else {
            return false
        }
        return moveSession(source, toNewTabIn: destination, atIndex: 0) != -1
    }

    @objc(moveTab:toWindow:atIndex:)
    static func moveTab(_ tab: PTYTab, to window: PseudoTerminal, at index: Int) {
        guard let source = tab.realParentWindow() as? PseudoTerminal,
              let sourceIndex = source.tabs()?.firstIndex(of: tab) else { return }
        source.tabBarControl()?.moveTab(at: sourceIndex, toTabBar: window.tabBarControl(), at: index)
    }

    @objc func clearSession() { session = nil }

    @objc func removeAndClearSession() -> SessionView? {
        defer { clearSession() }
        guard let source = session, let tab = source.delegate as? PTYTab else { return nil }
        let view = source.view
        tab.remove(source)
        if tab.sessions()?.isEmpty == true { tab.realParentWindow()?.close(tab) }
        return view
    }

    private enum DragSource {
        case pane(PTYSession)
        case tab(PTYTab)
    }

    private func source(of drag: NSDraggingInfo, for destination: PTYSession) -> DragSource? {
        guard destination.delegate?.realParentWindow()?.layoutLocked == false,
              let types = drag.draggingPasteboard.types else { return nil }
        if types.contains(.TerminalTabPasteboardType),
           drag.draggingSource is TerminalTabBarView,
           let tab = TerminalTabDrag.shared.item?.identifier as? PTYTab,
           let panes = tab.sessions(), panes.count == 1, let pane = panes.first,
           pane !== destination, canMove(pane), pane.is(compatibleWith: destination) {
            return .tab(tab)
        }
        guard types.contains(.iTermMovePaneDragType), let source = session,
              let view = dragSource, drag.draggingSource as? SessionView === view,
              canMove(source), source === destination || source.is(compatibleWith: destination) else { return nil }
        return .pane(source)
    }

    @objc(dragEntered:destination:)
    func dragEntered(_ drag: NSDraggingInfo, destination: PTYSession) -> NSDragOperation {
        guard let source = source(of: drag, for: destination) else { return [] }
        if case .pane(let pane) = source, pane === destination { return .move }
        destination.view?.createSplitSelectionView()
        return .move
    }

    @objc(performDrop:destination:)
    func performDrop(_ drag: NSDraggingInfo, destination: PTYSession) -> Bool {
        let half = destination.view?.removeSplitSelectionView() ?? .noHalf
        guard let origin = source(of: drag, for: destination) else {
            if let view = dragSource, drag.draggingSource as? SessionView === view { dragFailed = true }
            return false
        }
        switch origin {
        case .tab(let tab):
            return dropTab(tab, in: destination, half: half, at: drag.draggingLocation)
        case .pane(let pane):
            guard pane === destination else { return drop(in: destination, half: half, at: drag.draggingLocation) }
            dragFailed = true
            if let tab = pane.delegate as? PTYTab, tab.sessions()?.count == 1,
               let terminal = tab.realParentWindow(), !terminal.anyFullScreen(), terminal.movesWhenDraggedOntoSelf(),
               let window = terminal.window {
                let end = window.convertPoint(toScreen: drag.draggingLocation)
                window.setFrameOrigin(NSPoint(x: window.frame.minX + end.x - initialMouseLocation.x,
                                              y: window.frame.minY + end.y - initialMouseLocation.y))
            }
            return false
        }
    }

    @objc(dropTab:inSession:half:atPoint:)
    func dropTab(_ tab: PTYTab, in destination: PTYSession, half: SplitSessionHalf, at point: NSPoint) -> Bool {
        guard let panes = tab.sessions(), panes.count == 1, let source = panes.first else { return false }
        session = source
        moving = true
        dropHandled = false
        defer { clearSession() }
        return drop(in: destination, half: half, at: point)
    }

    @objc(dropInSession:half:atPoint:)
    func drop(in destination: PTYSession?, half: SplitSessionHalf, at point: NSPoint) -> Bool {
        guard let source = session, !dropHandled else { return false }
        // AppKit may report both the destination drop and the end of the same drag.
        dropHandled = true
        dropping = true
        defer { dropping = false }
        guard canMove(source) else { return false }
        guard let destination else { return detachToNewWindow(source, at: point) }
        guard destination !== source, source.is(compatibleWith: destination),
              let target = destination.delegate as? PTYTab,
              let window = target.realParentWindow(), !window.layoutLocked else { return false }

        if !moving && (destination.locked || target.lockedSession != nil || (source.delegate as? PTYTab)?.lockedSession != nil) {
            return false
        }
        let vertical = half == .eastHalf || half == .westHalf
        let before = half == .northHalf || half == .westHalf
        DLog("Dropping pane \(source) onto \(destination), move=\(moving), half=\(half)")
        if source.isTmuxClient {
            guard let controller = source.tmuxController else { return false }
            if moving {
                controller.movePane(source.tmuxPane, intoPane: destination.tmuxPane, isVertical: vertical, before: before)
            } else {
                controller.swapPane(source.tmuxPane, withPane: destination.tmuxPane)
            }
        } else if moving {
            guard let previous = source.delegate as? PTYTab, let view = source.view,
                  window.canSplitPaneVertically(vertical, withBookmark: source.profile) else { return false }
            target.checkInvariants("Before move")
            withExtendedLifetime(view) {
                previous.remove(source)
                let sourceIsEmpty = previous.sessions()?.isEmpty == true
                if sourceIsEmpty { previous.realParentWindow()?.close(previous) }
                window.splitVertically(vertical, before: before, adding: source, targetSession: destination, performSetup: false)
                _ = target.fitSession(toCurrentViewSize: source)
                target.checkInvariants("After move")
                target.updateSessionOrdinals()
                if !sourceIsEmpty && previous !== target { previous.updateSessionOrdinals() }
            }
        } else {
            target.checkInvariants("Before swap")
            target.swapSession(destination, with: source)
            target.checkInvariants("After swap")
        }
        NotificationCenter.default.post(name: .iTermSessionDidChangeTab, object: source)
        return true
    }

    @objc(beginDrag:event:) func beginDrag(_ source: PTYSession, event: NSEvent?) {
        guard !isDragInProgress, canMove(source), let view = source.view, let window = view.window,
              let event, let image = source.dragImage else { return }
        exitMovePaneMode()
        session = source
        moving = true
        dropHandled = false
        dragFailed = false
        dragSource = view
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        cursorWindows = terminals.compactMap(\.window)
        for window in cursorWindows { window.disableCursorRects() }
        NSCursor.closedHand.set()
        iTermPreferences.setHideTabBarSuppressedDuringDrag(true)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.dragFailed = true }
            return event
        }
        let writer = NSPasteboardItem()
        writer.setString("", forType: .iTermMovePaneDragType)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(NSRect(origin: view.bounds.origin, size: image.size), contents: image)
        view.beginDraggingSession(with: [item], event: event, source: view).animatesToStartingPositionsOnCancelOrFail = false
    }

    @objc(endDragFrom:atPoint:operation:)
    func endDrag(from view: SessionView, at point: NSPoint, operation: NSDragOperation) {
        guard dragSource === view else { return }
        if !dragFailed && operation.isEmpty && NSEvent.pressedMouseButtons == 0 {
            _ = drop(in: nil, half: .noHalf, at: point)
        }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        iTermPreferences.setHideTabBarSuppressedDuringDrag(false)
        for window in cursorWindows { window.enableCursorRects() }
        cursorWindows.removeAll()
        NSCursor.openHand.set()
        dragSource = nil
        clearSession()
    }
}
