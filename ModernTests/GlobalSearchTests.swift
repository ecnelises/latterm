//
//  GlobalSearchTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class GlobalSearchTests: XCTestCase {
    func testOutlineViewAcceptsFirstMouse() {
        let outlineView = GlobalSearchOutlineView()
        XCTAssertTrue(outlineView.acceptsFirstMouse(for: nil))
    }

    func testWindowControllerLoadsXIBCleanly() {
        let controller = GlobalSearchWindowController()
        let window = controller.window
        XCTAssertNotNil(window)
        XCTAssertFalse(controller.autoHidesHotKeyWindow())
    }

    func testEmptyEngineCompletesWithFullProgress() {
        let finished = expectation(description: "empty global search finishes")
        var receivedSession: PTYSession? = PTYSession(synthetic: false)
        var receivedProgress = 0.0

        let engine = GlobalSearchEngine(query: "needle",
                                        sessions: [],
                                        mode: .smartCaseSensitivity) { session, _, progress in
            receivedSession = session
            receivedProgress = progress
            if session == nil {
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 2.0)
        withExtendedLifetime(engine) {
            XCTAssertNil(receivedSession)
            XCTAssertEqual(receivedProgress, 1.0, accuracy: 0.0001)
        }
    }

    func testFoldGroupCollectsResultsAndRevealsGracefullyWhenEmpty() {
        let session = PTYSession(synthetic: false)!
        let group = GlobalSearchFoldGroup(
            session: session,
            snippet: NSAttributedString(string: "Folded region"))
        XCTAssertEqual(group.results.count, 0)

        let emptyReveal = expectation(description: "empty group reveal")
        group.reveal(withState: NSMutableDictionary()) { rect in
            XCTAssertEqual(rect, .zero)
            emptyReveal.fulfill()
        }
        wait(for: [emptyReveal], timeout: 1.0)

        let child = GlobalFoldSearchResult()
        child.session = session
        child.snippet = NSAttributedString(string: "match")
        group.addResult(child)
        XCTAssertEqual(group.results.count, 1)
        XCTAssertTrue(group.results[0] === child)
    }

    func testGlobalSearchFindsTextInSyntheticSession() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let syncConfig = VT100MutableScreenConfiguration()
        syncConfig.sessionGuid = session.guid
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            session.screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
            mutableState.appendString(atCursor: "hello global_search_needle world")
            mutableState.appendCarriageReturnLineFeed()
            _ = session.screen.synchronize(withConfig: syncConfig,
                                           expect: nil,
                                           checkTriggers: .none,
                                           resetOverflow: false,
                                           mutableState: mutableState)
        })
        XCTAssertTrue(session.screen.compactLineDumpWithHistory().contains("global_search_needle"))

        let finished = expectation(description: "session global search finishes")
        var collectedResults: [GlobalSearchResultProtocol] = []
        var finalProgress = 0.0

        let engine = GlobalSearchEngine(query: "global_search_needle",
                                        sessions: [session],
                                        mode: .caseSensitiveSubstring) { callbackSession, results, progress in
            if let results {
                collectedResults.append(contentsOf: results)
            }
            if callbackSession == nil {
                finalProgress = progress
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 5.0)
        withExtendedLifetime(engine) {
            XCTAssertEqual(finalProgress, 1.0, accuracy: 0.0001)
            XCTAssertFalse(collectedResults.isEmpty)
            XCTAssertEqual(collectedResults.first?.session, session)
            XCTAssertTrue(collectedResults.first?.snippet.string.contains("global_search_needle") ?? false)
        }
    }
}
