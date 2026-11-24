//
//  GzipCodecTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class GzipCodecTests: XCTestCase {
    func testRoundTripCompressionAndDecompression() throws {
        let original = Data(String(repeating: "Latterm terminal recording payload 0123456789\n", count: 500).utf8)
        let compressed = try XCTUnwrap((original as NSData).gzippedData())
        XCTAssertTrue((compressed as NSData).isGzippedData)
        XCTAssertLessThan(compressed.count, original.count)

        let decompressed = try XCTUnwrap((compressed as NSData).gunzippedData())
        XCTAssertEqual(decompressed, original)
    }

    func testEmptyDataReturnsEmptyDataUnchanged() {
        let empty = Data()
        XCTAssertFalse((empty as NSData).isGzippedData)
        XCTAssertEqual((empty as NSData).gzippedData(), empty)
        XCTAssertEqual((empty as NSData).gunzippedData(), empty)
    }

    func testAlreadyGzippedDataIsNotDoubleCompressed() throws {
        let original = Data("hello gzip".utf8)
        let compressed = try XCTUnwrap((original as NSData).gzippedData(compressionLevel: 1.0))
        XCTAssertEqual((compressed as NSData).gzippedData(), compressed)
    }

    func testNonGzippedDataPassedToGunzipReturnsInputUnchanged() {
        let plain = Data("plain text".utf8)
        XCTAssertFalse((plain as NSData).isGzippedData)
        XCTAssertEqual((plain as NSData).gunzippedData(), plain)
    }

    func testTruncatedGzipDataReturnsNil() {
        let truncated = Data([0x1f, 0x8b, 0x08, 0x00])
        XCTAssertTrue((truncated as NSData).isGzippedData)
        XCTAssertNil((truncated as NSData).gunzippedData())
    }
}
