//
//  MetalMemoryOptimizationTests.swift
//  ModernTests
//

import Metal
import XCTest
@testable import iTerm2SharedARC

final class MetalMemoryOptimizationTests: XCTestCase {
    private func makeDeviceOrSkip() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable in test environment")
        }
        return device
    }

    private func makeBitmap(width: Int = 8, height: Int = 16) -> iTermCharacterBitmap {
        let bitmap = iTermCharacterBitmap()
        bitmap.size = CGSize(width: width, height: height)
        bitmap.data = NSMutableData(length: width * height * 4) ?? NSMutableData()
        return bitmap
    }

    private func makeGlyphKey(code: unichar) -> iTermGlyphKey {
        var repr = iTermMetalGlyphKey()
        repr.type = .regular
        repr.payload.regular.code = code
        repr.payload.regular.drawable = true
        return iTermGlyphKeyMake(&repr)
    }

    func testMixedSizeBufferPoolMatchesExactAndNextLargerAndPurges() throws {
        let device = try makeDeviceOrSkip()
        let pool = iTermMetalMixedSizeBufferPool(device: device, capacity: 4, name: "test")

        let b128: MTLBuffer
        let b256: MTLBuffer
        do {
            let ctx = iTermMetalBufferPoolContext()
            let payload128 = [UInt8](repeating: 0xAA, count: 128)
            let payload256 = [UInt8](repeating: 0xBB, count: 256)
            b128 = payload128.withUnsafeBytes { ptr in
                pool.requestBuffer(from: ctx, size: 128, bytes: ptr.baseAddress!)
            }
            b256 = payload256.withUnsafeBytes { ptr in
                pool.requestBuffer(from: ctx, size: 256, bytes: ptr.baseAddress!)
            }
            XCTAssertEqual(b128.length, 128)
            XCTAssertEqual(b256.length, 256)
        }
        // ctx deallocated -> b128 and b256 returned to pool

        do {
            let ctx = iTermMetalBufferPoolContext()
            // Exact match via requestBuffer(from:size:) (previously used strict > and missed exact matches)
            let exact = pool.requestBuffer(from: ctx, size: 128)
            XCTAssertTrue(exact === b128)

            // Next-larger match
            let nextLarger = pool.requestBuffer(from: ctx, size: 200)
            XCTAssertTrue(nextLarger === b256)
        }

        // Size 0 edge case (previously underflowed unsigned size_t subtraction)
        do {
            let ctx = iTermMetalBufferPoolContext()
            let zeroMatch = pool.requestBuffer(from: ctx, size: 0)
            XCTAssertTrue(zeroMatch === b128)
        }

        // Purge removes all cached buffers so a subsequent request allocates a new one
        pool.purge()
        do {
            let ctx = iTermMetalBufferPoolContext()
            let fresh = pool.requestBuffer(from: ctx, size: 128)
            XCTAssertFalse(fresh === b128)
            XCTAssertFalse(fresh === b256)
            XCTAssertEqual(fresh.length, 128)
        }
    }

    func testFixedSizeBufferPoolReusesAndPurges() throws {
        let device = try makeDeviceOrSkip()
        let pool = iTermMetalBufferPool(device: device, bufferSize: 64)

        let first: MTLBuffer
        do {
            let ctx = iTermMetalBufferPoolContext()
            first = pool.requestBuffer(from: ctx)
            XCTAssertEqual(first.length, 64)
        }

        do {
            let ctx = iTermMetalBufferPoolContext()
            let reused = pool.requestBuffer(from: ctx)
            XCTAssertTrue(reused === first)
        }

        pool.purge()
        do {
            let ctx = iTermMetalBufferPoolContext()
            let afterPurge = pool.requestBuffer(from: ctx)
            XCTAssertFalse(afterPurge === first)
            XCTAssertEqual(afterPurge.length, 64)
        }
    }

    func testTexturePageCollectionPruneToMaximumPagesKeepsMostRecentlyUsed() throws {
        let device = try makeDeviceOrSkip()
        let collection = iTermTexturePageCollection(device: device,
                                                    cellSize: vector_uint2(8, 16),
                                                    pageCapacity: 1,
                                                    maximumNumberOfPages: 8)
        let context = iTermMetalBufferPoolContext()
        let bitmap = makeBitmap()

        let keys = (1...5).map { makeGlyphKey(code: unichar(0x4E00 + $0)) }
        var pages: [iTermTexturePage] = []
        for (idx, key) in keys.enumerated() {
            let entries = collection.addEntries(forColumn: Int32(idx), glyphKey: key, context: context) { _, isEmoji in
                isEmoji.pointee = false
                return [NSNumber(value: 0): bitmap]
            }
            XCTAssertNotNil(entries)
            if let page = entries?.pointee.entries?.pointee.page.takeUnretainedValue() {
                page.recordUse()
                pages.append(page)
            }
        }
        XCTAssertEqual(collection.pageCount, 5)

        // Bump page 0 so it becomes the most recently used alongside page 4.
        pages[0].recordUse()

        collection.prune(toMaximumPages: 2)
        XCTAssertEqual(collection.pageCount, 2)

        XCTAssertNotNil(collection.findEntries(for: keys[0]))
        XCTAssertNil(collection.findEntries(for: keys[1]))
        XCTAssertNil(collection.findEntries(for: keys[2]))
        XCTAssertNil(collection.findEntries(for: keys[3]))
        XCTAssertNotNil(collection.findEntries(for: keys[4]))

        collection.prune(toMaximumPages: 0)
        XCTAssertEqual(collection.pageCount, 0)
        XCTAssertNil(collection.findEntries(for: keys[0]))
        XCTAssertNil(collection.findEntries(for: keys[4]))
    }
}
