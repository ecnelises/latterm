//
//  SSHHostnameFinderTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class SSHHostnameFinderTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHHostnameFinderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testFirstMatchWinsWildcardNegationAndPercentH() throws {
        let includedFile = tempDir.appendingPathComponent("extra.conf")
        try """
        Host inc-*
            HostName %h.included.internal
        """.write(to: includedFile, atomically: true, encoding: .utf8)

        let mainConfig = tempDir.appendingPathComponent("config")
        try """
        # Comment line
        Include "\(includedFile.path)"

        Host prod-* !prod-skip
            HostName %h.corp.example.com

        Host prod-*
            HostName fallback.should.not.win

        Host eq=alias
            HostName=equals-syntax.example.org
        """.write(to: mainConfig, atomically: true, encoding: .utf8)

        let finder = iTermHostnameFinder(configPaths: [mainConfig.path])
        XCTAssertEqual(finder.sshHostname(forHost: "prod-web1"), "prod-web1.corp.example.com")
        // Negated in first Host block, falls through to second Host block:
        XCTAssertEqual(finder.sshHostname(forHost: "prod-skip"), "fallback.should.not.win")
        // Included directive:
        XCTAssertEqual(finder.sshHostname(forHost: "inc-db"), "inc-db.included.internal")
        // `HostName=...` syntax:
        XCTAssertEqual(finder.sshHostname(forHost: "eq=alias"), "equals-syntax.example.org")
        // Unmatched host returns input unchanged:
        XCTAssertEqual(finder.sshHostname(forHost: "unmatched.local"), "unmatched.local")
    }
}
