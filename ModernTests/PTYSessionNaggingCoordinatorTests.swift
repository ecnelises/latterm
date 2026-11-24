//
//  PTYSessionNaggingCoordinatorTests.swift
//  ModernTests
//
//  Unit tests for pure policy and arrangement cache logic extracted in
//  PTYSessionNaggingCoordinator.swift.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionNaggingCoordinatorTests: XCTestCase {
    func testAnnouncementObscuresCursorBoundariesAndZeroLineHeight() {
        // Exactly 2 lines high -> cursor on lines 0, 1, 2 is obscured; line 3 is not.
        XCTAssertTrue(PTYSessionNaggingPolicy.announcementObscuresCursor(
            announcementHeight: 24,
            lineHeight: 12,
            cursorY: 2
        ))
        XCTAssertFalse(PTYSessionNaggingPolicy.announcementObscuresCursor(
            announcementHeight: 24,
            lineHeight: 12,
            cursorY: 3
        ))
        // Fractional line height rounds up via ceil.
        XCTAssertTrue(PTYSessionNaggingPolicy.announcementObscuresCursor(
            announcementHeight: 25,
            lineHeight: 12,
            cursorY: 3
        ))
        // Zero or non-finite lineHeight safely returns false.
        XCTAssertFalse(PTYSessionNaggingPolicy.announcementObscuresCursor(
            announcementHeight: 24,
            lineHeight: 0,
            cursorY: 0
        ))
        XCTAssertFalse(PTYSessionNaggingPolicy.announcementObscuresCursor(
            announcementHeight: 24,
            lineHeight: -5,
            cursorY: 0
        ))
    }

    func testBackgroundImageUpdatePayloadHandlesNilEmptyAndNonEmpty() {
        let nilPayload = PTYSessionNaggingPolicy.backgroundImageUpdatePayload(for: nil)
        XCTAssertTrue(nilPayload[KEY_BACKGROUND_IMAGE_LOCATION] is NSNull)

        let emptyPayload = PTYSessionNaggingPolicy.backgroundImageUpdatePayload(for: "")
        XCTAssertTrue(emptyPayload[KEY_BACKGROUND_IMAGE_LOCATION] is NSNull)

        let pathPayload = PTYSessionNaggingPolicy.backgroundImageUpdatePayload(for: "/tmp/bg.png")
        XCTAssertEqual(pathPayload[KEY_BACKGROUND_IMAGE_LOCATION] as? String, "/tmp/bg.png")
    }

    func testProfileMutationTargetAndCodeReviewReloadPolicy() {
        XCTAssertEqual(PTYSessionNaggingPolicy.profileMutationTarget(isDivorced: true), .sessionSpecific)
        XCTAssertEqual(PTYSessionNaggingPolicy.profileMutationTarget(isDivorced: false), .sharedProfileModel)

        XCTAssertTrue(PTYSessionNaggingPolicy.shouldReloadCodeReviewPrompt(mode: .codeReview, hasRawCommand: true))
        XCTAssertFalse(PTYSessionNaggingPolicy.shouldReloadCodeReviewPrompt(mode: .codeReview, hasRawCommand: false))
        XCTAssertFalse(PTYSessionNaggingPolicy.shouldReloadCodeReviewPrompt(mode: .regular, hasRawCommand: true))
    }

    func testArrangementRepairCacheHonorsMissingInputsAndCachesPerGeneration() {
        var cache = PTYSessionArrangementRepairCache()

        // Unconfigured -> false without invoking finder.
        var finderCalls = 0
        XCTAssertFalse(cache.canChangeProfile(currentGeneration: 1, hasWindowArrangements: true) { _ in
            finderCalls += 1
            return true
        })
        XCTAssertEqual(finderCalls, 0)

        // Missing GUID -> false without invoking finder.
        cache.setOriginating(arrangement: [:], name: "Default")
        XCTAssertFalse(cache.canChangeProfile(currentGeneration: 1, hasWindowArrangements: true) { _ in
            finderCalls += 1
            return true
        })
        XCTAssertEqual(finderCalls, 0)

        // Valid arrangement + non-empty arrangements -> finder runs once for generation 1.
        cache.setOriginating(arrangement: [SESSION_ARRANGEMENT_GUID: "session-1"], name: "Default")
        XCTAssertFalse(cache.canChangeProfile(currentGeneration: 1, hasWindowArrangements: false) { _ in
            finderCalls += 1
            return true
        })
        XCTAssertEqual(finderCalls, 0)

        XCTAssertTrue(cache.canChangeProfile(currentGeneration: 1, hasWindowArrangements: true) { guid in
            finderCalls += 1
            XCTAssertEqual(guid, "session-1")
            return true
        })
        XCTAssertTrue(cache.canChangeProfile(currentGeneration: 1, hasWindowArrangements: true) { _ in
            finderCalls += 1
            return false
        })
        XCTAssertEqual(finderCalls, 1)

        // Generation bump invalidates cache and re-runs finder.
        XCTAssertFalse(cache.canChangeProfile(currentGeneration: 2, hasWindowArrangements: true) { _ in
            finderCalls += 1
            return false
        })
        XCTAssertEqual(finderCalls, 2)
    }

    func testReplacingProfileInSessionArrangementUpdatesOnlyMatchingGUID() {
        let replacementProfile: [AnyHashable: Any] = [KEY_GUID: "new-profile", KEY_NAME: "New"]
        let matching: [AnyHashable: Any] = [
            SESSION_ARRANGEMENT_GUID: "target-guid",
            SESSION_ARRANGEMENT_BOOKMARK: [KEY_GUID: "old-profile"]
        ]
        let nonMatching: [AnyHashable: Any] = [
            SESSION_ARRANGEMENT_GUID: "other-guid",
            SESSION_ARRANGEMENT_BOOKMARK: [KEY_GUID: "keep-profile"]
        ]

        let updated = PTYSessionArrangementRepairCache.replacingProfile(
            in: matching,
            matchingGUID: "target-guid",
            with: replacementProfile
        )
        let bookmark = updated[SESSION_ARRANGEMENT_BOOKMARK] as? [AnyHashable: Any]
        XCTAssertEqual(bookmark?[KEY_GUID] as? String, "new-profile")

        let untouched = PTYSessionArrangementRepairCache.replacingProfile(
            in: nonMatching,
            matchingGUID: "target-guid",
            with: replacementProfile
        )
        let keptBookmark = untouched[SESSION_ARRANGEMENT_BOOKMARK] as? [AnyHashable: Any]
        XCTAssertEqual(keptBookmark?[KEY_GUID] as? String, "keep-profile")
    }
}
