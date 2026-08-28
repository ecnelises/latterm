//
//  iTermSoftwareUpdateServiceTests.swift
//  ModernTests
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class iTermSoftwareUpdateServiceTests: XCTestCase {
    private final class FakeDriver: NSObject, iTermSoftwareUpdateDriver {
        var automaticallyChecksForUpdates = true
        let willRestartNotification = Notification.Name("iTermSoftwareUpdateServiceTestsWillRestart")
        var checkedSender: AnyObject?
        var ownsWindowController = false
        var comparisonResult = ComparisonResult.orderedSame
        var comparedVersions: (String, String)?

        func checkForUpdates(_ sender: Any?) {
            checkedSender = sender as AnyObject?
        }

        func isUpdaterOwnedWindowController(_ windowController: NSWindowController) -> Bool {
            return ownsWindowController
        }

        func compareVersion(_ version: String, toVersion otherVersion: String) -> ComparisonResult {
            comparedVersions = (version, otherVersion)
            return comparisonResult
        }
    }

    func testForwardsUpdaterOperationsWithoutExposingDriverType() {
        let driver = FakeDriver()
        let service = iTermSoftwareUpdateService(driver: driver)
        let sender = NSObject()

        XCTAssertTrue(service.automaticallyChecksForUpdates)
        service.checkForUpdates(sender)
        XCTAssertTrue(driver.checkedSender === sender)

        let windowController = NSWindowController()
        driver.ownsWindowController = true
        XCTAssertTrue(service.isUpdaterOwnedWindowController(windowController))
        XCTAssertFalse(service.isUpdaterOwnedWindowController(nil))

        driver.comparisonResult = .orderedDescending
        XCTAssertTrue(service.isVersion("3.8", newerThan: "3.7"))
        XCTAssertEqual(driver.comparedVersions?.0, "3.8")
        XCTAssertEqual(driver.comparedVersions?.1, "3.7")
    }

    func testTranslatesDriverRestartIntoStableApplicationState() {
        let driver = FakeDriver()
        let service = iTermSoftwareUpdateService(driver: driver)
        let restarted = expectation(description: "service restart notification")
        let token = NotificationCenter.default.addObserver(
            forName: .iTermSoftwareUpdateWillRestart,
            object: service,
            queue: nil) { _ in
                restarted.fulfill()
            }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertFalse(service.isRestarting)
        NotificationCenter.default.post(name: driver.willRestartNotification, object: nil)

        wait(for: [restarted], timeout: 1)
        XCTAssertTrue(service.isRestarting)
    }
}
