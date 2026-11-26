import XCTest
@testable import iTerm2SharedARC

final class PTYSessionProfileAndLoggingCoordinatorTests: XCTestCase {
    func testAutomaticProfileSwitchFontZoomDelta() {
        XCTAssertEqual(
            PTYSessionAutomaticProfileSwitchPolicy.fontZoomDelta(
                preserveFontSize: true,
                currentPointSize: 16,
                originalPointSize: 12
            ),
            4
        )
        XCTAssertEqual(
            PTYSessionAutomaticProfileSwitchPolicy.fontZoomDelta(
                preserveFontSize: false,
                currentPointSize: 16,
                originalPointSize: 12
            ),
            0
        )
    }

    func testFilteredDivorcedOverridesExcludesGuidAndFontKeysOnlyWhenZoomed() {
        let overridden: Set<String> = [
            KEY_GUID,
            KEY_ORIGINAL_GUID,
            KEY_NORMAL_FONT,
            KEY_NON_ASCII_FONT,
            KEY_FONT_CONFIG,
            KEY_NAME
        ]
        let saved: [AnyHashable: Any] = [
            KEY_GUID: "g1",
            KEY_ORIGINAL_GUID: "g0",
            KEY_NORMAL_FONT: "Menlo 12",
            KEY_NON_ASCII_FONT: "Monaco 12",
            KEY_FONT_CONFIG: "cfg",
            KEY_NAME: "Custom"
        ]

        let zoomed = PTYSessionAutomaticProfileSwitchPolicy.filteredDivorcedOverrides(
            overriddenFields: overridden,
            savedProfileValues: saved,
            fontZoomDelta: 2
        )
        XCTAssertNil(zoomed[KEY_GUID])
        XCTAssertNil(zoomed[KEY_ORIGINAL_GUID])
        XCTAssertNil(zoomed[KEY_NORMAL_FONT])
        XCTAssertNil(zoomed[KEY_NON_ASCII_FONT])
        XCTAssertNil(zoomed[KEY_FONT_CONFIG])
        XCTAssertEqual(zoomed[KEY_NAME] as? String, "Custom")

        let unzoomed = PTYSessionAutomaticProfileSwitchPolicy.filteredDivorcedOverrides(
            overriddenFields: overridden,
            savedProfileValues: saved,
            fontZoomDelta: 0
        )
        XCTAssertNil(unzoomed[KEY_GUID])
        XCTAssertNil(unzoomed[KEY_ORIGINAL_GUID])
        XCTAssertEqual(unzoomed[KEY_NORMAL_FONT] as? String, "Menlo 12")
        XCTAssertEqual(unzoomed[KEY_NON_ASCII_FONT] as? String, "Monaco 12")
        XCTAssertEqual(unzoomed[KEY_FONT_CONFIG] as? String, "cfg")
        XCTAssertEqual(unzoomed[KEY_NAME] as? String, "Custom")
    }

    func testTitleIdentifierPolicy() {
        XCTAssertEqual(
            PTYSessionTitleIdentifierPolicy.uniqueIdentifier(components: .sessionName, titleFuncPlist: nil),
            iTermSessionNameControllerSystemTitleUniqueIdentifier
        )

        let tuple = iTermTuple<NSString, NSString>()
        tuple.firstObject = "Display"
        tuple.secondObject = "fn-id"
        XCTAssertEqual(
            PTYSessionTitleIdentifierPolicy.uniqueIdentifier(components: .custom, titleFuncPlist: tuple.plistValue),
            "fn-id"
        )
        XCTAssertNil(
            PTYSessionTitleIdentifierPolicy.uniqueIdentifier(components: .custom, titleFuncPlist: "not-a-tuple")
        )
    }

    func testLoggingTimestampPolicy() {
        XCTAssertTrue(PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(enabled: true, style: .plainText))
        XCTAssertFalse(PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(enabled: false, style: .plainText))
        XCTAssertFalse(PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(enabled: true, style: .raw))
        XCTAssertFalse(PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(enabled: true, style: .HTML))
        XCTAssertFalse(PTYSessionLoggingTimestampPolicy.shouldIncludePlainTextTimestamp(enabled: true, style: .asciicast))
    }

    func testTabStatusNotificationPolicy() {
        XCTAssertFalse(PTYSessionTabStatusNotificationPolicy.shouldPostNotification(previousStatusText: nil, newStatusText: nil, priorityAllowsNotification: true))
        XCTAssertFalse(PTYSessionTabStatusNotificationPolicy.shouldPostNotification(previousStatusText: "wait", newStatusText: "wait", priorityAllowsNotification: true))
        XCTAssertFalse(PTYSessionTabStatusNotificationPolicy.shouldPostNotification(previousStatusText: nil, newStatusText: "wait", priorityAllowsNotification: false))
        XCTAssertTrue(PTYSessionTabStatusNotificationPolicy.shouldPostNotification(previousStatusText: nil, newStatusText: "wait", priorityAllowsNotification: true))
        XCTAssertTrue(PTYSessionTabStatusNotificationPolicy.shouldPostNotification(previousStatusText: "work", newStatusText: "wait", priorityAllowsNotification: true))
    }
}
