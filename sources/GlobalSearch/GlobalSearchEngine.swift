//
//  GlobalSearchEngine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import Cocoa

/// Drives incremental global search across multiple sessions and reports progress.
@objc(iTermGlobalSearchEngine)
class GlobalSearchEngine: NSObject {
    @objc var mode: iTermFindMode
    @objc let query: String
    @objc let handler: (PTYSession?, [GlobalSearchResultProtocol]?, Double) -> Void
    @objc let sessions: [PTYSession]

    private var timer: Timer?
    private var cursors: [GlobalSearchEngineCursorProtocol] = []
    private var retiredLines: UInt = 0
    private var expectedLines: UInt = 0

    @objc(initWithQuery:sessions:mode:handler:)
    init(query: String,
         sessions: [PTYSession],
         mode: iTermFindMode,
         handler: @escaping (PTYSession?, [GlobalSearchResultProtocol]?, Double) -> Void) {
        self.query = query
        self.sessions = sessions
        self.mode = mode
        self.handler = handler
        super.init()

        for session in sessions {
            let cursor = GlobalSearchEngineCursor(query: query, mode: mode, session: session)
            cursor.willPause = { [weak self] pausedCursor in
                self?.drain(pausedCursor)
            }
            expectedLines += UInt(max(0, cursor.expectedLines))
            cursors.append(cursor)

            let foldCursor = GlobalSearchEngineFoldCursor(query: query, mode: mode, session: session)
            expectedLines += UInt(max(0, foldCursor.expectedLines))
            cursors.append(foldCursor)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0, repeats: true) { [weak self] _ in
            self?.searchMore()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Cancels any active search cursors and signals completion.
    @objc func stop() {
        handler(nil, nil, 1)
        timer?.invalidate()
        timer = nil
    }

    private func drain(_ cursor: GlobalSearchEngineCursorProtocol) {
        cursor.drainFully { results, retired in
            retiredLines += retired
            handler(cursor.session(), results, progress(including: cursor))
        }
    }

    private func searchMore() {
        guard !cursors.isEmpty else {
            stop()
            return
        }
        let cursor = cursors.removeFirst()
        var more = false
        cursor.consumeAvailable { results, retired in
            retiredLines += retired
            handler(cursor.session(), results, progress(including: cursor))
        }.with { result in
            more = result
        }
        if more {
            cursors.append(cursor)
            return
        }
        if let nextCursor = cursor.instanceForNextPass() {
            cursors.append(nextCursor)
            return
        }
        if cursors.isEmpty {
            stop()
        }
    }

    private func progress(including additionalCursor: GlobalSearchEngineCursorProtocol) -> Double {
        guard expectedLines > 0 else {
            return 1.0
        }
        var done = Double(retiredLines)
        for cursor in cursors + [additionalCursor] {
            done += Double(cursor.approximateLinesSearched())
        }
        return min(1.0, max(0.0, done / Double(expectedLines)))
    }
}

private extension Bool {
    func with(_ body: (Bool) -> Void) {
        body(self)
    }
}
