//
//  PTYSessionWave5CoordinatorTests.swift
//  ModernTests
//

import Cocoa
import XCTest
@testable import iTerm2SharedARC

final class PTYSessionWave5CoordinatorTests: XCTestCase {
    func testAnnouncementCoordinatorQueueReplaceCompletionAndDismiss() {
        var addedControllers: [iTermAnnouncementViewController] = []
        let coordinator = PTYSessionAnnouncementCoordinator(session: nil) { controller in
            addedControllers.append(controller)
        }

        var firstSelections: [Int32] = []
        let first = iTermAnnouncementViewController.announcement(
            withTitle: "First notice",
            style: .warning,
            withActions: ["OK"]
        ) { selection in
            firstSelections.append(selection)
        }

        coordinator.queueAnnouncement(first, identifier: "id.one")
        XCTAssertTrue(coordinator.hasAnnouncement(withIdentifier: "id.one"))
        XCTAssertTrue(coordinator.announcement(withIdentifier: "id.one") === first)
        XCTAssertEqual(addedControllers.count, 1)

        // Non--2 selection keeps the entry until dismiss (-2) runs.
        first.completion?(0)
        XCTAssertEqual(firstSelections, [0])
        XCTAssertTrue(coordinator.hasAnnouncement(withIdentifier: "id.one"))

        // Queueing a second announcement with the same identifier dismisses the first (-2).
        var secondSelections: [Int32] = []
        let second = iTermAnnouncementViewController.announcement(
            withTitle: "Second notice",
            style: .warning,
            withActions: ["OK"]
        ) { selection in
            secondSelections.append(selection)
        }
        coordinator.queueAnnouncement(second, identifier: "id.one")
        XCTAssertEqual(firstSelections, [0, -2])
        XCTAssertTrue(coordinator.announcement(withIdentifier: "id.one") === second)
        XCTAssertEqual(addedControllers.count, 2)

        coordinator.dismissAnnouncement(withIdentifier: "id.one")
        XCTAssertEqual(secondSelections, [-2])
        XCTAssertFalse(coordinator.hasAnnouncement(withIdentifier: "id.one"))
        XCTAssertNil(coordinator.announcement(withIdentifier: "id.one"))
    }

    func testFilterPolicySkipAndRefineDecisions() {
        XCTAssertFalse(PTYSessionFilterPolicy.shouldSkipUpdate(
            newFilter: "err",
            currentFilter: "err",
            currentMode: .caseSensitiveSubstring,
            requestedMode: .caseSensitiveSubstring,
            hasActiveAsyncFilter: false
        ))
        XCTAssertTrue(PTYSessionFilterPolicy.shouldSkipUpdate(
            newFilter: "err",
            currentFilter: "err",
            currentMode: .caseSensitiveSubstring,
            requestedMode: .caseSensitiveSubstring,
            hasActiveAsyncFilter: true
        ))
        XCTAssertFalse(PTYSessionFilterPolicy.shouldSkipUpdate(
            newFilter: "err",
            currentFilter: "err",
            currentMode: .caseSensitiveSubstring,
            requestedMode: .caseInsensitiveSubstring,
            hasActiveAsyncFilter: true
        ))
        XCTAssertFalse(PTYSessionFilterPolicy.shouldSkipUpdate(
            newFilter: nil,
            currentFilter: "err",
            currentMode: .caseSensitiveSubstring,
            requestedMode: .caseSensitiveSubstring,
            hasActiveAsyncFilter: true
        ))

        XCTAssertTrue(PTYSessionFilterPolicy.shouldRefine(
            existingMode: .caseInsensitiveSubstring,
            requestedMode: .caseInsensitiveSubstring,
            isRegex: false
        ))
        XCTAssertFalse(PTYSessionFilterPolicy.shouldRefine(
            existingMode: .caseInsensitiveSubstring,
            requestedMode: .caseSensitiveSubstring,
            isRegex: false
        ))
        XCTAssertFalse(PTYSessionFilterPolicy.shouldRefine(
            existingMode: .caseSensitiveRegex,
            requestedMode: .caseSensitiveRegex,
            isRegex: true
        ))
    }

    func testFindCoordinatorSafeStateWithoutViewOrWindow() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let coordinator = PTYSessionFindCoordinator(session: session)
        XCTAssertFalse(coordinator.hasActiveAsyncFilter)
        XCTAssertNil(coordinator.currentFilter)
        XCTAssertFalse(coordinator.canSearch())
        XCTAssertFalse(coordinator.findInProgress())
        XCTAssertEqual(coordinator.findDriverNumberOfSearchResults(), 0)
        XCTAssertEqual(coordinator.findDriverCurrentIndex(), 0)
        XCTAssertTrue(coordinator.findDriverSearchEngine() === session.screen.searchEngine())
    }

    func testViewLayoutPolicyGeometryAndFlags() {
        let grown = PTYSessionViewLayoutPolicy.safeWrapperFrame(
            proposed: NSRect(x: 0, y: 0, width: 400, height: 120),
            minimumHeight: 200
        )
        XCTAssertEqual(grown, NSRect(x: 0, y: 0, width: 400, height: 200))

        let unchanged = PTYSessionViewLayoutPolicy.safeWrapperFrame(
            proposed: NSRect(x: 0, y: 0, width: 400, height: 250),
            minimumHeight: 200
        )
        XCTAssertEqual(unchanged, NSRect(x: 0, y: 0, width: 400, height: 250))

        let clamped = PTYSessionViewLayoutPolicy.clampedTmuxScrollViewSize(
            proposed: NSSize(width: 900, height: 700),
            ideal: NSSize(width: 800, height: 600),
            charWidth: 8,
            lineHeight: 16
        )
        XCTAssertEqual(clamped, NSSize(width: 807, height: 615))

        XCTAssertTrue(PTYSessionViewLayoutPolicy.useSeparateStatusBarsPerPane(preferenceEnabled: true, isTmuxClient: false))
        XCTAssertFalse(PTYSessionViewLayoutPolicy.useSeparateStatusBarsPerPane(preferenceEnabled: true, isTmuxClient: true))
        XCTAssertFalse(PTYSessionViewLayoutPolicy.useSeparateStatusBarsPerPane(preferenceEnabled: false, isTmuxClient: false))

        XCTAssertFalse(PTYSessionViewLayoutPolicy.splitPaneWidthLockAllowed(tmuxMode: TMUX_CLIENT, sessionCount: 2, hasVerticalSplitAncestor: true))
        XCTAssertFalse(PTYSessionViewLayoutPolicy.splitPaneWidthLockAllowed(tmuxMode: TMUX_NONE, sessionCount: 1, hasVerticalSplitAncestor: true))
        XCTAssertFalse(PTYSessionViewLayoutPolicy.splitPaneWidthLockAllowed(tmuxMode: TMUX_NONE, sessionCount: 2, hasVerticalSplitAncestor: false))
        XCTAssertTrue(PTYSessionViewLayoutPolicy.splitPaneWidthLockAllowed(tmuxMode: TMUX_NONE, sessionCount: 2, hasVerticalSplitAncestor: true))

        XCTAssertTrue(PTYSessionViewLayoutPolicy.selectionScrollAllowed(disabledInAltScreen: false, isAltScreen: true, isScrolledToBottom: true))
        XCTAssertTrue(PTYSessionViewLayoutPolicy.selectionScrollAllowed(disabledInAltScreen: true, isAltScreen: false, isScrolledToBottom: true))
        XCTAssertTrue(PTYSessionViewLayoutPolicy.selectionScrollAllowed(disabledInAltScreen: true, isAltScreen: true, isScrolledToBottom: false))
        XCTAssertFalse(PTYSessionViewLayoutPolicy.selectionScrollAllowed(disabledInAltScreen: true, isAltScreen: true, isScrolledToBottom: true))
    }
}
