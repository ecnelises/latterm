//
//  PTYSessionTriggersTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionTriggersTests: XCTestCase {
    func testTriggerNamesFormatsTitlesStripsEllipsisAndSkipsInvalidDicts() throws {
        let dicts: [[AnyHashable: Any]] = [
            [
                kTriggerActionKey: "AlertTrigger",
                kTriggerRegexKey: "fatal error"
            ],
            [
                kTriggerActionKey: "BellTrigger",
                kTriggerRegexKey: "done"
            ],
            [
                kTriggerActionKey: "NotARealTriggerClass",
                kTriggerRegexKey: "ignored"
            ],
            [
                kTriggerRegexKey: "missing action"
            ]
        ]

        let alertTrigger = try XCTUnwrap(Trigger(fromUntrustedDict: dicts[0]))
        let bellTrigger = try XCTUnwrap(Trigger(fromUntrustedDict: dicts[1]))
        XCTAssertTrue(type(of: alertTrigger).title.hasSuffix("…"))

        let names = PTYSessionTriggerSupport.triggerNames(from: dicts)
        XCTAssertEqual(names, [
            "\(type(of: alertTrigger).title.removingSuffix("…")) — fatal error",
            "\(type(of: bellTrigger).title.removingSuffix("…")) — done"
        ])
    }

    func testEnabledTriggerIndexesFiltersDisabledEntries() {
        let dicts: [[AnyHashable: Any]] = [
            [kTriggerActionKey: "BellTrigger"],
            [kTriggerActionKey: "BellTrigger", kTriggerDisabledKey: true],
            [kTriggerActionKey: "BellTrigger", kTriggerDisabledKey: false],
            [kTriggerActionKey: "BellTrigger", kTriggerDisabledKey: NSNumber(value: 1)]
        ]

        let indexes = PTYSessionTriggerSupport.enabledTriggerIndexes(from: dicts)
        XCTAssertEqual(indexes, IndexSet([0, 2]))
    }

    func testScrollRangeForStopScrollingInBounds() {
        let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: 150,
            totalScrollbackOverflow: 100,
            screenHeight: 24,
            numberOfLines: 80
        )
        XCTAssertEqual(range?.location, 27)
        XCTAssertEqual(range?.length, 24)
    }

    func testScrollRangeForStopScrollingNegativeAfterOverflowReturnsNil() {
        let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: 99,
            totalScrollbackOverflow: 100,
            screenHeight: 24,
            numberOfLines: 80
        )
        XCTAssertNil(range)
    }

    func testScrollRangeForStopScrollingBeyondNumberOfLinesReturnsNil() {
        let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: 181,
            totalScrollbackOverflow: 100,
            screenHeight: 24,
            numberOfLines: 80
        )
        XCTAssertNil(range)
    }

    func testScrollRangeForStopScrollingNearTopClampsLocationToZero() {
        let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: 105,
            totalScrollbackOverflow: 100,
            screenHeight: 24,
            numberOfLines: 80
        )
        XCTAssertEqual(range?.location, 0)
        XCTAssertEqual(range?.length, 24)
    }

    func testScrollRangeForStopScrollingClampsNonPositiveScreenHeightToOne() {
        let range = PTYSessionTriggerSupport.scrollRangeForStopScrolling(
            absLine: 110,
            totalScrollbackOverflow: 100,
            screenHeight: 0,
            numberOfLines: 80
        )
        XCTAssertEqual(range?.location, 10)
        XCTAssertEqual(range?.length, 1)
    }

    func testCanEnterWorkgroup() {
        XCTAssertTrue(PTYSessionTriggerSupport.canEnterWorkgroup(hasWorkgroup: false, isRestoring: false))
        XCTAssertFalse(PTYSessionTriggerSupport.canEnterWorkgroup(hasWorkgroup: true, isRestoring: false))
        XCTAssertFalse(PTYSessionTriggerSupport.canEnterWorkgroup(hasWorkgroup: false, isRestoring: true))
        XCTAssertFalse(PTYSessionTriggerSupport.canEnterWorkgroup(hasWorkgroup: true, isRestoring: true))
    }

    func testCanExitWorkgroup() {
        XCTAssertFalse(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: false, leaderOnly: false, isLeader: true))
        XCTAssertFalse(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: false, leaderOnly: true, isLeader: true))
        XCTAssertTrue(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: true, leaderOnly: false, isLeader: false))
        XCTAssertTrue(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: true, leaderOnly: false, isLeader: true))
        XCTAssertFalse(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: true, leaderOnly: true, isLeader: false))
        XCTAssertTrue(PTYSessionTriggerSupport.canExitWorkgroup(hasWorkgroup: true, leaderOnly: true, isLeader: true))
    }
}
