//
//  PTYSessionPasteCoordinatorTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

private final class MockTransferrableFile: TransferrableFile {
    var stopCount = 0

    override func stop() {
        stopCount += 1
    }
}

final class PTYSessionPasteCoordinatorTests: XCTestCase {
    func testResolveNonTextPasteDestination() {
        XCTAssertEqual(
            PTYSessionPastePolicy.resolveNonTextPasteDestination(
                hasDestination: false,
                hasConductor: false,
                isLocalityVerified: false
            ),
            .local
        )
        XCTAssertEqual(
            PTYSessionPastePolicy.resolveNonTextPasteDestination(
                hasDestination: false,
                hasConductor: true,
                isLocalityVerified: false
            ),
            .local
        )
        XCTAssertEqual(
            PTYSessionPastePolicy.resolveNonTextPasteDestination(
                hasDestination: true,
                hasConductor: true,
                isLocalityVerified: false
            ),
            .verifiedRemote
        )
        XCTAssertEqual(
            PTYSessionPastePolicy.resolveNonTextPasteDestination(
                hasDestination: true,
                hasConductor: false,
                isLocalityVerified: true
            ),
            .verifiedRemote
        )
        XCTAssertEqual(
            PTYSessionPastePolicy.resolveNonTextPasteDestination(
                hasDestination: true,
                hasConductor: false,
                isLocalityVerified: false
            ),
            .unverifiedRemote
        )
    }

    func testResolveRemoteTargetHandlesConductorTmuxFallbackAndLocalhost() {
        // Without shell integration remoteHost, framing conductor provides home directory.
        let conductorOnly = PTYSessionPastePolicy.resolveRemoteTarget(
            hasRemoteHost: false,
            username: nil,
            hostname: nil,
            isLocalhost: false,
            workingDirectory: nil,
            hasConductor: true,
            conductorHostname: "dev.example.com",
            conductorUsername: "alice",
            conductorHomeDirectory: "/home/alice",
            canTransferToIdentity: true
        )
        XCTAssertEqual(
            conductorOnly,
            PTYSessionPastePolicy.RemoteSCPTarget(
                hostname: "dev.example.com",
                username: "alice",
                path: "/home/alice"
            )
        )

        // Localhost never uploads even with working directory.
        XCTAssertNil(
            PTYSessionPastePolicy.resolveRemoteTarget(
                hasRemoteHost: true,
                username: "alice",
                hostname: "localhost",
                isLocalhost: true,
                workingDirectory: "/tmp",
                hasConductor: true,
                conductorHostname: "dev.example.com",
                conductorUsername: "alice",
                conductorHomeDirectory: "/home/alice",
                canTransferToIdentity: false
            )
        )

        // Remote host with empty cwd falls back to conductor home directory if conductor can transfer.
        let cwdFallback = PTYSessionPastePolicy.resolveRemoteTarget(
            hasRemoteHost: true,
            username: "bob",
            hostname: "alias-host",
            isLocalhost: false,
            workingDirectory: "",
            hasConductor: true,
            conductorHostname: "real.example.com",
            conductorUsername: "bob",
            conductorHomeDirectory: "/home/bob",
            canTransferToIdentity: true
        )
        XCTAssertEqual(
            cwdFallback,
            PTYSessionPastePolicy.RemoteSCPTarget(
                hostname: "alias-host",
                username: "bob",
                path: "/home/bob"
            )
        )
    }

    func testShouldPasteAfterUploadSupportsSameConductorAlias() {
        XCTAssertTrue(
            PTYSessionPastePolicy.shouldPasteAfterUpload(
                sessionExited: false,
                conductorMatches: true,
                currentHostname: "full.example.com",
                currentUsername: "alice",
                destinationHostname: "short-alias",
                destinationUsername: "alice",
                canTransferToDestination: true,
                canTransferToCurrent: true
            )
        )
        XCTAssertFalse(
            PTYSessionPastePolicy.shouldPasteAfterUpload(
                sessionExited: true,
                conductorMatches: true,
                currentHostname: "host",
                currentUsername: "alice",
                destinationHostname: "host",
                destinationUsername: "alice",
                canTransferToDestination: false,
                canTransferToCurrent: false
            )
        )
        XCTAssertFalse(
            PTYSessionPastePolicy.shouldPasteAfterUpload(
                sessionExited: false,
                conductorMatches: false,
                currentHostname: "host",
                currentUsername: "alice",
                destinationHostname: "host",
                destinationUsername: "alice",
                canTransferToDestination: true,
                canTransferToCurrent: true
            )
        )
    }

    func testUploadBatchOutOfOrderAndPartialFailurePreservesDropOrder() {
        var batch = PTYSessionUploadBatchState()
        let generation = batch.beginGroup(fileCount: 3)
        let t0 = MockTransferrableFile()
        let t1 = MockTransferrableFile()
        let t2 = MockTransferrableFile()
        batch.addTransfer(t0, generation: generation)
        batch.addTransfer(t1, generation: generation)
        batch.addTransfer(t2, generation: generation)

        // Second file fails before markAllStarted even if synchronous.
        XCTAssertNil(batch.recordCompletion(generation: generation, index: 1, success: false, remotePath: "/remote/b.txt"))
        XCTAssertNil(batch.recordCompletion(generation: generation, index: 2, success: true, remotePath: "/remote/c (2).txt"))
        // Even if last async completes before markAllStarted returns, batch waits for markAllStarted.
        XCTAssertNil(batch.recordCompletion(generation: generation, index: 0, success: true, remotePath: "/remote/a.txt"))

        let finished = batch.markAllStarted(generation: generation)
        XCTAssertEqual(finished?.count, 3)
        XCTAssertEqual(finished?[0], "/remote/a.txt")
        XCTAssertNil(finished?[1])
        XCTAssertEqual(finished?[2], "/remote/c (2).txt")

        let formatted = PTYSessionPastePolicy.formatUploadedPathsForPaste(finished ?? []) { "'\($0)'" }
        XCTAssertEqual(formatted, "'/remote/a.txt' '/remote/c (2).txt'")

        batch.finishCompletedGroup(generation: generation)
        XCTAssertFalse(batch.isUploading)
    }

    func testUploadBatchCancellationStopsActiveTransfersAndIgnoresStaleCallbacks() {
        var batch = PTYSessionUploadBatchState()
        let generation = batch.beginGroup(fileCount: 2)
        let t0 = MockTransferrableFile()
        let t1 = MockTransferrableFile()
        batch.addTransfer(t0, generation: generation)
        batch.addTransfer(t1, generation: generation)
        XCTAssertTrue(batch.isUploading)

        let cancelled = batch.cancel()
        XCTAssertEqual(cancelled.count, 2)
        XCTAssertFalse(batch.isUploading)

        // Simulated late/synchronous completion triggered by -stop must be ignored.
        XCTAssertNil(batch.recordCompletion(generation: generation, index: 0, success: true, remotePath: "/remote/a.txt"))
        XCTAssertNil(batch.recordCompletion(generation: generation, index: 1, success: true, remotePath: "/remote/b.txt"))
        XCTAssertNil(batch.markAllStarted(generation: generation))
    }

    func testShouldWatchForBracketedPasteOopsieRequiresFirstChunkAndFlagAndMode() {
        XCTAssertTrue(
            PTYSessionPastePolicy.shouldWatchForBracketedPasteOopsie(
                bytesWritten: 0,
                flags: [.pasteFlagsBracket],
                terminalBracketedPasteMode: true
            )
        )
        XCTAssertFalse(
            PTYSessionPastePolicy.shouldWatchForBracketedPasteOopsie(
                bytesWritten: 4,
                flags: [.pasteFlagsBracket],
                terminalBracketedPasteMode: true
            )
        )
        XCTAssertFalse(
            PTYSessionPastePolicy.shouldWatchForBracketedPasteOopsie(
                bytesWritten: 0,
                flags: [],
                terminalBracketedPasteMode: true
            )
        )
        XCTAssertFalse(
            PTYSessionPastePolicy.shouldWatchForBracketedPasteOopsie(
                bytesWritten: 0,
                flags: [.pasteFlagsBracket],
                terminalBracketedPasteMode: false
            )
        )
    }
}
