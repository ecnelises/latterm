//
//  SixelDecoderTests.swift
//  ModernTests
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class SixelDecoderTests: XCTestCase {
    private func pixelRGBA(_ image: NSImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let ptr = rep.bitmapData,
              x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else {
            return nil
        }
        let offset = y * rep.bytesPerRow + x * 4
        return (ptr[offset], ptr[offset + 1], ptr[offset + 2], ptr[offset + 3])
    }

    func testRGBPaletteRepeatCarriageReturnAndNewlineBands() {
        // 4x12 image:
        // - Register 0 (bg): (10%, 20%, 30%) -> (26, 51, 77)
        // - Register 1: pure red (100%, 0%, 0%), top band 4 cols full height ('~' = 0x7E = 63)
        // - Carriage return '$', Register 2: pure green, overwrite first 2 cols top pixel ('@' = 0x40 = 1)
        // - Newline '-', Register 1, bottom band 3 cols full height
        let payload = "\u{1B}P0;0;0q\"1;1;4;12#0;2;10;20;30#1;2;100;0;0!4~$#2;2;0;100;0!2@-#1!3~\u{1B}\\"
        guard let image = SixelDecoder.decodeImage(from: Data(payload.utf8)) else {
            return XCTFail("Expected valid decoded SIXEL image")
        }
        XCTAssertEqual(image.size, NSSize(width: 4, height: 12))

        // Overwritten top-left pixel (x=1, y=0) should be green; (x=1, y=1) stays red.
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 0)?.r, 0)
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 0)?.g, 255)
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 1)?.r, 255)
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 1)?.g, 0)

        // Second band: (x=2, y=8) is red; untouched (x=3, y=8) gets opaque register 0 background.
        XCTAssertEqual(pixelRGBA(image, x: 2, y: 8)?.r, 255)
        let bg = pixelRGBA(image, x: 3, y: 8)
        XCTAssertEqual(bg?.r, 26)
        XCTAssertEqual(bg?.g, 51)
        XCTAssertEqual(bg?.b, 77)
        XCTAssertEqual(bg?.a, 255)
    }

    func testTransparentBackgroundWhenP2EqualsOne() {
        // P2=1 leaves untouched pixels transparent (alpha = 0).
        let payload = "0;1;0\n\u{1B}P0;1;0q\"1;1;4;6#1;2;0;0;100!2~\u{1B}\\"
        guard let image = SixelDecoder.decodeImage(from: Data(payload.utf8)) else {
            return XCTFail("Expected decoded SIXEL image with VT100SixelParser header")
        }
        XCTAssertEqual(image.size, NSSize(width: 4, height: 6))
        XCTAssertEqual(pixelRGBA(image, x: 0, y: 0)?.b, 255)
        XCTAssertEqual(pixelRGBA(image, x: 0, y: 0)?.a, 255)
        XCTAssertEqual(pixelRGBA(image, x: 3, y: 0)?.a, 0)
    }

    func testVT340HLSColorSpaceAndHighPaletteRegister() {
        // VT340 HLS: Hue 0 = Blue, Hue 120 = Red, Hue 240 = Green.
        // Also test register #777 (> 255) to verify 1024-register support without 8-bit truncation.
        let payload = "\u{1B}Pq#300;1;0;50;100~#500;1;120;50;100~#777;1;240;50;100~\u{1B}\\"
        guard let image = SixelDecoder.decodeImage(from: Data(payload.utf8)) else {
            return XCTFail("Expected decoded HLS SIXEL image")
        }
        XCTAssertEqual(image.size, NSSize(width: 3, height: 6))
        XCTAssertEqual(pixelRGBA(image, x: 0, y: 0)?.b, 255)
        XCTAssertEqual(pixelRGBA(image, x: 0, y: 0)?.r, 0)
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 0)?.r, 255)
        XCTAssertEqual(pixelRGBA(image, x: 1, y: 0)?.g, 0)
        XCTAssertEqual(pixelRGBA(image, x: 2, y: 0)?.g, 255)
        XCTAssertEqual(pixelRGBA(image, x: 2, y: 0)?.b, 0)
    }

    func testC1DCSSixelFixtureAndITermImageIntegration() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repoRoot.appendingPathComponent("tests/c1_dcs_sixel.txt")
        let data = try Data(contentsOf: fixtureURL)
        guard let decoded = SixelDecoder.decodeImage(from: data) else {
            return XCTFail("Failed to decode tests/c1_dcs_sixel.txt")
        }
        XCTAssertEqual(decoded.size, NSSize(width: 600, height: 450))

        let factoryImage = iTermImage(sixelData: Data("0;0;0\n\u{1B}Pq#2;2;100;0;0!3~\u{1B}\\".utf8))
        XCTAssertNotNil(factoryImage)
        XCTAssertEqual(factoryImage?.size, NSSize(width: 3, height: 6))
    }

    func testRejectsMalformedAndOversizedInputs() {
        XCTAssertNil(SixelDecoder.decodeImage(from: Data()))
        XCTAssertNil(SixelDecoder.decodeImage(from: Data("hello world".utf8)))
        XCTAssertNil(SixelDecoder.decodeImage(from: Data("\u{1B}Pq\u{1B}\\".utf8)))
        // Excessive repeat count (> 65535) and excessive raster dimensions (> 9999) fail safely.
        XCTAssertNil(SixelDecoder.decodeImage(from: Data("\u{1B}Pq!99999~\u{1B}\\".utf8)))
        XCTAssertNil(SixelDecoder.decodeImage(from: Data("\u{1B}Pq\"1;1;20000;20000~\u{1B}\\".utf8)))
    }
}
