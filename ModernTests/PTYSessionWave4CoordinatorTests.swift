//
//  PTYSessionWave4CoordinatorTests.swift
//  ModernTests
//

import Cocoa
import XCTest
@testable import iTerm2SharedARC

final class PTYSessionWave4CoordinatorTests: XCTestCase {
    private final class MockEchoProbeHost: NSObject, PTYSessionEchoProbeHost {
        var tmuxMode: PTYSessionTmuxMode = TMUX_NONE
        var echoProbeWindow: NSWindow? = nil
        var notedUserInputCount = 0
        var writtenStrings: [String] = []
        var writtenData: [Data] = []
        var shownMessages: [(message: String, duration: TimeInterval)] = []
        var focusReportingDeltas: [Int] = []
        var sendPasswordCount = 0
        var resetCount = 0

        func echoProbeNoteUserInput() {
            notedUserInputCount += 1
        }

        func echoProbeWriteString(_ string: String) {
            writtenStrings.append(string)
        }

        func echoProbeWriteLatin1Data(_ data: Data) {
            writtenData.append(data)
        }

        func echoProbeShowUnobtrusiveMessage(_ message: String, duration: TimeInterval) {
            shownMessages.append((message, duration))
        }

        func echoProbeIncrementDisableFocusReporting(_ delta: Int) {
            focusReportingDeltas.append(delta)
        }

        func echoProbeSendPassword() {
            sendPasswordCount += 1
        }

        func echoProbeReset() {
            resetCount += 1
        }
    }

    func testEchoProbePolicyMessagesAndSuppression() {
        XCTAssertEqual(PTYSessionEchoProbePolicy.passwordSentMessage(sendReturnAfterPassword: true),
                       "Password sent.")
        XCTAssertEqual(PTYSessionEchoProbePolicy.passwordSentMessage(sendReturnAfterPassword: false),
                       "Password sent (press Return).")
        XCTAssertTrue(PTYSessionEchoProbePolicy.shouldSuppressWrite(tmuxMode: TMUX_GATEWAY))
        XCTAssertFalse(PTYSessionEchoProbePolicy.shouldSuppressWrite(tmuxMode: TMUX_NONE))
        XCTAssertFalse(PTYSessionEchoProbePolicy.shouldSuppressWrite(tmuxMode: TMUX_CLIENT))
    }

    func testEchoProbeCoordinatorRoutesWritesAndPermissionConfirmation() {
        let host = MockEchoProbeHost()
        var sendReturn = true
        var userConfirmed = true
        let coordinator = PTYSessionEchoProbeCoordinator(
            host: host,
            shouldSendReturnAfterPassword: { sendReturn },
            confirmEchoedPassword: { _ in userConfirmed }
        )
        let probe = iTermEchoProbe(queue: DispatchQueue.main)

        coordinator.echoProbe(probe, write: "secret")
        XCTAssertEqual(host.notedUserInputCount, 1)
        XCTAssertEqual(host.writtenStrings, ["secret"])
        XCTAssertEqual(host.shownMessages.last?.message, "Password sent.")
        XCTAssertEqual(host.shownMessages.last?.duration, 3)

        sendReturn = false
        coordinator.echoProbe(probe, write: "secret2")
        XCTAssertEqual(host.shownMessages.last?.message, "Password sent (press Return).")

        let payload = Data([0x41, 0x42])
        coordinator.echoProbe(probe, write: payload)
        XCTAssertEqual(host.writtenData, [payload])

        // Tmux gateway suppresses writes but still records user input
        host.tmuxMode = TMUX_GATEWAY
        coordinator.echoProbe(probe, write: "ignored")
        coordinator.echoProbe(probe, write: Data([0x43]))
        XCTAssertEqual(host.writtenStrings, ["secret", "secret2"])
        XCTAssertEqual(host.writtenData, [payload])
        XCTAssertEqual(host.notedUserInputCount, 5)

        // Confirm echoed password
        coordinator.sendPasswordAfterGettingPermission()
        XCTAssertEqual(host.sendPasswordCount, 1)
        XCTAssertEqual(host.resetCount, 0)

        // Decline echoed password -> decrements focus reporting and resets probe
        userConfirmed = false
        coordinator.sendPasswordAfterGettingPermission()
        XCTAssertEqual(host.focusReportingDeltas, [-1])
        XCTAssertEqual(host.resetCount, 1)

        // Succeed -> decrements focus reporting
        coordinator.echoProbeDidSucceed(probe)
        XCTAssertEqual(host.focusReportingDeltas, [-1, -1])
        XCTAssertTrue(coordinator.echoProbeShouldSendPassword(probe))
    }

    func testBadgeFontPolicyFallbackAndBoldConversion() {
        var requestedNames: [String] = []
        let helvetica = NSFont(name: "Helvetica", size: 14) ?? NSFont.systemFont(ofSize: 14)
        let resolved = PTYSessionBadgePolicy.resolveFont(
            named: "NonExistentFontXYZ",
            pointSize: 14,
            isBold: false,
            fontFactory: { name, _ in
                requestedNames.append(name)
                return name == "Helvetica" ? helvetica : nil
            }
        )
        XCTAssertEqual(requestedNames, ["NonExistentFontXYZ", "Helvetica"])
        XCTAssertEqual(resolved, helvetica)

        var boldConverted = false
        let boldResolved = PTYSessionBadgePolicy.resolveFont(
            named: "Menlo",
            pointSize: 16,
            isBold: true,
            fontFactory: { _, _ in helvetica },
            boldConverter: { font in
                boldConverted = true
                return font
            }
        )
        XCTAssertTrue(boldConverted)
        XCTAssertEqual(boldResolved, helvetica)
    }

    func testInteractionCoordinatorBadgeStateAndSafeNilSessionDefaults() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let coordinator = PTYSessionInteractionCoordinator(session: session)
        coordinator.updateBadge(fontName: "Menlo", sizeFraction: NSSize(width: 0.4, height: 0.25))
        XCTAssertEqual(coordinator.badgeFontName, "Menlo")
        XCTAssertEqual(coordinator.badgeLabelSizeFraction().width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(coordinator.badgeLabelSizeFraction().height, 0.25, accuracy: 0.0001)
        XCTAssertNotNil(coordinator.badgeLabelFont(ofSize: 12))
        XCTAssertFalse(coordinator.popupShouldTakePrefixFromScreen())
        XCTAssertEqual(coordinator.popupWords(beforeInsertionPoint: 2), [""])
        XCTAssertEqual(coordinator.popupScreenVisibleFrame(), NSRect.zero)
        XCTAssertFalse(coordinator.popupWindowIsInFloatingHotkeyWindow())
        XCTAssertTrue(coordinator.popupVT100Screen() === session.screen)
        XCTAssertTrue(coordinator.popupPresenter() === session)
    }
}
