//
//  MutableOrderedSetTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class MutableOrderedSetTests: XCTestCase {
    private func makeSet() -> iTermMutableOrderedSet<NSNumber> {
        return iTermMutableOrderedSet { lhs, rhs in
            lhs.compare(rhs)
        }
    }

    func testRandomizedInsertsDeletesAndBinarySearchingAgainstReferenceArray() {
        let set = makeSet()
        var reference: [Int] = []
        var state: UInt64 = 0x5DEECE66D

        func nextRandom() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % 900)
        }

        // Sequential ascending and descending stress across multiple B-Tree splits.
        for i in stride(from: 400, to: 800, by: 2) {
            let inserted = set.insert(NSNumber(value: i))
            XCTAssertTrue(inserted)
            reference.append(i)
        }
        reference.sort()

        for i in stride(from: 799, through: 0, by: -3) {
            let num = NSNumber(value: i)
            let expectedInsert = !reference.contains(i)
            XCTAssertEqual(set.insert(num), expectedInsert)
            if expectedInsert {
                reference.append(i)
                reference.sort()
            }
        }

        // Pseudo-random mix of insertions (including duplicates) and indexed deletions.
        for _ in 0..<2500 {
            let value = nextRandom()
            let num = NSNumber(value: value)
            let expectedInsert = !reference.contains(value)
            XCTAssertEqual(set.insert(num), expectedInsert)
            if expectedInsert {
                reference.append(value)
                reference.sort()
            }
            XCTAssertEqual(Int(set.count), reference.count)
            XCTAssertTrue(set.contains(num))

            if reference.count > 40 && (value % 5 == 0) {
                let deleteCount = min(4, reference.count - 10)
                let start = value % (reference.count - deleteCount)
                let range = NSRange(location: start, length: deleteCount)
                set.removeObjects(in: range)
                reference.removeSubrange(start..<(start + deleteCount))
            }
        }

        XCTAssertEqual(set.array.map(\.intValue), reference)
        for (idx, expected) in reference.enumerated() {
            XCTAssertEqual(set[idx].intValue, expected)
        }

        // Verify binary searching (firstEqual / lastEqual / insertionIndex).
        let fullRange = NSRange(location: 0, length: reference.count)
        for probe in [-10, 0, reference[reference.count / 2], 450, 9999] {
            let num = NSNumber(value: probe)
            let expectedIndex = UInt(reference.firstIndex(of: probe) ?? NSNotFound)
            XCTAssertEqual(
                set.index(of: num, inSortedRange: fullRange, options: .firstEqual),
                expectedIndex
            )
            let insertionIndex = set.index(of: num, inSortedRange: fullRange, options: [.insertionIndex, .firstEqual])
            let expectedInsertion = UInt(reference.firstIndex(where: { $0 >= probe }) ?? reference.count)
            XCTAssertEqual(insertionIndex, expectedInsertion)
        }

        // Verify block enumeration and indexed removal.
        var enumerated: [Int] = []
        set.enumerateObjects { obj, _, _ in
            enumerated.append(obj.intValue)
        }
        XCTAssertEqual(enumerated, reference)

        if reference.count > 10 {
            let indexes = IndexSet([0, 3, reference.count / 2, reference.count - 1])
            set.removeObjects(at: indexes)
            for idx in indexes.reversed() {
                reference.remove(at: idx)
            }
            XCTAssertEqual(set.array.map(\.intValue), reference)
        }

        // Drain to empty via head deletions (heavy borrow/merge stress).
        while !reference.isEmpty {
            let batch = min(7, reference.count)
            set.removeObjects(in: NSRange(location: 0, length: batch))
            reference.removeFirst(batch)
            XCTAssertEqual(Int(set.count), reference.count)
        }
        XCTAssertEqual(set.array.count, 0)
        XCTAssertNil(set.firstObject)
        XCTAssertNil(set.lastObject)
    }
}
