//
//  CommandExecutionTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class CommandExecutionTests: XCTestCase {
    func testBlockingRunCapturesOutputAndExitCode() {
        let runner = iTermBufferedCommandRunner(command: "/bin/echo",
                                                withArguments: ["hello-swift-runner"],
                                                path: "/tmp")
        let rc = runner.blockingRun()
        XCTAssertEqual(rc, 0)
        let text = runner.output.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(text.contains("hello-swift-runner"))
        XCTAssertFalse(runner.truncated)
    }

    func testBufferedCommandRunnerTruncatesWhenExceedingMaximumSize() {
        let runner = iTermBufferedCommandRunner(command: "/bin/sh",
                                                withArguments: ["-c", "printf '0123456789abcdef'"],
                                                path: "/tmp")
        runner.environment = ["PATH": "/usr/bin:/bin"]
        runner.maximumOutputSize = 6
        let rc = runner.blockingRun()
        XCTAssertEqual(rc, 0)
        XCTAssertTrue(runner.truncated)
        XCTAssertEqual(runner.output?.count, 6)
        XCTAssertEqual(String(data: runner.output ?? Data(), encoding: .utf8), "012345")
    }

    func testCommandRunnerFailsGracefullyForMissingBinary() {
        let finished = expectation(description: "missing binary completion")
        var exitStatus: Int32 = 0
        let runner = iTermCommandRunner(command: "/nonexistent/binary/path",
                                        withArguments: [],
                                        path: "/tmp")
        runner.completion = { status in
            exitStatus = status
            finished.fulfill()
        }
        runner.run()
        wait(for: [finished], timeout: 2.0)
        XCTAssertEqual(exitStatus, -1)
    }

    func testCommandRunnerStreamingOutputAndWrite() {
        let finished = expectation(description: "cat stdin round trip")
        var collected = Data()
        var exitStatus: Int32 = -1

        let runner = iTermCommandRunner(command: "/bin/sh",
                                        withArguments: ["-c", "head -c 5"],
                                        path: "/tmp")
        runner.environment = ["PATH": "/usr/bin:/bin"]
        runner.outputHandler = { data, done in
            if let data {
                collected.append(data)
            }
            done()
        }
        runner.completion = { status in
            exitStatus = status
            finished.fulfill()
        }
        runner.run()
        runner.write(Data("abcde".utf8), completion: nil)

        wait(for: [finished], timeout: 5.0)
        XCTAssertEqual(exitStatus, 0)
        XCTAssertEqual(String(data: collected, encoding: .utf8), "abcde")
    }

    func testBackgroundCommandRunnerPromiseDefersUntilFulfill() {
        let finished = expectation(description: "fulfilled promise runs")
        var exitStatus: Int32 = -1
        let promise = iTermBackgroundCommandRunnerPromise(command: "true",
                                                          shell: "/bin/sh",
                                                          title: "PromiseTest")
        promise.path = "/usr/bin:/bin"
        promise.completion = { status in
            exitStatus = status
            finished.fulfill()
        }
        // Unfulfilled run() must be a no-op.
        promise.run()
        XCTAssertEqual(exitStatus, -1)

        promise.fulfill()
        wait(for: [finished], timeout: 5.0)
        XCTAssertEqual(exitStatus, 0)
    }
}
