//
//  iTermVersionComparatorTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class iTermVersionComparatorTests: XCTestCase {
    private func assertOrder(
        _ version: String,
        _ otherVersion: String,
        _ expected: ComparisonResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            iTermVersionComparator.compareVersion(version, toVersion: otherVersion),
            expected,
            file: file,
            line: line)
    }

    func testDottedNumericVersions() {
        assertOrder("1.0", "1.1", .orderedAscending)
        assertOrder("1.0", "1.0", .orderedSame)
        assertOrder("2.0", "1.1", .orderedDescending)
        assertOrder("0.1", "0.0.1", .orderedDescending)
        assertOrder("0.1", "0.1.2", .orderedAscending)
        assertOrder("3.10.12", "3.9.20", .orderedDescending)
        assertOrder("3.10.00012", "3.10.12", .orderedSame)
    }

    func testPrereleaseVersionsSortBeforeFinalVersions() {
        assertOrder("1.5.5", "1.5.6a1", .orderedAscending)
        assertOrder("1.1.0b1", "1.1.0b2", .orderedAscending)
        assertOrder("1.0a1", "1.0b1", .orderedAscending)
        assertOrder("1.0b1", "1.0", .orderedAscending)
        assertOrder("1.0rc", "1.0", .orderedAscending)
        assertOrder("1.0pre1", "1.0", .orderedAscending)
    }

    func testBuildNumbersAndLargeNumericParts() {
        assertOrder("1.0 (1234)", "1.0 (1235)", .orderedAscending)
        assertOrder("1.0b1 (1234)", "1.0 (1234)", .orderedAscending)
        assertOrder("2.0.0.2429", "2.0.0.2430", .orderedAscending)
        assertOrder("1.99999999999999999999", "1.100000000000000000000", .orderedAscending)
    }
}
