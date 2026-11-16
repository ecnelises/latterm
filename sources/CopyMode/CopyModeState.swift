//
//  CopyModeState.swift
//  iTerm2SharedARC
//
//  Migrated from iTermCopyModeState.{h,m}.
//

import Foundation

/// Interface exposed by copy-mode cursor and selection state.
@objc(iTermCopyModeStateProtocol)
protocol iTermCopyModeStateProtocol: NSObjectProtocol {
    var selecting: Bool { get set }
    var mode: iTermSelectionMode { get set }

    func moveBackwardWord() -> Bool
    func moveForwardWord() -> Bool

    func moveBackwardBigWord() -> Bool
    func moveForwardBigWord() -> Bool

    func moveLeft() -> Bool
    func moveRight() -> Bool

    func moveUp() -> Bool
    func moveDown() -> Bool

    func moveToStartOfNextLine() -> Bool

    func pageUp() -> Bool
    func pageDown() -> Bool
    func pageUpHalfScreen() -> Bool
    func pageDownHalfScreen() -> Bool

    func previousMark() -> Bool
    func nextMark() -> Bool

    func moveToStart() -> Bool
    func moveToEnd() -> Bool

    func moveToStartOfIndentation() -> Bool

    func moveToBottomOfVisibleArea() -> Bool
    func moveToMiddleOfVisibleArea() -> Bool
    func moveToTopOfVisibleArea() -> Bool

    func moveToStartOfLine() -> Bool
    func moveToEndOfLine() -> Bool

    func swap()

    func scrollUp() -> Bool
    func scrollDown() -> Bool

    @objc optional func performAsynchronously(_ block: @escaping () -> Void,
                                            completion: @escaping (Bool) -> Void)
}

/// Tracks cursor position, anchor, and active selection state while in Copy Mode.
@objc(iTermCopyModeState)
final class iTermCopyModeState: NSObject, iTermCopyModeStateProtocol {
    @objc var coord = VT100GridCoordMake(0, 0)
    @objc var start = VT100GridCoordMake(0, 0)
    @objc var numberOfLines: Int32 = 0
    @objc var textView: PTYTextView?

    @objc var selecting: Bool = false {
        didSet {
            if selecting != oldValue, selecting {
                start = coord
            }
        }
    }

    @objc var mode: iTermSelectionMode = .kiTermSelectionModeCharacter {
        didSet {
            if selecting && mode == .kiTermSelectionModeLine, let textView {
                commitLiveSelection(on: textView)
            }
        }
    }

    override init() {
        super.init()
    }

    // MARK: - Word & Character Movement

    @objc func moveBackwardWord() -> Bool {
        move(in: .left, unit: .word)
    }

    @objc func moveForwardWord() -> Bool {
        move(in: .right, unit: .word)
    }

    @objc func moveBackwardBigWord() -> Bool {
        move(in: .left, unit: .bigWord)
    }

    @objc func moveForwardBigWord() -> Bool {
        move(in: .right, unit: .bigWord)
    }

    @objc func moveLeft() -> Bool {
        move(in: .left, unit: .character)
    }

    @objc func moveRight() -> Bool {
        move(in: .right, unit: .character)
    }

    @objc func moveUp() -> Bool {
        move(in: .up, unit: .character)
    }

    @objc func moveDown() -> Bool {
        move(in: .down, unit: .character)
    }

    @objc func moveToStartOfNextLine() -> Bool {
        let moved = moveDown()
        if moved {
            _ = moveToStartOfLine()
        }
        return moved
    }

    @objc func moveToStartOfLine() -> Bool {
        move(in: .startOfLine, unit: .character)
    }

    @objc func moveToEndOfLine() -> Bool {
        move(in: .endOfLine, unit: .character)
    }

    // MARK: - Paging & Scrolling

    @objc func pageUp() -> Bool {
        let height = textView?.dataSource?.height() ?? 0
        return repeatStep(height) { moveUp() }
    }

    @objc func pageUpHalfScreen() -> Bool {
        let halfHeight = (textView?.dataSource?.height() ?? 0) / 2
        return repeatStep(halfHeight) {
            _ = scrollUpIfPossible()
            return moveUp()
        }
    }

    @objc func pageDown() -> Bool {
        let height = textView?.dataSource?.height() ?? 0
        return repeatStep(height) { moveDown() }
    }

    @objc func pageDownHalfScreen() -> Bool {
        let height = textView?.dataSource?.height() ?? 0
        return repeatStep(height) {
            _ = scrollUpIfPossible()
            return moveDown()
        }
    }

    @objc func scrollUp() -> Bool {
        guard let textView else {
            return false
        }
        if textView.rangeOfVisibleLines.location == 0 {
            return false
        }
        if scrollUpIfPossible() {
            return false
        }
        let moved = moveUp()
        if moved {
            _ = scrollUpIfPossible()
        }
        return moved
    }

    @objc func scrollDown() -> Bool {
        guard let textView, let dataSource = textView.dataSource else {
            return false
        }
        let visibleLines = textView.rangeOfVisibleLines
        if visibleLines.location + visibleLines.length == dataSource.numberOfLines() {
            return false
        }
        if scrollDownIfPossible() {
            return false
        }
        let moved = moveDown()
        if moved {
            _ = scrollDownIfPossible()
        }
        return moved
    }

    // MARK: - Visible Area, Marks & Document Bounds

    @objc func moveToBottomOfVisibleArea() -> Bool {
        guard let textView else {
            return false
        }
        let range = textView.rangeOfVisibleLines
        let destination = range.location + range.length - 1
        let steps = max(0, destination - coord.y)
        return repeatStep(steps) { moveDown() }
    }

    @objc func moveToMiddleOfVisibleArea() -> Bool {
        guard let textView else {
            return false
        }
        let range = textView.rangeOfVisibleLines
        let destination = range.location + range.length / 2
        let delta = destination - coord.y
        return repeatStep(abs(delta)) {
            delta < 0 ? moveUp() : moveDown()
        }
    }

    @objc func moveToTopOfVisibleArea() -> Bool {
        guard let textView else {
            return false
        }
        let range = textView.rangeOfVisibleLines
        let destination = range.location
        let steps = max(0, coord.y - destination)
        return repeatStep(steps) { moveUp() }
    }

    @objc func previousMark() -> Bool {
        move(in: .left, unit: .mark)
    }

    @objc func nextMark() -> Bool {
        move(in: .right, unit: .mark)
    }

    @objc func moveToStart() -> Bool {
        move(in: .top, unit: .character)
    }

    @objc func moveToEnd() -> Bool {
        move(in: .bottom, unit: .character)
    }

    @objc func moveToStartOfIndentation() -> Bool {
        move(in: .startOfIndentation, unit: .character)
    }

    @objc func swap() {
        let temp = coord
        coord = start
        start = temp
    }

    // MARK: - Private

    private func repeatStep(_ count: Int32, step: () -> Bool) -> Bool {
        guard count > 0 else {
            return false
        }
        var moved = false
        for _ in 0..<count {
            if step() {
                moved = true
            }
        }
        return moved
    }

    private func trivialRange() -> VT100GridWindowedRange {
        VT100GridWindowedRangeMake(VT100GridCoordRangeMake(coord.x, coord.y, 0, 0), 0, 0)
    }

    private func commitLiveSelection(on textView: PTYTextView) {
        let overflow = textView.dataSource?.totalScrollbackOverflow() ?? 0
        textView.selection.begin(at: VT100GridAbsCoordFromCoord(start, overflow),
                                 mode: mode,
                                 resume: false,
                                 append: false)
        textView.selection.moveEndpoint(to: VT100GridAbsCoordFromCoord(coord, overflow))
        textView.selection.endLive()
    }

    private func scrollUpIfPossible() -> Bool {
        scroll(.up)
    }

    private func scrollDownIfPossible() -> Bool {
        scroll(.down)
    }

    private func scroll(_ direction: PTYTextViewSelectionExtensionDirection) -> Bool {
        guard let textView else {
            return false
        }
        let visibleLines = textView.rangeOfVisibleLines
        switch direction {
        case .up:
            if coord.y + 1 == visibleLines.location + visibleLines.length {
                return false
            }
            textView.lockScroll()
            textView.scrollLineUp(nil)
            return true
        case .down:
            if coord.y == visibleLines.location {
                return false
            }
            textView.lockScroll()
            textView.scrollLineDown(nil)
            return true
        case .left, .right, .startOfLine, .endOfLine, .top, .bottom, .startOfIndentation:
            it_assert(false, "Unexpected scroll direction \(direction.rawValue)")
            return false
        @unknown default:
            it_assert(false, "Unknown scroll direction \(direction.rawValue)")
            return false
        }
    }

    private func move(in direction: PTYTextViewSelectionExtensionDirection,
                      unit: PTYTextViewSelectionExtensionUnit) -> Bool {
        guard let textView, let dataSource = textView.dataSource else {
            return false
        }
        let before = coord

        let extractor = iTermTextExtractor(dataSource: dataSource)
        extractor.restrictToLogicalWindow(including: coord)
        var windowedRange = trivialRange()
        windowedRange.columnWindow = extractor.logicalWindow
        let overflow = dataSource.totalScrollbackOverflow()
        let absWindowedRange = VT100GridAbsWindowedRangeFromWindowedRange(windowedRange, overflow)
        guard let helper = textView.logicalMovementHelper(forCursorCoordinate: textView.cursorCoord) else {
            return false
        }
        let range = helper.absRange(byExtending: absWindowedRange,
                                    endpoint: .start,
                                    direction: direction,
                                    extractor: extractor,
                                    unit: unit)
        coord = VT100GridCoordFromAbsCoord(range.coordRange.start, overflow, nil)

        // _start and _coord are logical cursor coordinates.
        if selecting {
            if mode == .kiTermSelectionModeCharacter {
                // Commit a logical range rather than driving a character-mode live
                // selection, which with bidi on would treat these as visual columns and
                // select the wrong cells on right-to-left lines.
                let absStart = VT100GridAbsCoordFromCoord(start, overflow)
                let absEnd = VT100GridAbsCoordFromCoord(coord, overflow)
                textView.selection.setSelectedLogicalRange(
                    VT100GridAbsWindowedRangeMake(
                        VT100GridAbsCoordRangeMake(absStart.x, absStart.y, absEnd.x, absEnd.y),
                        0,
                        0),
                    mode: mode)
            } else {
                // Line and box modes expand a range to whole lines / column bounds only
                // while it is a live selection, so keep the live path for them.
                commitLiveSelection(on: textView)
            }
        }
        textView.scrollLineNumberRange(intoView: VT100GridRangeMake(coord.y, 1))
        return !VT100GridCoordEquals(before, coord)
    }
}
