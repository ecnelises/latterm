import XCTest
@testable import iTerm2SharedARC

final class DynamicProfileFolderMonitorTests: XCTestCase {
    func testReportsChangesInNestedFolderOnMainQueue() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let changed = expectation(description: "profile directory changed")
        var received = false
        let monitor = try XCTUnwrap(DynamicProfileFolderMonitor(paths: [folder.path], latency: 0.05) {
            XCTAssertTrue(Thread.isMainThread)
            if !received {
                received = true
                changed.fulfill()
            }
        })
        try withExtendedLifetime(monitor) {
            try Data("{}".utf8).write(to: nested.appendingPathComponent("profile.json"))
            wait(for: [changed], timeout: 10)
        }
    }
}
