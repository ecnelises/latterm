import XCTest
@testable import iTerm2SharedARC

final class PTYSessionInputModeCoordinatorTests: XCTestCase {
    func testMetaFrustrationPolicyPromptSpecAndActionsForSingleProfile() {
        let spec = PTYSessionMetaFrustrationPolicy.promptSpec(left: true, profileCount: 1)
        XCTAssertEqual(spec.leftOrRight, "left")
        XCTAssertEqual(spec.profileKey, KEY_OPTION_KEY_SENDS)
        XCTAssertEqual(spec.actions, ["Yes", "Stop Asking"])
        XCTAssertNil(spec.allProfilesIndex)

        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: -1, profileCount: 1), .dismiss)
        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: 0, profileCount: 1), .changeThisProfile)
        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: 1, profileCount: 1), .stopAsking)
    }

    func testMetaFrustrationPolicyPromptSpecAndActionsForMultipleProfiles() {
        let spec = PTYSessionMetaFrustrationPolicy.promptSpec(left: false, profileCount: 3)
        XCTAssertEqual(spec.leftOrRight, "right")
        XCTAssertEqual(spec.profileKey, KEY_RIGHT_OPTION_KEY_SENDS)
        XCTAssertEqual(spec.actions, ["Change This Profile", "Change All Profiles", "Stop Asking"])
        XCTAssertEqual(spec.allProfilesIndex, 1)

        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: -2, profileCount: 3), .dismiss)
        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: 0, profileCount: 3), .changeThisProfile)
        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: 1, profileCount: 3), .changeAllProfiles)
        XCTAssertEqual(PTYSessionMetaFrustrationPolicy.action(forSelection: 2, profileCount: 3), .stopAsking)
    }

    func testShortcutNavigationPolicyPrefixAndCaseInsensitiveMatches() {
        let candidates: [PTYSessionShortcutNavigationPolicy.ShortcutCandidate] = [
            .init(keyEquivalent: "ab", terminating: true),
            .init(keyEquivalent: "AC", terminating: false),
            .init(keyEquivalent: "b", terminating: false)
        ]

        XCTAssertFalse(PTYSessionShortcutNavigationPolicy.isCommandPrefix("ab", in: candidates))
        XCTAssertTrue(PTYSessionShortcutNavigationPolicy.isCommandPrefix("a", in: candidates))
        XCTAssertFalse(PTYSessionShortcutNavigationPolicy.isCommandPrefix("z", in: candidates))

        XCTAssertNil(PTYSessionShortcutNavigationPolicy.matchingIndex(forKeyEquivalent: "AB", in: candidates))
        XCTAssertEqual(PTYSessionShortcutNavigationPolicy.matchingIndex(forKeyEquivalent: "ac", in: candidates), 1)
        XCTAssertEqual(PTYSessionShortcutNavigationPolicy.matchingIndex(forKeyEquivalent: "B", in: candidates), 2)
    }

    func testCopyModeInitialCursorCoord() {
        let coord = PTYSessionCopyModeInitialStatePolicy.initialCursorCoord(cursorX: 5,
                                                                           cursorY: 12,
                                                                           scrollbackLines: 200)
        XCTAssertEqual(coord.x, 4)
        XCTAssertEqual(coord.y, 211)
    }

    func testPasteboardPolicyRoutesAndPermissionDecisions() {
        XCTAssertEqual(PTYSessionPasteboardPolicy.route(isTmuxClient: true, tmuxShouldHandleOSC52Queries: true), .tmuxOSC52)
        XCTAssertEqual(PTYSessionPasteboardPolicy.route(isTmuxClient: false, tmuxShouldHandleOSC52Queries: false), .directReport)
        XCTAssertEqual(PTYSessionPasteboardPolicy.route(isTmuxClient: true, tmuxShouldHandleOSC52Queries: false), .ignore)

        XCTAssertEqual(PTYSessionPasteboardPolicy.permissionDecision(forSelection: 0), .init(allowed: true, permanently: false))
        XCTAssertEqual(PTYSessionPasteboardPolicy.permissionDecision(forSelection: 1), .init(allowed: true, permanently: true))
        XCTAssertEqual(PTYSessionPasteboardPolicy.permissionDecision(forSelection: 2), .init(allowed: false, permanently: true))
        XCTAssertEqual(PTYSessionPasteboardPolicy.permissionDecision(forSelection: -1), .init(allowed: false, permanently: false))
    }
}
