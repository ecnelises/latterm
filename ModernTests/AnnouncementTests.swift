//
//  AnnouncementTests.swift
//  ModernTests
//

import Cocoa
import XCTest
@testable import iTerm2SharedARC

private final class MockAnnouncementDelegate: NSObject, iTermAnnouncementDelegate {
    var dismissedAnnouncements: [iTermAnnouncementViewController] = []

    func announcementWillDismiss(_ announcement: iTermAnnouncementViewController) {
        dismissedAnnouncements.append(announcement)
    }
}

final class AnnouncementTests: XCTestCase {
    private func makeOptionKeyDown(_ key: String,
                                   modifiers: NSEvent.ModifierFlags = [.option]) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: 0)!
    }

    func testAnnouncementActionInvocationAndSingleDismiss() {
        let delegate = MockAnnouncementDelegate()
        var receivedIndices: [Int32] = []
        let controller = iTermAnnouncementViewController.announcement(
            withTitle: "Test banner",
            style: .warning,
            withActions: ["_Yes", "_No", "_Cancel"]) { index in
            receivedIndices.append(index)
        }
        controller.delegate = delegate

        let view = controller.view as? iTermAnnouncementView
        XCTAssertNotNil(view)

        // Option+N matches index 1 ("_No").
        XCTAssertTrue(controller.handleKeyDown(makeOptionKeyDown("n")))
        // Second call after dismissal must not invoke completion or delegate again.
        controller.dismiss()

        XCTAssertEqual(receivedIndices, [1, -2])
        XCTAssertEqual(delegate.dismissedAnnouncements.count, 1)
    }

    func testAnnouncementMarkdownAndDismissOnKeyDown() {
        let delegate = MockAnnouncementDelegate()
        var receivedIndices: [Int32] = []
        let controller = iTermAnnouncementViewController.announcement(
            withMarkdownTitle: "Hello **World**",
            style: .question,
            withActions: ["_Accept"]) { index in
            receivedIndices.append(index)
        }
        controller.delegate = delegate

        let view = controller.view as? iTermAnnouncementView
        XCTAssertNotNil(view)
        XCTAssertTrue(view?.isMarkdown ?? false)

        // Setting dismissOnKeyDown appends notice and stays sticky even if set to false.
        controller.dismissOnKeyDown = true
        controller.dismissOnKeyDown = false
        XCTAssertTrue(controller.dismissOnKeyDown)

        // Updating title after load updates view title.
        controller.title = "Updated *Markdown*"
        XCTAssertEqual(view?.title, "Updated *Markdown*")

        // Unmatched key dismisses when dismissOnKeyDown is enabled.
        XCTAssertTrue(controller.handleKeyDown(makeOptionKeyDown("x", modifiers: [])))
        XCTAssertEqual(receivedIndices, [-2])
        XCTAssertEqual(delegate.dismissedAnnouncements.count, 1)
    }

    func testEstimatedHeightClampsWithinBounds() {
        let singleLine = iTermAnnouncementView.estimatedHeight(forWidth: 300, text: "short")
        let twoLines = iTermAnnouncementView.estimatedHeight(forWidth: 300, text: "line 1\nline 2")
        let manyLines = iTermAnnouncementView.estimatedHeight(forWidth: 300, text: "1\n2\n3\n4\n5\n6")
        let threeLines = iTermAnnouncementView.estimatedHeight(forWidth: 300, text: "1\n2\n3")

        XCTAssertGreaterThan(singleLine, 29)
        XCTAssertGreaterThan(twoLines, singleLine)
        XCTAssertEqual(manyLines, threeLines, accuracy: 0.01)
    }

    func testTimeoutAutoDismissesAnnouncement() {
        let delegate = MockAnnouncementDelegate()
        var receivedIndices: [Int32] = []
        let controller = iTermAnnouncementViewController.announcement(
            withTitle: "Timed notice",
            style: .warning,
            withActions: []) { index in
            receivedIndices.append(index)
        }
        controller.delegate = delegate
        _ = controller.view

        XCTAssertTrue(controller.shouldBecomeVisible())
        controller.setTimeout(0.05)

        let deadline = Date().addingTimeInterval(1.0)
        while controller.shouldBecomeVisible() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }

        XCTAssertFalse(controller.shouldBecomeVisible())
        XCTAssertEqual(receivedIndices, [-2])
        XCTAssertEqual(delegate.dismissedAnnouncements.count, 1)
    }
}
