//
//  CumulativeSumCache.swift
//  Latterm
//

import Foundation

@objc(iTermCumulativeSumCache)
final class CumulativeSumCache: NSObject, NSCopying {
    private struct Bucket {
        var value: Int
        var sum: Int
    }

    // Dropping old scrollback advances the head. Compact only after at least
    // half the storage has been consumed, so front removal is amortized O(1).
    private var buckets: [Bucket] = []
    private var head = 0
    @objc var offset: Int = 0
    @objc var count: Int { buckets.count - head }

    @objc var sumOfAllValues: Int {
        sumOfValues(in: NSRange(location: 0, length: count))
    }

    @objc func dump() {
        DLog(description)
    }

    override var description: String {
        var out = ""
        for index in 0..<count {
            out += "_sums[\(index)] = \(sum(at: index) + offset)\n"
        }
        for index in 0..<count {
            out += "_values[\(index)] = \(value(at: index))\n"
        }
        return out
    }

    @objc(sumOfValuesInRange:)
    func sumOfValues(in range: NSRange) -> Int {
        it_assert(range.location < Int.max, "Invalid range location")
        guard range.length > 0 else {
            return 0
        }
        let lowIndex = max(0, range.location)
        let highIndex = max(0, range.location + range.length) - 1
        if highIndex < lowIndex {
            return 0
        }
        it_assert(highIndex < count,
                  "Range out of bounds")
        return sum(at: highIndex) - sum(at: lowIndex) + value(at: lowIndex)
    }

    @objc(appendValue:)
    func appendValue(_ value: Int) {
        if count == 0 { offset = 0 }
        buckets.append(Bucket(value: value, sum: (buckets.last?.sum ?? 0) + value))
    }

    /// Returns first index `i` where `sums[i] >= target`, or `count` if none.
    private func lowerBound(for target: Int) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if sum(at: mid) < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    @objc(indexContainingValue:roundUp:)
    func index(containingValue value: Int, roundUp: UnsafeMutablePointer<ObjCBool>) -> Int {
        let adjusted = value - offset
        var idx = lowerBound(for: adjusted)
        if idx == count {
            return NSNotFound
        }
        let isLastValueOfBucket = (sum(at: idx) == adjusted)
        if roundUp.pointee.boolValue && isLastValueOfBucket {
            idx += 1
            if idx == count {
                return NSNotFound
            }
        }
        roundUp.pointee = ObjCBool(isLastValueOfBucket)
        return idx
    }

    @objc(verboseIndexContainingValue:)
    func verboseIndex(containingValue value: Int) -> Int {
        let adjusted = value - offset
        var idx = lowerBound(for: adjusted)
        if idx == count {
            return NSNotFound
        }
        if sum(at: idx) == adjusted {
            idx += 1
            if idx == count {
                return NSNotFound
            }
        }
        return idx
    }

    @objc func removeFirstValue() {
        offset -= buckets[head].value
        head += 1
        if head >= count {
            buckets.removeFirst(head)
            head = 0
        }
        if count == 0 { offset = 0 }
    }

    @objc func removeLastValue() {
        buckets.removeLast()
        if count == 0 {
            buckets.removeAll()
            head = 0
            offset = 0
        }
    }

    @objc(setLastValue:)
    func setLastValue(_ value: Int) {
        it_assert(count >= 2, "setLastValue requires at least two buckets")
        let last = buckets.count - 1
        buckets[last] = Bucket(value: value, sum: buckets[last - 1].sum + value)
    }

    @objc(setFirstValue:)
    func setFirstValue(_ value: Int) {
        let cachedNumLines = buckets[head].value
        let delta = value - cachedNumLines
        if count > 1 {
            it_assert(delta <= 0, "First bucket cannot grow when multiple buckets exist")
        }
        offset += delta
        buckets[head].value = value
    }

    func copy(with zone: NSZone? = nil) -> Any {
        let copy = CumulativeSumCache()
        copy.buckets = buckets
        copy.head = head
        copy.offset = offset
        return copy
    }

    @objc(valueAtIndex:)
    func value(at index: Int) -> Int {
        buckets[head + index].value
    }

    @objc(sumAtIndex:)
    func sum(at index: Int) -> Int {
        buckets[head + index].sum
    }
}
