import XCTest
@testable import iTerm2SharedARC

final class iTermPromptOnCloseReasonTests: XCTestCase {
    private func compound() -> PromptOnCloseReason {
        return PromptOnCloseReason.none()
    }

    private func pinned(_ tabNumber: Int32) -> PromptOnCloseReason {
        return PromptOnCloseReason.pinnedTab(tabNumber)
    }

    func testSessionAndTabUseProfilePolicyAndLockState() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let tab = try XCTUnwrap(PTYTab(session: session, parentWindow: nil))
        session.profile = [KEY_NAME: "Test", KEY_PROMPT_CLOSE: PROMPT_ALWAYS]
        XCTAssertEqual(tab.promptOnCloseReason.message, "• The profile “Test” always requires confirmation.\nYou can change this setting in Settings > Profiles > Session")
        session.profile = [KEY_NAME: "Test", KEY_PROMPT_CLOSE: PROMPT_NEVER]
        XCTAssertFalse(tab.promptOnCloseReason.hasReason)
        session.locked = true
        XCTAssertEqual(tab.promptOnCloseReason.message, "• This pane is locked.")
    }

    func testJobsAreGroupedByProfileAndSortedBeforePinnedTabs() {
        let reason = compound()
        reason.add(pinned(1))
        reason.add(.profile([KEY_NAME: "Build"], blockedByJobs: ["a", "b", "c", "d"]))
        XCTAssertEqual(reason.message.components(separatedBy: "\n"), [
            "• A session with profile “Build” is running a, b, c, and 1 other job.",
            "You can change this setting in Settings > Profiles > Session", "", "• Tab #1 is pinned."
        ])
    }

    func testNoReasonHasNoReason() {
        XCTAssertFalse(compound().hasReason)
    }

    func testTabIsPinnedHasReasonAndIncludesTabNumber() {
        let reason = pinned(3)
        XCTAssertTrue(reason.hasReason)
        XCTAssertEqual(reason.message, "Tab #3 is pinned.")
    }

    func testCompoundContainsAddedReasonMessage() {
        let c = compound()
        c.add(pinned(7))
        XCTAssertTrue(c.hasReason)
        XCTAssertTrue(c.message.contains("Tab #7 is pinned."))
    }

    func testCompoundListsEveryPinnedTabSeparately() {
        let c = compound()
        c.add(pinned(1))
        c.add(pinned(2))
        c.add(pinned(3))
        XCTAssertTrue(c.message.contains("Tab #1 is pinned."))
        XCTAssertTrue(c.message.contains("Tab #2 is pinned."))
        XCTAssertTrue(c.message.contains("Tab #3 is pinned."))
    }

    func testCompoundDeduplicatesIdenticalMessages() {
        let c = compound()
        c.add(PromptOnCloseReason.sessionIsLocked())
        c.add(PromptOnCloseReason.sessionIsLocked())
        let occurrences = c.message.components(separatedBy: "This pane is locked.").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testTabIsPinnedAndSessionIsLockedBothAppear() {
        let c = compound()
        c.add(PromptOnCloseReason.sessionIsLocked())
        c.add(pinned(5))
        XCTAssertTrue(c.message.contains("This pane is locked."))
        XCTAssertTrue(c.message.contains("Tab #5 is pinned."))
    }
}
