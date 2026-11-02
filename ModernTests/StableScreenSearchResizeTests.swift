//
//  StableScreenSearchResizeTests.swift
//  iTerm2
//
//  Stable upstream regressions for padding, backward find and null-only selections.
//

import XCTest
@testable import iTerm2SharedARC

// Records the delegate callbacks the legacy tests asserted on. Everything else
// is inherited from FakeSession.
private class StableScreenDelegate: FakeSession {
    var cursorVisible = true
    var updateCount = 0
    var highlightsCleared = false

    override func screenSetCursorVisible(_ visible: Bool) {
        cursorVisible = visible
    }

    override func screenUpdateDisplay(_ redraw: Bool) {
        updateCount += 1
    }

    override func screenClearHighlights() {
        highlightsCleared = true
    }

    override func screenRemoveSelection() {
        selection.clear()
    }
}

// The legacy test was the selection's delegate. Only the null range matters: iTermSelection
// extends a committed range past trailing nulls using it, and returning (INT_MAX, 0) means
// "no trailing nulls" so the range is kept as given.
private class StableSelectionDelegate: NSObject, iTermSelectionDelegate {
    private func emptyRange() -> VT100GridAbsWindowedRange {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, 0, 0, 0), 0, 0)
    }
    func selectionDidChange(_ selection: iTermSelection) {}
    func liveSelectionDidEnd() {}
    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange { emptyRange() }
    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange {
        return VT100GridRangeMake(Int32.max, 0)
    }
    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord {
        XCTFail("Unexpected call to selectionPredecessorOfAbsCoord")
        return absCoord
    }
    func selectionViewportWidth() -> Int32 { 80 }
    func selectionTotalScrollbackOverflow() -> Int64 { 0 }
    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet? { IndexSet() }
    func selectionParagraphIsRTL(onAbsoluteLine line: Int64) -> Bool { false }
    func selectionLogicalIndexes(forVisualRange visualRange: NSRange, onAbsoluteLine line: Int64) -> IndexSet {
        return IndexSet(integersIn: Range(visualRange) ?? 0..<0)
    }
}

class StableScreenSearchResizeTests: XCTestCase {
    private var session = StableScreenDelegate()
    private let selectionDelegate = StableSelectionDelegate()

    override func setUp() {
        super.setUp()
        session = StableScreenDelegate()
        session.selection.delegate = selectionDelegate
    }

    // MARK: - Screen construction

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
        })
        return screen
    }

    private func screen(width: Int32, height: Int32) -> VT100Screen {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
        })
        return screen
    }

    private func appendLines(_ lines: [String], screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            for line in lines {
                mutableState.appendString(atCursor: line)
                mutableState.terminalCarriageReturn()
                mutableState.terminalLineFeed()
            }
        })
    }

    // Mirrors what VT100ScreenMutableState.setConfig does when the profile's scrollback changes.
    private func setMaxScrollbackLines(_ screen: VT100Screen, _ n: UInt32) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.maxScrollbackLines = n
            mutableState.linebuffer.setMaxLines(Int32(n))
        })
    }

    // Moves the cursor with CUP, which VT100Terminal routes to terminalMoveCursorToX:y:.
    private func moveCursor(_ screen: VT100Screen, toX x: Int32, y: Int32) {
        feed(screen, "\u{1b}[\(y);\(x)H")
    }

    // Run raw bytes through the real parser, as the pty would.
    private func feed(_ screen: VT100Screen, _ string: String) {
        guard let data = string.data(using: .utf8) else {
            XCTFail("Could not encode \(string)")
            return
        }
        screen.inject(data)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    // Cursor at first col of last row.
    private func fiveByFourScreenWithThreeLinesOneWrapped() -> VT100Screen {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde\n" +
                       "fgh..\n" +
                       "ijkl.\n" +
                       ".....")
        return screen
    }

    private func fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer() -> VT100Screen {
        let screen = self.screen(width: 5, height: 4)
        appendLines(["abcdefgh", "ijkl", "mnopqrst"], screen: screen)
        XCTAssertEqual(screen.compactLineDump(),
                       "ijkl.\n" +
                       "mnopq\n" +
                       "rst..\n" +
                       ".....")
        return screen
    }

    private func showAltAndUppercase(_ screen: VT100Screen) {
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let temp = mutableState.currentGrid.copy() else {
                XCTFail("Could not copy grid")
                return
            }
            mutableState.terminalShowAltBuffer()
            let width = Int(screen.width())
            for y in 0..<screen.height() {
                guard let lineIn = temp.screenChars(atLineNumber: y),
                      let lineOut = mutableState.currentGrid.screenChars(atLineNumber: y) else {
                    XCTFail("Missing line \(y)")
                    return
                }
                for x in 0..<width {
                    lineOut[x] = lineIn[x]
                    let c = lineIn[x].code
                    if c >= 0x61 && c <= 0x7a {
                        lineOut[x].code = c - 0x20
                    }
                }
                lineOut[width] = lineIn[width]
            }
        })
    }

    private func setSelectionRange(_ range: VT100GridCoordRange, width: Int32) {
        session.selection.clear()
        let windowedRange = VT100GridWindowedRangeMake(range, 0, 0)
        let sub = iTermSubSelection(absRange: VT100GridAbsWindowedRangeFromRelative(windowedRange, 0),
                                    mode: .kiTermSelectionModeCharacter,
                                    width: width)
        session.selection.add(sub)
    }

    // '.' is null, '-' is DWC_RIGHT, and a trailing '>' is DWC_SKIP with EOL_DWC.
    private func screenFromCompactLinesWithContinuationMarks(_ compactLines: String) -> VT100Screen {
        let lines = compactLines.components(separatedBy: "\n")
        let screen = self.screen(width: Int32(lines[0].utf16.count - 1), height: Int32(lines.count))
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            var mayHaveDWC = false
            for (i, line) in lines.enumerated() {
                guard let s = mutableState.currentGrid.screenChars(atLineNumber: Int32(i)) else {
                    XCTFail("Missing line \(i)")
                    return
                }
                let chars = Array(line.utf16)
                let last = chars.count - 1
                for j in 0..<last {
                    switch chars[j] {
                    case 0x2e:  // .
                        s[j].code = 0
                    case 0x2d:  // -
                        ScreenCharSetDWC_RIGHT(&s[j])
                        mayHaveDWC = true
                    case 0x3e where j == last - 1:  // >
                        ScreenCharSetDWC_SKIP(&s[j])
                        mayHaveDWC = true
                    default:
                        s[j].code = chars[j]
                    }
                }
                switch chars[last] {
                case 0x21:  // !
                    s[last].code = UInt16(EOL_HARD)
                case 0x2b:  // +
                    s[last].code = UInt16(EOL_SOFT)
                case 0x3e:  // >
                    mayHaveDWC = true
                    s[last].code = UInt16(EOL_DWC)
                default:
                    XCTFail("Bogus continuation mark in \(line)")
                }
            }
            if mayHaveDWC {
                mutableState.linebuffer.mayHaveDoubleWidthCharacter = true
            }
            // The cells were written behind the grid's back.
            mutableState.currentGrid.resetDWCFreeCount()
            mutableState.currentGrid.markAllCharsDirty(true, updateTimestamps: false)
        })
        return screen
    }

    private func drainSearchResults(_ engine: iTermSearchEngine) -> [SearchResult] {
        var results = [SearchResult]()
        var rangeSearched = VT100GridAbsCoordRange()
        var lineRange = NSRange()
        var finished = ObjCBool(false)
        while !finished.boolValue {
            guard let partial = engine.consume(rangeSearched: &rangeSearched,
                                               lineRange: &lineRange,
                                               finished: &finished,
                                               block: true) else {
                break
            }
            results.append(contentsOf: partial)
        }
        return results
    }

    private func search(_ screen: VT100Screen,
                        for pattern: String,
                        forward: Bool,
                        mode: iTermFindMode,
                        startX: Int32,
                        startY: Int32,
                        offset: Int32,
                        startPosition: LineBufferPosition? = nil) -> [SearchResult] {
        guard let engine = screen.searchEngine() else {
            XCTFail("No search engine")
            return []
        }
        engine.setFind(pattern,
                       forwardDirection: forward,
                       mode: mode,
                       startingAtX: startX,
                       startingAtY: startY,
                       withOffset: offset,
                       multipleResults: true,
                       absLineRange: NSRange(location: 0, length: 0),
                       forceMainScreen: false,
                       startPosition: startPosition,
                       extendResultsAcrossSoftBoundaries: false)
        return drainSearchResults(engine)
    }

    private func result(_ x: Int32, _ y: Int64, _ endX: Int32, _ endY: Int64) -> SearchResult {
        guard let result = SearchResult(fromX: x, y: y, toX: endX, y: endY) else {
            it_fatalError("SearchResult init failed")
        }
        return result
    }

    private func assertResults(_ actual: [SearchResult],
                               _ expected: [SearchResult],
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count,
                       "Expected \(expected) but got \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertTrue(e.isEqual(to: a), "Expected \(e) but got \(a)", file: file, line: line)
        }
    }

    private func assertSearch(in screen: VT100Screen,
                              for pattern: String,
                              forward: Bool,
                              mode: iTermFindMode,
                              startX: Int32,
                              startY: Int32,
                              offset: Int32,
                              matches expected: [SearchResult],
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        screen.size = VT100GridSizeMake(screen.width(), 2)
        let actual = search(screen,
                            for: pattern,
                            forward: forward,
                            mode: mode,
                            startX: startX,
                            startY: startY,
                            offset: offset)
        assertResults(actual, expected, file: file, line: line)
    }

    private func assertSearchInLines(_ compactLines: String,
                                     for pattern: String,
                                     forward: Bool,
                                     mode: iTermFindMode,
                                     startX: Int32,
                                     startY: Int32,
                                     offset: Int32,
                                     matches expected: [SearchResult],
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let screen = screenFromCompactLinesWithContinuationMarks(compactLines)
        assertSearch(in: screen,
                     for: pattern,
                     forward: forward,
                     mode: mode,
                     startX: startX,
                     startY: startY,
                     offset: offset,
                     matches: expected,
                     file: file,
                     line: line)
    }

    private let findLines =
        "abcd+\n" +
        "efgc!\n" +
        "de..!\n" +
        "fgx>>\n" +
        "Y-z.!"

    private var cdeResults: [SearchResult] {
        return [result(2, 0, 0, 1)]
    }

    func testScreenCharArrayForLastHistoryLineBeforeGridStartingWithDWC() {
        let screen = self.screen(width: 6, height: 3)
        appendLines(["abcdeＦghi"], screen: screen)
        // compactLineDump prints any code above 127 as a question mark.
        XCTAssertEqual(screen.compactLineDump(),
                       "abcde>\n" +
                       "?-ghi.\n" +
                       "......")
        var sca = screen.screenCharArray(forLine: 0)
        XCTAssertEqual(sca.line[0].code, unichar(UInt8(ascii: "a")))
        XCTAssertTrue(ScreenCharIsDWC_SKIP(sca.line[5]))
        XCTAssertEqual(sca.eol, Int32(EOL_DWC))

        // Scroll the split line into history. The line buffer does not store DWC_SKIP/EOL_DWC,
        // so screenCharArrayForLine: has to restore them for the last history line.
        appendLines(["jkl"], screen: screen)
        XCTAssertEqual(screen.numberOfScrollbackLines(), 1)
        XCTAssertEqual(screen.compactLineDump(),
                       "?-ghi.\n" +
                       "jkl...\n" +
                       "......")
        sca = screen.screenCharArray(forLine: 0)
        XCTAssertEqual(sca.line[0].code, unichar(UInt8(ascii: "a")))
        XCTAssertTrue(ScreenCharIsDWC_SKIP(sca.line[5]))
        XCTAssertEqual(sca.eol, Int32(EOL_DWC))
    }

    // Regression test for the backward wrap-around in SearchRequest.stopPosition
    // (sources/SearchingFiltering/SearchEngine.swift). -[LineBuffer findSubstring:stopAt:]
    // keeps a backward match that starts exactly at the stop, and the wrapped pass used the
    // initial start as its stop regardless of the offset, so with offset 0 the match at the
    // starting coordinate (already reported by the first pass) was reported a second time.
    // The forward equivalent (testFind_Offset0) never duplicated.
    func testFind_BackwardOffset0WrapsAroundWithoutDuplicatingStartMatch() {
        assertSearchInLines(findLines,
                            for: "de",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 0,
                            startY: 2,
                            offset: 0,
                            matches: [result(0, 2, 1, 2),
                                      result(3, 0, 0, 1)])
    }

    // For a backward search with offset 0 the wrapped pass stops one cell past the initial
    // start (SearchRequest.stopPosition). When the initial start is the last character in the
    // line buffer, that position is the buffer's end position, which is valid and equals
    // lastPosition(), so the fallback to the initial start itself is not taken and the match
    // in the final cell is reported once. These pin that: if the position one past the end
    // ever stopped being valid, the fallback would stop on the initial start and
    // findSubstring:stopAt: would report the match a second time.
    func testFind_BackwardOffset0FromMatchInFinalCellDoesNotDuplicate() {
        // The last character is the x in the last column of the last line.
        assertSearchInLines("abcd!\nefgx!",
                            for: "x",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 1,
                            offset: 0,
                            matches: [result(3, 1, 3, 1)])
    }

    // Same, with a null cell after the final character, and an earlier match so the wrapped
    // pass has something else to find.
    func testFind_BackwardOffset0FromMatchAtLastCharacterBeforeTrailingNullDoesNotDuplicate() {
        assertSearchInLines("zbcd.!\nefgz.!",
                            for: "z",
                            forward: false,
                            mode: .caseSensitiveSubstring,
                            startX: 3,
                            startY: 1,
                            offset: 0,
                            matches: [result(3, 1, 3, 1),
                                      result(0, 0, 0, 0)])
    }

    // Regression tests for a selection of nothing but nulls surviving a resize. Since commit
    // 5e401d357, -[VT100ScreenMutableState runByTrimmingNullsFromRun:] in
    // sources/VT100Screen/VT100ScreenMutableState+Resizing.m only trims nulls on the run's
    // first and last lines, so an all-null multi-line selection trimmed to a null cell,
    // positionRangeForCoordRange: succeeded, and didResizeToSize: re-added a phantom
    // sub-selection with no content, leaving hasSelection YES. The resize now drops any
    // sub-selection that contains no non-null character before converting it.
    func testResizeWithSelectionOfJustNullsInMainScreenClearsSelection() {
        let screen = self.screen(width: 5, height: 4)
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertFalse(session.selection.hasSelection)
    }

    func testResizeWithSelectionOfJustNullsInAltScreenClearsSelection() {
        let screen = self.screen(width: 5, height: 4)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalShowAltBuffer()
        })
        setSelectionRange(VT100GridCoordRangeMake(1, 1, 2, 2), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertFalse(session.selection.hasSelection)
    }

    // A selection whose first and last lines are nulls but whose middle line holds text must
    // still survive the resize.
    func testResizeWithSelectionOfNullsAroundTextKeepsSelection() {
        let screen = self.screen(width: 5, height: 4)
        moveCursor(screen, toX: 1, y: 2)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "ab")
        })
        setSelectionRange(VT100GridCoordRangeMake(1, 0, 2, 3), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 4)
        XCTAssertTrue(session.selection.hasSelection)
    }

    // Review finding on ecf71a7e7: the all-null check in
    // subSelectionsWithConvertedRangesFromSelection:newWidth: runs after reallySetSize: has
    // appended the primary grid to the line buffer. When the height shrinks, only some of the
    // grid's rows are appended, and getLineAtIndex: then serves rows past the line buffer's end
    // from the top of the grid. For a selection below the cursor the check therefore reads the
    // text rows at the top of the screen and wrongly reports content (confirmed by
    // instrumenting the check). The selection is still dropped today, but only because
    // convertRange:toWidth:to:inLineBuffer:tolerateEmpty: cannot convert a range that lies
    // past the appended rows. This pins that outcome so it keeps holding if either the check
    // or the conversion changes.
    func testResizeWithSelectionOfJustNullsBelowCursorAndTextAboveClearsSelection() {
        let screen = self.screen(width: 5, height: 24)
        appendLines(["abcd", "abcd", "abcd"], screen: screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "efgh")
        })
        XCTAssertEqual(screen.cursorY(), 4)
        setSelectionRange(VT100GridCoordRangeMake(1, 5, 2, 6), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 23)
        XCTAssertFalse(session.selection.hasSelection)
    }

    // Width-only version of the test above: the shape that reproduced the original bug. When
    // the height does not shrink, appendScreen:toScrollback:withUsedHeight:newHeight: appends
    // the whole grid, so the selected rows are inside the line buffer, the range converts, and
    // only the all-null check keeps the phantom selection from surviving.
    func testWidthOnlyResizeWithSelectionOfJustNullsBelowCursorAndTextAboveClearsSelection() {
        let screen = self.screen(width: 5, height: 24)
        appendLines(["abcd", "abcd", "abcd"], screen: screen)
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.appendString(atCursor: "efgh")
        })
        XCTAssertEqual(screen.cursorY(), 4)
        setSelectionRange(VT100GridCoordRangeMake(1, 5, 2, 6), width: screen.width())
        XCTAssertTrue(session.selection.hasSelection)
        screen.size = VT100GridSizeMake(4, 24)
        XCTAssertFalse(session.selection.hasSelection)
    }
}
