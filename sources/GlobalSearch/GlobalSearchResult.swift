//
//  GlobalSearchResult.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import Cocoa

/// Common interface for items rendered and revealed in the global search outline view.
@objc(iTermGlobalSearchResultProtocol)
protocol GlobalSearchResultProtocol: NSObjectProtocol {
    @objc var session: PTYSession? { get set }
    @objc var snippet: NSAttributedString { get set }

    @objc(revealWithState:completion:)
    func reveal(withState state: NSMutableDictionary, completion: @escaping (NSRect) -> Void)
}

private func revealCoordRange(from start: ResilientCoordinate,
                              end: ResilientCoordinate,
                              in session: PTYSession) -> NSRect {
    let overflow = session.screen.totalScrollbackOverflow()
    let absStart = start.coord
    let absEnd = end.coord
    let coordRange = VT100GridCoordRangeMake(
        absStart.x,
        max(0, Int32(absStart.y - overflow)),
        absEnd.x + 1,
        max(0, Int32(absEnd.y - overflow)))
    if let textView = session.textview {
        textView.select(coordRange)
        let margin: Int32 = 3
        let scrollRange = VT100GridRangeMake(
            max(0, coordRange.start.y - margin),
            coordRange.end.y - coordRange.start.y + 1 + margin * 2)
        textView.scrollLineNumberRange(intoView: scrollRange)
        for line in coordRange.start.y...coordRange.end.y {
            textView.highlightMark(onLine: line, hasErrorCode: false)
        }
    }
    return GlobalSearchResult.rect(forCoordRange: coordRange, session: session)
}

/// A search hit in a session's main or alternate screen (or external search results).
@objc(iTermGlobalSearchResult)
class GlobalSearchResult: NSObject, GlobalSearchResultProtocol {
    private static let stateKey = "session guids with changed screens"

    @objc var isExternal: Bool {
        return result?.isExternal ?? false
    }

    @objc weak var session: PTYSession?
    @objc var result: SearchResult?
    @objc var snippet: NSAttributedString = NSAttributedString()
    @objc var onMainScreen: Bool = false

    // Resilient coordinates that automatically adjust for fold/unfold/resize.
    @objc var resilientStart: ResilientCoordinate?
    @objc var resilientEnd: ResilientCoordinate?

    /// Restores any sessions that were temporarily switched between main and alternate screens.
    @objc(restoreAlternateScreensWithAnnouncement:state:)
    static func restoreAlternateScreens(withAnnouncement announce: Bool, state: NSMutableDictionary) {
        if let changed = state[stateKey] as? [String: NSNumber] {
            for (guid, originalShowAlternate) in changed {
                if let session = iTermController.sharedInstance().session(withGUID: guid) {
                    session.setShowAlternateScreen(originalShowAlternate.boolValue, announce: announce)
                }
            }
        }
        state.removeAllObjects()
    }

    /// Computes the screen-space bounding rectangle for `coordRange` within `session`.
    static func rect(forCoordRange coordRange: VT100GridCoordRange, session: PTYSession) -> NSRect {
        guard let textView = session.textview, let window = textView.window else {
            return .zero
        }
        func screenRect(for coord: VT100GridCoord) -> NSRect {
            let viewRect = textView.frame(for: coord)
            let windowRect = textView.convert(viewRect, to: nil)
            return window.convertToScreen(windowRect)
        }
        return screenRect(for: coordRange.start).union(screenRect(for: coordRange.end))
    }

    @objc func highlightLines() {
        guard !isExternal,
              let session,
              let resilientStart,
              let resilientEnd,
              resilientStart.status == .valid else {
            return
        }
        let overflow = session.screen.totalScrollbackOverflow()
        let absStart = resilientStart.coord
        let absEnd = resilientEnd.coord
        let startY = max(0, Int32(absStart.y - overflow))
        let endY = max(0, Int32(absEnd.y - overflow))
        guard startY <= endY else { return }
        for line in startY...endY {
            session.textview?.highlightMark(onLine: line, hasErrorCode: false)
        }
    }

    @objc(revealWithState:completion:)
    func reveal(withState state: NSMutableDictionary, completion: @escaping (NSRect) -> Void) {
        switchSessionToAlternateScreenIfNeeded(state: state)
        guard let session else {
            completion(.zero)
            return
        }
        if isExternal, let externalResult = result?.externalResult {
            session.externalSearchResultsController?.select(
                externalSearchResult: externalResult,
                multiple: false,
                scroll: true)
            completion(.zero)
        } else if let resilientStart,
                  let resilientEnd,
                  resilientStart.status == .valid {
            let hull = revealCoordRange(from: resilientStart, end: resilientEnd, in: session)
            completion(hull)
        } else {
            completion(.zero)
        }
    }

    private func switchSessionToAlternateScreenIfNeeded(state: NSMutableDictionary) {
        guard let session else { return }
        let shouldShowAlternateScreen = !onMainScreen
        let currentlyShowingAlternate = session.screen.showingAlternateScreen()
        guard shouldShowAlternateScreen != currentlyShowingAlternate else {
            return
        }
        let changed: NSMutableDictionary
        if let existing = state[Self.stateKey] as? NSMutableDictionary {
            changed = existing
        } else {
            changed = NSMutableDictionary()
            state[Self.stateKey] = changed
        }
        changed[session.guid] = NSNumber(value: currentlyShowingAlternate)
        session.setShowAlternateScreen(shouldShowAlternateScreen, announce: true)
    }
}

/// A search hit inside a folded region, unfolding its enclosing fold before selecting on reveal.
@objc(iTermGlobalFoldSearchResult)
class GlobalFoldSearchResult: NSObject, GlobalSearchResultProtocol {
    @objc weak var session: PTYSession?
    @objc var snippet: NSAttributedString = NSAttributedString()
    @objc var foldResult: FoldSearchResult?

    // Resilient coordinates that automatically adjust for fold/unfold/resize.
    @objc var resilientStart: ResilientCoordinate?
    @objc var resilientEnd: ResilientCoordinate?

    @objc(revealWithState:completion:)
    func reveal(withState state: NSMutableDictionary, completion: @escaping (NSRect) -> Void) {
        guard let session else {
            completion(.zero)
            return
        }
        if let resilientStart,
           resilientStart.status == .inFold,
           let foldInfo = resilientStart.foldInfo,
           let textView = session.textview {
            textView.unfold(mark: foldInfo.mark) { [weak self] _ in
                self?.revealAfterUnfold(completion: completion)
            }
            return
        }
        revealAfterUnfold(completion: completion)
    }

    private func revealAfterUnfold(completion: (NSRect) -> Void) {
        guard let session,
              let resilientStart,
              let resilientEnd,
              resilientStart.status == .valid else {
            completion(.zero)
            return
        }
        let hull = revealCoordRange(from: resilientStart, end: resilientEnd, in: session)
        completion(hull)
    }
}

/// Groups all global search matches belonging to a single folded region.
@objc(iTermGlobalSearchFoldGroup)
class GlobalSearchFoldGroup: NSObject, GlobalSearchResultProtocol {
    @objc weak var session: PTYSession?
    @objc var snippet: NSAttributedString
    @objc private(set) var results: [GlobalFoldSearchResult] = []

    @objc(initWithSession:snippet:)
    init(session: PTYSession, snippet: NSAttributedString) {
        self.session = session
        self.snippet = snippet.copy() as? NSAttributedString ?? snippet
        super.init()
    }

    @objc(addResult:)
    func addResult(_ result: GlobalFoldSearchResult) {
        results.append(result)
    }

    @objc(revealWithState:completion:)
    func reveal(withState state: NSMutableDictionary, completion: @escaping (NSRect) -> Void) {
        if let first = results.first {
            first.reveal(withState: state, completion: completion)
        } else {
            completion(.zero)
        }
    }
}
