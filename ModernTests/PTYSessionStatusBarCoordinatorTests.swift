//
//  PTYSessionStatusBarCoordinatorTests.swift
//  ModernTests
//
//  Unit tests for status bar styling, profile target selection, and window drag
//  policy extracted into PTYSessionStatusBarCoordinator.swift.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionStatusBarCoordinatorTests: XCTestCase {
    func testSeparatorResolutionMinimalAndCustomAndAllTabStyles() {
        let customColor = NSColor.systemRed

        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: true,
                                                          configuredColor: customColor,
                                                          tabStyle: .TAB_STYLE_DARK),
            .noneForMinimalStyle
        )

        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: customColor,
                                                          tabStyle: .TAB_STYLE_LIGHT),
            .custom(customColor)
        )

        let alpha = PTYSessionStatusBarPolicy.defaultSeparatorAlpha
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_DARK),
            .derivedFromText(appearanceName: .darkAqua, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_DARK_HIGH_CONTRAST),
            .derivedFromText(appearanceName: .darkAqua, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_LIGHT),
            .derivedFromText(appearanceName: .aqua, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_LIGHT_HIGH_CONTRAST),
            .derivedFromText(appearanceName: .aqua, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_AUTOMATIC),
            .derivedFromText(appearanceName: nil, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_COMPACT),
            .derivedFromText(appearanceName: nil, alpha: alpha)
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.separatorResolution(isMinimalWindowStyle: false,
                                                          configuredColor: nil,
                                                          tabStyle: .TAB_STYLE_MINIMAL),
            .derivedFromText(appearanceName: nil, alpha: alpha)
        )
    }

    func testPreferencesAndProfileModelTargetsRespectDivorceAndOverriddenFields() {
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.preferencesTargetForOpen(isDivorced: false,
                                                               overriddenFields: [KEY_STATUS_BAR_LAYOUT]),
            .sharedProfile
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.preferencesTargetForOpen(isDivorced: true,
                                                               overriddenFields: [KEY_NAME]),
            .sharedProfile
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.preferencesTargetForOpen(isDivorced: true,
                                                               overriddenFields: [KEY_SHOW_STATUS_BAR]),
            .sessionSpecific
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.preferencesTargetForOpen(isDivorced: true,
                                                               overriddenFields: [KEY_STATUS_BAR_LAYOUT]),
            .sessionSpecific
        )

        // profileModelTarget checks KEY_STATUS_BAR_LAYOUT only (not KEY_SHOW_STATUS_BAR).
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.profileModelTarget(isDivorced: true,
                                                           overriddenFields: [KEY_SHOW_STATUS_BAR]),
            .sharedProfile
        )
        XCTAssertEqual(
            PTYSessionStatusBarPolicy.profileModelTarget(isDivorced: true,
                                                           overriddenFields: [KEY_STATUS_BAR_LAYOUT]),
            .sessionSpecific
        )
    }

    func testCanDragWindowEvaluatesDelegateOnlyWhenInPaneTitleBar() {
        var delegateCalls = 0
        XCTAssertTrue(
            PTYSessionStatusBarPolicy.canDragWindow(inPaneTitleBar: false) {
                delegateCalls += 1
                return false
            }
        )
        XCTAssertEqual(delegateCalls, 0)

        XCTAssertFalse(
            PTYSessionStatusBarPolicy.canDragWindow(inPaneTitleBar: true) {
                delegateCalls += 1
                return false
            }
        )
        XCTAssertEqual(delegateCalls, 1)

        XCTAssertTrue(
            PTYSessionStatusBarPolicy.canDragWindow(inPaneTitleBar: true) {
                delegateCalls += 1
                return true
            }
        )
        XCTAssertEqual(delegateCalls, 2)
    }
}
