//
//  PTYSessionSSHBridgeTests.swift
//  ModernTests
//
//  Unit tests for pure SSH conductor variable snapshot and lifecycle policy
//  extracted into PTYSessionSSHBridge.swift.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionSSHBridgeTests: XCTestCase {
    func testSSHVariableSnapshotAcrossConductorLevels() {
        let localSnapshot = PTYSessionSSHVariableSnapshot.compute(
            hasConductor: false,
            conductorFraming: false,
            conductorHomeDirectory: "/remote/home",
            conductorShell: "zsh",
            conductorUName: "Linux",
            localHomeDirectory: "/Users/local",
            localShell: "fish",
            localUName: "Darwin",
            isOnLocalhost: true
        )
        XCTAssertEqual(
            localSnapshot,
            PTYSessionSSHVariableSnapshot(
                sshIntegrationActive: false,
                sshIntegrationLevel: 0,
                homeDirectory: "/Users/local",
                shell: "fish",
                uname: "Darwin"
            )
        )

        let basicSSHSnapshot = PTYSessionSSHVariableSnapshot.compute(
            hasConductor: true,
            conductorFraming: false,
            conductorHomeDirectory: "/remote/home",
            conductorShell: "zsh",
            conductorUName: "Linux",
            localHomeDirectory: "/Users/local",
            localShell: "fish",
            localUName: "Darwin",
            isOnLocalhost: false
        )
        XCTAssertEqual(
            basicSSHSnapshot,
            PTYSessionSSHVariableSnapshot(
                sshIntegrationActive: true,
                sshIntegrationLevel: 1,
                homeDirectory: nil,
                shell: nil,
                uname: nil
            )
        )

        let framerSSHSnapshot = PTYSessionSSHVariableSnapshot.compute(
            hasConductor: true,
            conductorFraming: true,
            conductorHomeDirectory: "/remote/home",
            conductorShell: "zsh",
            conductorUName: "Linux",
            localHomeDirectory: "/Users/local",
            localShell: "fish",
            localUName: "Darwin",
            isOnLocalhost: false
        )
        XCTAssertEqual(
            framerSSHSnapshot,
            PTYSessionSSHVariableSnapshot(
                sshIntegrationActive: true,
                sshIntegrationLevel: 2,
                homeDirectory: "/remote/home",
                shell: "zsh",
                uname: "Linux"
            )
        )
    }

    func testInitialDirectoryAndStartActionPolicies() {
        // Pending jump initial directory takes priority over profile PWD.
        XCTAssertEqual(
            PTYSessionSSHPolicy.initialDirectoryForHook(isSSHProfileState: true,
                                                        hasExistingConductor: false,
                                                        environmentPWD: "/Users/me",
                                                        nextPendingJumpDirectory: "/var/tmp"),
            "/var/tmp"
        )
        // Profile SSH session without existing conductor uses PWD when no jump dir exists.
        XCTAssertEqual(
            PTYSessionSSHPolicy.initialDirectoryForHook(isSSHProfileState: true,
                                                        hasExistingConductor: false,
                                                        environmentPWD: "/Users/me",
                                                        nextPendingJumpDirectory: nil),
            "/Users/me"
        )
        XCTAssertNil(
            PTYSessionSSHPolicy.initialDirectoryForHook(isSSHProfileState: false,
                                                        hasExistingConductor: false,
                                                        environmentPWD: "/Users/me",
                                                        nextPendingJumpDirectory: nil)
        )
        XCTAssertNil(
            PTYSessionSSHPolicy.initialDirectoryForHook(isSSHProfileState: true,
                                                        hasExistingConductor: true,
                                                        environmentPWD: "/Users/me",
                                                        nextPendingJumpDirectory: nil)
        )

        XCTAssertEqual(
            PTYSessionSSHPolicy.startAction(hasPreviousConductor: false,
                                            remainingPendingJumpsCount: 2,
                                            previousSubsequentJumpsCount: 1),
            .startPendingJumps
        )
        XCTAssertEqual(
            PTYSessionSSHPolicy.startAction(hasPreviousConductor: true,
                                            remainingPendingJumpsCount: 2,
                                            previousSubsequentJumpsCount: 1),
            .startPreviousSubsequentJumps
        )
        XCTAssertEqual(
            PTYSessionSSHPolicy.startAction(hasPreviousConductor: true,
                                            remainingPendingJumpsCount: 0,
                                            previousSubsequentJumpsCount: 0),
            .startNormally
        )
    }

    func testFramerRecoveryAndUnwindCountPolicies() {
        XCTAssertTrue(PTYSessionSSHPolicy.shouldUnhookAllBeforeFramerRecovery(parentDepth: -1))
        XCTAssertFalse(PTYSessionSSHPolicy.shouldUnhookAllBeforeFramerRecovery(parentDepth: 0))
        XCTAssertFalse(PTYSessionSSHPolicy.shouldUnhookAllBeforeFramerRecovery(parentDepth: 2))

        let ancestry = ["leaf", "middle", "root"]
        XCTAssertEqual(PTYSessionSSHPolicy.unwindCount(ancestryClientIDsFromLeafToRoot: ancestry, targetUniqueID: "missing"), 0)
        XCTAssertEqual(PTYSessionSSHPolicy.unwindCount(ancestryClientIDsFromLeafToRoot: ancestry, targetUniqueID: "leaf"), 1)
        XCTAssertEqual(PTYSessionSSHPolicy.unwindCount(ancestryClientIDsFromLeafToRoot: ancestry, targetUniqueID: "middle"), 2)
        XCTAssertEqual(PTYSessionSSHPolicy.unwindCount(ancestryClientIDsFromLeafToRoot: ancestry, targetUniqueID: "root"), 3)
    }
}
