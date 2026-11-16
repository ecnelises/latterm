//
//  GlobalSearchEngineCursor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import Cocoa

/// Which screen pass a global search cursor is currently scanning.
@objc(iTermGlobalSearchEngineCursorPass)
enum GlobalSearchEngineCursorPass: UInt {
    case mainScreen
    case currentScreen
}

/// Incremental search cursor consumed by `GlobalSearchEngine`.
@objc(iTermGlobalSearchEngineCursorProtocol)
protocol GlobalSearchEngineCursorProtocol: NSObjectProtocol {
    @objc(drainFully:)
    func drainFully(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void)

    @objc(consumeAvailable:)
    func consumeAvailable(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void) -> Bool

    @objc func session() -> PTYSession
    @objc func instanceForNextPass() -> GlobalSearchEngineCursorProtocol?
    @objc func approximateLinesSearched() -> Int64
}

private func snippetMatchAttributes() -> [NSAttributedString.Key: Any] {
    return [
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .backgroundColor: NSColor(red: 1, green: 1, blue: 0, alpha: 0.35),
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
    ]
}

private func snippetRegularAttributes() -> [NSAttributedString.Key: Any] {
    return [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
    ]
}

/// Incremental search cursor over a session's screen and scrollback line buffer.
@objc(iTermGlobalSearchEngineCursor)
class GlobalSearchEngineCursor: NSObject, GlobalSearchEngineCursorProtocol, iTermSearchEngineDelegate {
    @objc var sessionValue: PTYSession
    @objc var searchEngine: iTermSearchEngine
    @objc var pass: GlobalSearchEngineCursorPass
    @objc var query: String
    @objc var mode: iTermFindMode
    @objc var currentScreenIsAlternate: Bool
    @objc var willPause: ((GlobalSearchEngineCursor) -> Void)?

    // Diagnostics only: scrollback overflow captured when the search began, so a
    // per-result log can show how far the buffer scrolled between find time and
    // snippet-extraction time.
    private let searchStartOverflow: Int64
    private let searchStartNumberOfLines: Int64

    @objc var expectedLines: Int64 {
        let screen = sessionValue.screen
        if screen.showingAlternateScreen() {
            let lastLineY = screen.absLineNumberOfLastLineInLineBuffer() - screen.totalScrollbackOverflow()
            return Int64(screen.height()) + Int64(screen.numberOfLines()) - lastLineY
        }
        return Int64(screen.numberOfLines())
    }

    @objc(initWithQuery:mode:session:)
    convenience init(query: String, mode: iTermFindMode, session: PTYSession) {
        let initialPass: GlobalSearchEngineCursorPass = session.screen.showingAlternateScreen() ? .mainScreen : .currentScreen
        self.init(query: query, mode: mode, session: session, pass: initialPass)
    }

    private init(query: String,
                 mode: iTermFindMode,
                 session: PTYSession,
                 pass: GlobalSearchEngineCursorPass) {
        let screen = session.screen
        let searchEngine = iTermSearchEngine(dataSource: nil, syncDistributor: nil)
        // Global search searches a snapshot of state at the time it began.
        searchEngine.automaticallySynchronize = false
        searchEngine.dataSource = (screen as AnyObject) as? iTermSearchEngineDataSource
        it_assert(searchEngine.dataSource != nil, "VT100Screen must conform to iTermSearchEngineDataSource")
        // Avoid blocking the main queue for too long.
        searchEngine.maxConsumeCount = 128

        let range: NSRange
        switch pass {
        case .mainScreen:
            let lastLineStart = screen.absLineNumberOfLastLineInLineBuffer()
            let numberOfLines = Int64(screen.numberOfLines())
            let length = max(0, numberOfLines - lastLineStart)
            range = NSRange(location: max(0, Int(lastLineStart)), length: Int(length))
        case .currentScreen:
            let offset = screen.totalScrollbackOverflow()
            range = NSRange(location: max(0, Int(offset)), length: max(0, Int(screen.numberOfLines())))
        }

        let request = iTermSearchRequest(
            query: query,
            mode: mode,
            startCoord: VT100GridCoordMake(0, screen.numberOfLines() + 1),
            offset: 0,
            options: [.optBackwards, .multipleResults],
            forceMainScreen: pass == .mainScreen,
            startPosition: nil)
        request.setAbsLineRange(range)

        self.sessionValue = session
        self.searchEngine = searchEngine
        self.pass = pass
        self.query = query
        self.mode = mode
        self.currentScreenIsAlternate = screen.showingAlternateScreen()
        self.searchStartOverflow = screen.totalScrollbackOverflow()
        self.searchStartNumberOfLines = Int64(screen.numberOfLines())

        super.init()

        searchEngine.delegate = self
        searchEngine.search(request)
    }

    @objc func session() -> PTYSession {
        return sessionValue
    }

    @objc func instanceForNextPass() -> GlobalSearchEngineCursorProtocol? {
        switch pass {
        case .mainScreen:
            return GlobalSearchEngineCursor(query: query, mode: mode, session: sessionValue, pass: .currentScreen)
        case .currentScreen:
            return nil
        }
    }

    @objc(drainFully:)
    func drainFully(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void) {
        while searchEngine.havePendingResults {
            let output = performSearch()
            handler(output.results, output.retiredLines)
        }
    }

    @objc(consumeAvailable:)
    func consumeAvailable(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void) -> Bool {
        let output = performSearch()
        handler(output.results, output.retiredLines)
        return output.more
    }

    @objc func approximateLinesSearched() -> Int64 {
        return Int64(searchEngine.progress * Double(sessionValue.screen.numberOfLines()))
    }

    // MARK: - iTermSearchEngineDelegate

    @objc(searchEngineWillPause:)
    func searchEngineWillPause(_ searchEngine: iTermSearchEngine) {
        if searchEngine === self.searchEngine {
            willPause?(self)
        }
    }

    // MARK: - Private

    private func performSearch() -> (results: [GlobalSearchResultProtocol], more: Bool, retiredLines: UInt) {
        let mutableResults = NSMutableArray()
        let queryCopy = searchEngine.query ?? query
        let activeMode = searchEngine.mode
        var range = NSRange(location: 0, length: 0)
        let more = searchEngine.continueFindAllResults(
            mutableResults,
            rangeOut: &range,
            absLineRange: NSRange(location: 0, length: 0),
            rangeSearched: nil)

        var results = mutableResults.compactMap { $0 as? SearchResult }

        // Extract snippets from the exact snapshot the search engine ran against so coordinates
        // stay consistent even if the live buffer scrolls or clears.
        let dataSource: iTermTextDataSource = searchEngine.searchedSnapshot ?? sessionValue.screen
        let extractor = iTermTextExtractor(dataSource: dataSource)
        let esrc = sessionValue.externalSearchResultsController
        let externals = esrc?.externalSearchResults(for: queryCopy, mode: activeMode) ?? []
        if !externals.isEmpty {
            let wrapped = externals.enumerated().compactMap { idx, external in
                SearchResult(fromExternal: external, index: Int64(idx))
            }
            results.append(contentsOf: wrapped)
            results.sort { $0.compare($1) == .orderedAscending }
        }

        let matchAttrs = snippetMatchAttributes()
        let regularAttrs = snippetRegularAttributes()
        let screen = sessionValue.screen
        let gridStartAbsY = Int64(screen.numberOfScrollbackLines()) + screen.totalScrollbackOverflow()

        let mapped: [GlobalSearchResultProtocol] = results.compactMap { item in
            if currentScreenIsAlternate && pass == .mainScreen && item.safeAbsEndY < gridStartAbsY {
                // Drop main-screen results that are entirely in the linebuffer.
                return nil
            }
            let globalResult = GlobalSearchResult()
            globalResult.session = sessionValue
            globalResult.result = item
            if item.isExternal, let externalResult = item.externalResult {
                globalResult.snippet = esrc?.snippet(
                    from: externalResult,
                    matchAttributes: matchAttrs,
                    regularAttributes: regularAttrs) ?? NSAttributedString()
            } else {
                globalResult.snippet = snippet(from: extractor, result: item)
                globalResult.resilientStart = ResilientCoordinate(
                    dataSource: screen.resilientCoordinateDataSource,
                    absCoord: VT100GridAbsCoordMake(item.internalStartX, item.internalAbsStartY))
                globalResult.resilientEnd = ResilientCoordinate(
                    dataSource: screen.resilientCoordinateDataSource,
                    absCoord: VT100GridAbsCoordMake(item.internalEndX, item.internalAbsEndY))
            }
            if pass == .mainScreen {
                globalResult.onMainScreen = true
            } else {
                globalResult.onMainScreen = !currentScreenIsAlternate
            }

            let nowOverflow = screen.totalScrollbackOverflow()
            let nowLines = Int64(screen.numberOfLines())
            let passLabel = pass == .mainScreen ? "main" : "current"
            let altLabel = currentScreenIsAlternate ? "Y" : "N"
            let extLabel = item.isExternal ? "Y" : "N"
            let escapedSnippet = globalResult.snippet.string.replacingOccurrences(of: "\n", with: "\\n")
            DLog("GS RESULT pass=\(passLabel) alt=\(altLabel) external=\(extLabel) absMatch=(\(item.internalStartX),\(item.internalAbsStartY))-(\(item.internalEndX),\(item.internalAbsEndY)) gridStartAbsY=\(gridStartAbsY) snippetLen=\(globalResult.snippet.length) snippet=\"\(escapedSnippet)\" searchStartOverflow=\(searchStartOverflow) nowOverflow=\(nowOverflow) deltaOverflow=\(nowOverflow - searchStartOverflow) searchStartLines=\(searchStartNumberOfLines) nowLines=\(nowLines) deltaLines=\(nowLines - searchStartNumberOfLines)")
            return globalResult
        }

        let retired = more ? 0 : UInt(max(0, screen.numberOfLines()))
        return (mapped, more, retired)
    }

    private func snippet(from extractor: iTermTextExtractor, result: SearchResult) -> NSAttributedString {
        it_assert(!result.isExternal)
        let range = VT100GridAbsCoordRangeMake(
            result.internalStartX,
            result.internalAbsStartY,
            result.internalEndX + 1,
            result.internalAbsEndY)
        return extractor.attributedStringForSnippet(
            for: range,
            regularAttributes: snippetRegularAttributes(),
            matchAttributes: snippetMatchAttributes(),
            maximumPrefixLength: 20,
            maximumSuffixLength: 256)
    }
}

/// Incremental search cursor over a session's folded command regions.
@objc(iTermGlobalSearchEngineFoldCursor)
class GlobalSearchEngineFoldCursor: NSObject, GlobalSearchEngineCursorProtocol {
    @objc var sessionValue: PTYSession
    @objc var query: String
    @objc var mode: iTermFindMode

    private let engine = FoldSearchEngine()
    private var pendingResults: [GlobalSearchResultProtocol] = []
    private var searchComplete = false
    private var totalFoldLines: Int64 = 0

    @objc var expectedLines: Int64 {
        return totalFoldLines
    }

    @objc(initWithQuery:mode:session:)
    init(query: String, mode: iTermFindMode, session: PTYSession) {
        self.query = query
        self.mode = mode
        self.sessionValue = session
        super.init()

        let screen = session.screen
        let width = screen.width()
        let range = VT100GridRangeMake(0, screen.numberOfLines())
        let foldMarks = screen.foldMarks(in: range) ?? []
        guard !foldMarks.isEmpty else {
            searchComplete = true
            return
        }

        var marks: [FoldMarkReading] = []
        var absLines: [NSNumber] = []
        for mark in foldMarks {
            guard let interval = mark.entry?.interval else { continue }
            let absRange = screen.absCoordRange(for: interval)
            marks.append(mark)
            absLines.append(NSNumber(value: absRange.start.y))
            totalFoldLines += Int64(mark.savedLines?.count ?? 0)
        }

        guard !marks.isEmpty else {
            searchComplete = true
            return
        }

        let matchAttrs = snippetMatchAttributes()
        let regularAttrs = snippetRegularAttributes()

        engine.search(
            query: query,
            mode: mode,
            foldMarks: marks,
            absLines: absLines,
            width: width,
            results: { [weak self] results in
                guard let self, !results.isEmpty else { return }
                let groupSnippet = NSAttributedString(
                    string: "Folded region (\(results.count) matches)",
                    attributes: regularAttrs)
                let group = GlobalSearchFoldGroup(session: self.sessionValue, snippet: groupSnippet)
                let dataSource = self.sessionValue.screen.resilientCoordinateDataSource
                for externalResult in results {
                    guard let foldResult = externalResult as? FoldSearchResult else { continue }
                    let globalResult = GlobalFoldSearchResult()
                    globalResult.session = self.sessionValue
                    globalResult.foldResult = foldResult
                    globalResult.snippet = Self.snippet(
                        from: foldResult,
                        matchAttributes: matchAttrs,
                        regularAttributes: regularAttrs)
                    if let foldMark = foldResult.foldMark as? FoldMark {
                        globalResult.resilientStart = ResilientCoordinate(
                            dataSource: dataSource,
                            enclosingFold: foldMark,
                            coord: VT100GridCoordMake(foldResult.startX, foldResult.startY))
                        globalResult.resilientEnd = ResilientCoordinate(
                            dataSource: dataSource,
                            enclosingFold: foldMark,
                            coord: VT100GridCoordMake(foldResult.endX, foldResult.endY))
                    }
                    group.addResult(globalResult)
                }
                self.pendingResults.append(group)
            },
            finished: { [weak self] in
                self?.searchComplete = true
            })
    }

    @objc func session() -> PTYSession {
        return sessionValue
    }

    @objc(drainFully:)
    func drainFully(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void) {
        guard !pendingResults.isEmpty else { return }
        let results = pendingResults
        pendingResults.removeAll()
        handler(results, UInt(max(0, totalFoldLines)))
    }

    @objc(consumeAvailable:)
    func consumeAvailable(_ handler: ([GlobalSearchResultProtocol], UInt) -> Void) -> Bool {
        let results = pendingResults
        pendingResults.removeAll()
        handler(results, searchComplete ? UInt(max(0, totalFoldLines)) : 0)
        return !searchComplete
    }

    @objc func instanceForNextPass() -> GlobalSearchEngineCursorProtocol? {
        return nil
    }

    @objc func approximateLinesSearched() -> Int64 {
        return searchComplete ? totalFoldLines : 0
    }

    private static func snippet(from foldResult: FoldSearchResult,
                                matchAttributes: [NSAttributedString.Key: Any],
                                regularAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let text = foldResult.snippetText
        if text.isEmpty {
            return NSAttributedString(string: "", attributes: regularAttributes)
        }
        let result = NSMutableAttributedString(string: text, attributes: regularAttributes)
        let matchRange = foldResult.snippetMatchRange
        if matchRange.location <= result.length && matchRange.length <= result.length - matchRange.location {
            result.addAttributes(matchAttributes, range: matchRange)
        }
        return result
    }
}
