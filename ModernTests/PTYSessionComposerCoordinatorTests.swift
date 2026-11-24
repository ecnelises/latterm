//
//  PTYSessionComposerCoordinatorTests.swift
//  ModernTests
//
//  Unit tests for composer frame layout and policy logic extracted into
//  PTYSessionComposerCoordinator.swift.
//

import Carbon.HIToolbox
import XCTest
@testable import iTerm2SharedARC

final class PTYSessionComposerCoordinatorTests: XCTestCase {
    func testAutoComposerFrameUsesPromptMarkAndRespectsTitleBarAndClamping() {
        let withPromptMark = PTYSessionComposerLayoutCalculator.autoComposerFrame(
            .init(previousFrame: NSRect(x: 10, y: 0, width: 200, height: 40),
                  paneSize: NSSize(width: 500, height: 300),
                  desiredHeight: 60,       // ceil(60 / 15) = 4 rows
                  lineHeight: 15,
                  cursorY: 5,
                  promptStartY: 112,       // lineAbove = 112 - 10 - 100 = 2 -> actualFree = 24 - 2 = 22
                  totalScrollbackOverflow: 10,
                  numberOfScrollbackLines: 100,
                  screenHeight: 24,
                  verticalMargin: 4,
                  titleBarHeight: 22)
        )
        // width = 500 - 20 = 480
        // linesOfHeight = min(22, 4) = 4 -> height = 4.5 * 15 = 67.5
        // gridOffsetInRows = 24 - 4 = 20 -> top = 4 + 22 + 300 = 326
        // y = max(0, 300 - 326 - 67.5) = 0
        XCTAssertEqual(withPromptMark.origin.x, 10)
        XCTAssertEqual(withPromptMark.size.width, 480)
        XCTAssertEqual(withPromptMark.size.height, 67.5)
        XCTAssertEqual(withPromptMark.origin.y, 0)

        // Fallback to cursorY when prompt mark is absent; verify non-zero y and clamping.
        let fallbackCursor = PTYSessionComposerLayoutCalculator.autoComposerFrame(
            .init(previousFrame: NSRect(x: 8, y: 0, width: 100, height: 20),
                  paneSize: NSSize(width: 400, height: 300),
                  desiredHeight: 100,      // desiredLines = 10, clamped to actualFree = 10 - (7 + 1) = 2
                  lineHeight: 10,
                  cursorY: 7,
                  promptStartY: nil,
                  totalScrollbackOverflow: 0,
                  numberOfScrollbackLines: 0,
                  screenHeight: 10,
                  verticalMargin: 5,
                  titleBarHeight: 0)
        )
        // linesOfHeight = 2 -> height = 25, gridOffsetInRows = 8 -> top = 5 + 80 = 85 -> y = 300 - 85 - 25 = 190
        XCTAssertEqual(fallbackCursor.origin.x, 8)
        XCTAssertEqual(fallbackCursor.size.width, 384)
        XCTAssertEqual(fallbackCursor.size.height, 25)
        XCTAssertEqual(fallbackCursor.origin.y, 190)
    }

    func testTopComposerFrameEnforcesMinimumWidthAndClampsOverage() {
        let narrow = PTYSessionComposerLayoutCalculator.topComposerFrame(
            .init(previousFrame: NSRect(x: 20, y: 0, width: 150, height: 30),
                  paneSize: NSSize(width: 180, height: 200),
                  desiredHeight: 50,
                  preferredOffsetFromTop: 15)
        )
        // maxWidth = 140 < 217 -> clamped to 217; y = 200 - 50 - 15 = 135; overage = 185 - 200 <= 0
        XCTAssertEqual(narrow.size.width, 217)
        XCTAssertEqual(narrow.origin.y, 135)
        XCTAssertEqual(narrow.size.height, 50)

        let overflow = PTYSessionComposerLayoutCalculator.topComposerFrame(
            .init(previousFrame: NSRect(x: 10, y: 0, width: 300, height: 30),
                  paneSize: NSSize(width: 400, height: 100),
                  desiredHeight: 80,
                  preferredOffsetFromTop: -30)
        )
        // initial y = 100 - 80 - (-30) = 50 -> y + height = 130 -> overage = 30 -> y = max(0, 50 - 30) = 20
        XCTAssertEqual(overflow.size.width, 380)
        XCTAssertEqual(overflow.origin.y, 20)
        XCTAssertEqual(overflow.size.height, 80)
    }

    func testKeyEquivalentAndKeyBindingAndFetchPolicies() {
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        XCTAssertEqual(
            PTYSessionComposerPolicy.keyEquivalentAction(modifierFlags: cmdShift, keyCode: UInt16(kVK_UpArrow)),
            .previousMark
        )
        XCTAssertEqual(
            PTYSessionComposerPolicy.keyEquivalentAction(modifierFlags: cmdShift, keyCode: UInt16(kVK_DownArrow)),
            .nextMark
        )
        XCTAssertEqual(
            PTYSessionComposerPolicy.keyEquivalentAction(modifierFlags: [.command, .shift, .option],
                                                         keyCode: UInt16(kVK_UpArrow)),
            .none
        )
        XCTAssertEqual(
            PTYSessionComposerPolicy.keyEquivalentAction(modifierFlags: cmdShift, keyCode: UInt16(kVK_LeftArrow)),
            .none
        )

        // Remote host depends on conductor framing; local host disallows tmux.
        XCTAssertTrue(PTYSessionComposerPolicy.shouldFetchSuggestions(
            isRemoteHost: true, conductorFraming: true, hasTmuxController: true
        ))
        XCTAssertFalse(PTYSessionComposerPolicy.shouldFetchSuggestions(
            isRemoteHost: true, conductorFraming: false, hasTmuxController: false
        ))
        XCTAssertFalse(PTYSessionComposerPolicy.shouldFetchSuggestions(
            isRemoteHost: false, conductorFraming: false, hasTmuxController: true
        ))
        XCTAssertTrue(PTYSessionComposerPolicy.shouldFetchSuggestions(
            isRemoteHost: false, conductorFraming: false, hasTmuxController: false
        ))

        // Key binding policy ignores sendsText and navigation keystrokes.
        XCTAssertFalse(PTYSessionComposerPolicy.shouldHandleKeyBinding(hasAction: false, sendsText: false, isNavigation: false))
        XCTAssertFalse(PTYSessionComposerPolicy.shouldHandleKeyBinding(hasAction: true, sendsText: true, isNavigation: false))
        XCTAssertFalse(PTYSessionComposerPolicy.shouldHandleKeyBinding(hasAction: true, sendsText: false, isNavigation: true))
        XCTAssertTrue(PTYSessionComposerPolicy.shouldHandleKeyBinding(hasAction: true, sendsText: false, isNavigation: false))
    }

    func testPreparedAutoComposerCommandPrependsControlUOnlyForShellProvidedText() {
        XCTAssertEqual(
            PTYSessionComposerPolicy.preparedAutoComposerCommand("ls -la\n", haveShellProvidedText: false),
            "ls -la\n"
        )
        XCTAssertEqual(
            PTYSessionComposerPolicy.preparedAutoComposerCommand("ls -la\n", haveShellProvidedText: true),
            "\u{15}ls -la\n"
        )
    }
}
