import XCTest
@testable import iTerm2SharedARC

final class CrashReporterTests: XCTestCase {
    private let executablePath = "/Users/developer/Applications/Latterm.app/Contents/MacOS/Latterm"
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func diagnostic(path: String? = nil, test: Bool = false) throws -> String {
        let details: [String: Any] = [
            "procPath": path ?? executablePath,
            "usedImages": test ? [["path": "/Tests/ModernTests.xctest/Contents/MacOS/ModernTests"]] : []
        ]
        let data = try JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted])
        return "{}\n" + String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    private func writeReport(_ name: String, date: Date, path: String? = nil, test: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try diagnostic(path: path, test: test).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testRecognizesRedactedHomeAndRejectsOtherInstallations() throws {
        let redacted = try diagnostic(path: "/Users/USER/Applications/Latterm.app/Contents/MacOS/Latterm")
        XCTAssertTrue(CrashReport.belongsToApplication(redacted, executablePath: executablePath))
        let other = try diagnostic(path: "/Applications/Latterm.app/Contents/MacOS/Latterm")
        XCTAssertFalse(CrashReport.belongsToApplication(other, executablePath: executablePath))
    }

    func testRejectsTestHostCrashesAndMalformedReports() throws {
        XCTAssertFalse(CrashReport.belongsToApplication(try diagnostic(test: true), executablePath: executablePath))
        XCTAssertFalse(CrashReport.belongsToApplication("not a report", executablePath: executablePath))
        XCTAssertFalse(CrashReport.belongsToApplication("{}\n{}", executablePath: executablePath))
    }

    func testFindsLatestMatchingReportWithoutChangingFiles() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try writeReport("Latterm-old.ips", date: date.addingTimeInterval(-1))
        let expected = try writeReport("Latterm-current.ips", date: date)
        try writeReport("Latterm-test.ips", date: date.addingTimeInterval(1), test: true)
        try writeReport("Latterm-other.ips", date: date.addingTimeInterval(2),
                        path: "/Applications/Latterm.app/Contents/MacOS/Latterm")
        try writeReport("AnotherApp.ips", date: date.addingTimeInterval(3))
        let original = try Data(contentsOf: expected)
        let report = CrashReport.latest(in: [directory, directory.appendingPathComponent("missing")],
                                        executablePath: executablePath, after: .distantPast)
        XCTAssertEqual(report?.url.resolvingSymlinksInPath(), expected.resolvingSymlinksInPath())
        XCTAssertEqual(report?.date, date)
        XCTAssertEqual(try Data(contentsOf: expected), original)
        XCTAssertNil(CrashReport.latest(in: [directory], executablePath: executablePath, after: date))
    }

    func testAcknowledgementKeepsSubsecondPrecision() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        try writeReport("Latterm-new.ips", date: date)
        XCTAssertNotNil(CrashReport.latest(in: [directory], executablePath: executablePath,
                                          after: date.addingTimeInterval(-0.125)))
        XCTAssertNil(CrashReport.latest(in: [directory], executablePath: executablePath, after: date))
    }

    func testCollectsAllRotatedErrorLogsWithoutDeletingOrRewritingThem() throws {
        let text = try diagnostic()
        let url = directory.appendingPathComponent("Latterm.ips")
        try text.write(to: url, atomically: true, encoding: .utf8)
        for index in 0..<3 {
            try "error-\(index)".write(to: directory.appendingPathComponent("log.\(index).txt"),
                                     atomically: true, encoding: .utf8)
        }
        let report = CrashReport(url: url, date: Date(), text: text)
        let exported = report.exportText(errorLogDirectory: directory)
        XCTAssertTrue(exported.hasPrefix(text))
        for index in 0..<3 {
            XCTAssertTrue(exported.contains("error-\(index)"))
            XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("log.\(index).txt"),
                                      encoding: .utf8), "error-\(index)")
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
        XCTAssertEqual(report.exportText(errorLogDirectory: nil), text)
    }

    func testReadsLegacyAppendedLogsWithoutDuplicatingThem() throws {
        let text = try diagnostic() + "\n~~ Error Logs ~~\nalready attached"
        XCTAssertTrue(CrashReport.belongsToApplication(text, executablePath: executablePath))
        let report = CrashReport(url: directory.appendingPathComponent("Latterm.ips"), date: Date(), text: text)
        XCTAssertEqual(report.exportText(errorLogDirectory: directory), text)
    }

    func testWindowCopiesAndExportsExactlyThePreviewedText() throws {
        let text = try diagnostic() + "\nExample log: 中文 & more"
        let report = CrashReport(url: directory.appendingPathComponent("Latterm.ips"), date: Date(), text: text)
        var dismissed = false
        let controller = CrashReportWindowController(report: report, text: text) {
            dismissed = true
        }
        XCTAssertEqual(controller.recipient, "fwage73@gmail.com")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        controller.copyLog(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        let exported = directory.appendingPathComponent("export.txt")
        try controller.exportLog(to: exported)
        XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8), text)
        let content = try XCTUnwrap(controller.window?.contentView)
        let titles = content.subviews.compactMap { ($0 as? NSButton)?.title }
        XCTAssertEqual(titles, ["Copy Log", "Export…", "Email Draft…", "Dismiss"])
        let emailButton = try XCTUnwrap(content.subviews.compactMap { $0 as? NSButton }
            .first { $0.title == "Email Draft…" })
        XCTAssertTrue(emailButton.isEnabled)
        XCTAssertTrue(content.subviews.compactMap { $0 as? NSTextField }
            .contains { $0.stringValue.contains(controller.recipient) })
        let scroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
        let preview = try XCTUnwrap(scroll.documentView as? NSTextView)
        XCTAssertEqual(preview.string, text)
        XCTAssertFalse(preview.isEditable)
        XCTAssertTrue(controller.window?.responds(to: NSSelectorFromString("closeCurrentSession:")) == true)
        for size in [NSSize(width: 700, height: 440), NSSize(width: 1000, height: 700)] {
            controller.window?.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            for child in content.subviews {
                XCTAssertTrue(content.bounds.contains(child.frame))
            }
        }
        XCTAssertFalse(dismissed)
        controller.close()
        XCTAssertTrue(dismissed)
    }
}
