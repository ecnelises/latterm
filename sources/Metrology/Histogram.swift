//
//  Histogram.swift
//  Latterm
//

import Darwin
import Foundation

@objc(iTermHistogram)
final class iTermHistogram: NSObject {
    private static let barWidth = 20
    private static let sparkCharacters = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    private struct Sampler {
        var values: [Double]
        let capacity: Int
        var weight: Int64

        init(capacity: Int) {
            self.capacity = Swift.max(0, capacity)
            self.values = []
            self.values.reserveCapacity(Swift.max(0, capacity))
            self.weight = 0
        }

        init(dictionary: [AnyHashable: Any]?) {
            let cap = (dictionary?["capacity"] as? NSNumber)?.intValue ?? 100
            let w = (dictionary?["weight"] as? NSNumber)?.int64Value ?? 0
            let rawValues = (dictionary?["values"] as? [NSNumber])?.map { $0.doubleValue } ?? []
            self.capacity = Swift.max(0, cap)
            self.values = rawValues
            self.weight = w
            it_assert(values.count <= capacity && weight >= Int64(values.count),
                      "Invalid histogram sampler dictionary")
        }

        var dictionaryValue: [String: Any] {
            [
                "capacity": capacity,
                "weight": weight,
                "values": values
            ]
        }

        mutating func add(_ value: Double) {
            guard capacity > 0 else {
                weight += 1
                return
            }
            if values.count < capacity {
                values.append(value)
            } else {
                let r = Self.randomBelow(weight + 1)
                if r < Int64(capacity) {
                    values[Int(r)] = value
                }
            }
            weight += 1
        }

        mutating func concatenate(_ other: Sampler) {
            it_assert(values.count + other.values.count <= capacity,
                      "Concatenated sampler exceeds capacity")
            weight += other.weight
            values.append(contentsOf: other.values)
        }

        mutating func merge(from other: Sampler) {
            guard other.weight > 0 else {
                return
            }
            it_assert(other.capacity == capacity, "Mismatched histogram reservoir capacities")
            if weight == 0 {
                values = other.values
                weight = other.weight
                return
            }
            it_assert(!values.isEmpty && values.count <= capacity && !other.values.isEmpty,
                      "Invalid sampler state before merge")

            var thisValues = values
            var otherValues = other.values
            thisValues.shuffle()
            otherValues.shuffle()

            let nm = Double(Swift.min(capacity, thisValues.count + otherValues.count))
            let w1 = Double(weight)
            let w2 = Double(other.weight)
            let s1 = Double(thisValues.count)
            let s2 = Double(otherValues.count)
            let p1 = nm / ((w1 + w2) * (s1 / w1))
            let p2 = nm / ((w1 + w2) * (s2 / w2))
            let n1 = Int(Swift.min(Swift.max(floor(s1 * p1), 0.0), Swift.min(s1, nm)))
            let n2 = Int(Swift.min(Swift.max(floor(s2 * p2), 0.0), Swift.min(s2, nm - Double(n1))))

            var merged: [Double] = []
            merged.reserveCapacity(n1 + n2)
            merged.append(contentsOf: thisValues.prefix(n1))
            merged.append(contentsOf: otherValues.prefix(n2))
            if merged.isEmpty, let fallback = thisValues.first ?? otherValues.first {
                merged.append(fallback)
            }
            values = merged
            weight += other.weight
        }

        func value(forPercentile p: Double) -> Double {
            guard !values.isEmpty else {
                return .nan
            }
            it_assert(p >= 0 && p <= 1, "Percentile out of range")
            let sorted = values.sorted()
            let rawIndex = Int(floor(Double(sorted.count) * p))
            let safeIndex = Swift.min(Swift.max(0, rawIndex), sorted.count - 1)
            return sorted[safeIndex]
        }

        func histogramBuckets() -> [Int] {
            guard !values.isEmpty else {
                return []
            }
            let n = Double(values.count)
            let iqr = value(forPercentile: 0.75) - value(forPercentile: 0.25)
            var binWidth = 2.0 * iqr / pow(n, 1.0 / 3.0)
            if binWidth <= 0 {
                return [values.count]
            }
            let minimum = value(forPercentile: 0)
            let maximum = value(forPercentile: 1)
            let range = maximum - minimum
            let maxBins = 15.0
            if range / binWidth > maxBins {
                binWidth = range / maxBins
            }
            if binWidth <= 0 {
                return [values.count]
            }
            var result: [Int] = []
            for v in values {
                let bucket = Swift.max(0, Int((v - minimum) / binWidth))
                if result.count <= bucket {
                    result.append(contentsOf: repeatElement(0, count: bucket + 1 - result.count))
                }
                result[bucket] += 1
            }
            return result
        }

        func discreteHistogramBuckets() -> (minValue: Int32, buckets: [Int]) {
            guard let first = values.first else {
                return (0, [])
            }
            var minVal = Int(floor(first))
            var maxVal = minVal
            for v in values {
                let iv = Int(floor(v))
                minVal = Swift.min(minVal, iv)
                maxVal = Swift.max(maxVal, iv)
            }
            var buckets = [Int](repeating: 0, count: maxVal - minVal + 1)
            for v in values {
                buckets[Int(floor(v)) - minVal] += 1
            }
            return (Int32(clamping: minVal), buckets)
        }

        private static func randomBelow(_ n: Int64) -> Int64 {
            if n <= Int64(UInt32.max) {
                return Int64(arc4random_uniform(UInt32(n)))
            }
            var r: UInt64 = 0
            arc4random_buf(&r, MemoryLayout<UInt64>.size)
            return Int64(r % UInt64(n))
        }
    }

    private var sampler: Sampler
    private var _reservoirSize: Int32

    @objc private(set) var count: Int64 = 0
    @objc private(set) var sum: Double = 0
    @objc private(set) var min: Double = 0
    @objc private(set) var max: Double = 0
    @objc var discrete: Bool = false

    @objc var reservoirSize: Int32 {
        get { _reservoirSize }
        set {
            _reservoirSize = newValue
            clear()
        }
    }

    override init() {
        _reservoirSize = 100
        sampler = Sampler(capacity: 100)
        super.init()
    }

    @objc(initConcatenating:)
    init(concatenating histograms: [iTermHistogram]) {
        var totalCap = 0
        var maxVal: Double = 0
        var minVal: Double = .infinity
        var totalCount: Int64 = 0
        var totalSum: Double = 0
        for hist in histograms {
            totalCap += Int(hist.count)
            maxVal = Swift.max(maxVal, hist.max)
            minVal = Swift.min(minVal, hist.min)
            totalCount += hist.count
            totalSum += hist.sum
        }
        _reservoirSize = Int32(clamping: totalCap)
        var combined = Sampler(capacity: totalCap)
        for hist in histograms {
            combined.concatenate(hist.sampler)
        }
        sampler = combined
        count = totalCount
        sum = totalSum
        min = minVal
        max = maxVal
        super.init()
    }

    @objc(initWithDictionary:)
    init(dictionary: [AnyHashable: Any]) {
        let resSize = (dictionary["reservoirSize"] as? NSNumber)?.int32Value ?? 0
        let effectiveResSize = resSize != 0 ? resSize : 100
        _reservoirSize = effectiveResSize
        sampler = Sampler(dictionary: dictionary["sampler"] as? [AnyHashable: Any])
        sum = (dictionary["sum"] as? NSNumber)?.doubleValue ?? 0
        min = (dictionary["min"] as? NSNumber)?.doubleValue ?? 0
        max = (dictionary["max"] as? NSNumber)?.doubleValue ?? 0
        count = (dictionary["count"] as? NSNumber)?.int64Value ?? 0
        discrete = (dictionary["discrete"] as? NSNumber)?.boolValue ?? false
        super.init()
    }

    @objc func sanityCheck() {
        if sampler.weight > 0 {
            it_assert(count > 0, "Positive sampler weight with zero count")
        }
    }

    @objc func clone() -> Self {
        Self(dictionary: dictionaryValue)
    }

    @objc var dictionaryValue: [AnyHashable: Any] {
        [
            "reservoirSize": _reservoirSize,
            "sampler": sampler.dictionaryValue,
            "sum": sum,
            "min": min,
            "max": max,
            "count": count,
            "discrete": discrete
        ]
    }

    @objc func clear() {
        sum = 0
        min = 0
        max = 0
        count = 0
        sampler = Sampler(capacity: Int(_reservoirSize))
    }

    @objc(addValue:)
    func addValue(_ value: Double) {
        if count == 0 {
            min = value
            max = value
        } else {
            min = Swift.min(min, value)
            max = Swift.max(max, value)
        }
        sum += value
        count += 1
        sampler.add(value)
    }

    @objc(mergeFrom:)
    func merge(from other: iTermHistogram?) {
        guard let other else {
            return
        }
        if count == 0 && other.count > 0 {
            min = other.min
            max = other.max
        } else if other.count > 0 {
            min = Swift.min(min, other.min)
            max = Swift.max(max, other.max)
        }
        sum += other.sum
        count += other.count
        sampler.merge(from: other.sampler)
    }

    @objc var mean: Double {
        sum / Double(count)
    }

    @objc var stringForTabularDisplay: String {
        sparklines
    }

    private static func saneDouble(_ d: Double) -> Double {
        if d.isNaN || d.isInfinite {
            return -666
        }
        return Double(Int(d * 1000.0)) / 1000.0
    }

    @objc var stringValue: String {
        if discrete {
            return discreteStringValue
        }
        let buckets = sampler.histogramBuckets()
        guard !buckets.isEmpty, let largestCount = buckets.max(), largestCount > 0 else {
            return "No events"
        }
        let total = buckets.reduce(0, +)
        let minimum = sampler.value(forPercentile: 0)
        let range = sampler.value(forPercentile: 1) - minimum
        let binWidth = range / Double(buckets.count)

        var tailStart = buckets.count
        for i in stride(from: buckets.count - 1, through: 0, by: -1) {
            let percent = 100.0 * Double(buckets[i]) / Double(total)
            if percent > 3.0 {
                break
            }
            tailStart = i
        }
        let compressTail = tailStart < buckets.count - 1
        let normalEnd = compressTail ? tailStart : buckets.count

        var out = ""
        for i in 0..<normalEnd {
            out += formatBucket(
                count: buckets[i],
                largestCount: largestCount,
                total: total,
                lowerBound: minimum + Double(i) * binWidth,
                upperBound: minimum + Double(i + 1) * binWidth,
                binWidth: binWidth
            ) + "\n"
        }
        if compressTail {
            let tailCount = buckets[tailStart...].reduce(0, +)
            out += formatBucket(
                count: tailCount,
                largestCount: largestCount,
                total: total,
                lowerBound: minimum + Double(tailStart) * binWidth,
                upperBound: minimum + Double(buckets.count) * binWidth,
                binWidth: binWidth
            ) + "\n"
        }

        let meanVal = sum / Double(count)
        let p50 = Self.saneDouble(sampler.value(forPercentile: 0.5))
        let p95 = Self.saneDouble(sampler.value(forPercentile: 0.95))
        out += String(format: "Count=%lld Sum=%@ Mean=%0.3f p_50=%0.3f p_95=%0.3f",
                      count, NSNumber(value: sum), meanVal, p50, p95)
        return out
    }

    private var discreteStringValue: String {
        let (minValue, buckets) = sampler.discreteHistogramBuckets()
        guard !buckets.isEmpty, let largestCount = buckets.max(), largestCount > 0 else {
            return "No events"
        }
        let total = buckets.reduce(0, +)
        var out = ""
        for (i, bucketCount) in buckets.enumerated() {
            let stars = String(repeating: "*", count: bucketCount * Self.barWidth / largestCount)
            let percent = String(format: "%0.1f%%", 100.0 * Double(bucketCount) / Double(total))
            out += String(format: "%12d %8d (%6@) |%@\n",
                          Int(minValue) + i, bucketCount, percent as NSString, stars as NSString)
        }
        let meanVal = sum / Double(count)
        let p50 = Self.saneDouble(sampler.value(forPercentile: 0.5))
        let p95 = Self.saneDouble(sampler.value(forPercentile: 0.95))
        out += String(format: "Count=%lld Sum=%@ Mean=%0.3f p_50=%0.3f p_95=%0.3f",
                      count, NSNumber(value: sum), meanVal, p50, p95)
        return out
    }

    @objc var sparklines: String {
        guard count > 0 else {
            return "No data"
        }
        let graph = sparklineGraph(withPrecision: 4, multiplier: 1, units: "")
        return "\(NSNumber(value: min)) \(graph) \(NSNumber(value: max))  Count=\(count) Mean=\(NSNumber(value: sum / Double(count))) p50=\(NSNumber(value: sampler.value(forPercentile: 0.5))) p95=\(NSNumber(value: sampler.value(forPercentile: 0.95))) Sum=\(NSNumber(value: sum))"
    }

    @objc(percentile:)
    func percentile(_ p: Double) -> Double {
        sampler.value(forPercentile: p)
    }

    @objc(valueAtNTile:)
    func value(atNTile ntile: Double) -> Double {
        sampler.value(forPercentile: ntile)
    }

    @objc(sparklineGraphWithPrecision:multiplier:units:)
    func sparklineGraph(withPrecision precision: Int32,
                        multiplier: Double,
                        units: String) -> String {
        let buckets = sampler.histogramBuckets()
        guard !buckets.isEmpty else {
            return ""
        }
        let fmt = "%0.\(precision)f\(units)"
        let lower = String(format: fmt, multiplier * sampler.value(forPercentile: 0))
        let upper = String(format: fmt, multiplier * sampler.value(forPercentile: 1))
        return "\(lower) \(graphString()) \(upper)"
    }

    @objc func graphString() -> String {
        let buckets = sampler.histogramBuckets()
        guard !buckets.isEmpty, let largest = buckets.max(), largest > 0 else {
            return ""
        }
        var out = ""
        for count in buckets {
            out += spark(withHeight: Double(count) / Double(largest))
        }
        return out
    }

    @objc func bucketData() -> [[AnyHashable: Any]] {
        guard count > 0 else {
            return []
        }
        let buckets = sampler.histogramBuckets()
        guard !buckets.isEmpty else {
            return []
        }
        let minimum = sampler.value(forPercentile: 0)
        let range = sampler.value(forPercentile: 1) - minimum
        let binWidth = range / Double(buckets.count)
        return buckets.enumerated().map { idx, c in
            [
                "lowerBound": minimum + Double(idx) * binWidth,
                "upperBound": minimum + Double(idx + 1) * binWidth,
                "count": c
            ]
        }
    }

    private func formatBucket(count: Int,
                              largestCount: Int,
                              total: Int,
                              lowerBound: Double,
                              upperBound: Double,
                              binWidth: Double) -> String {
        let stars = String(repeating: "*", count: count * Self.barWidth / largestCount)
        let percent = String(format: "%0.1f%%", 100.0 * Double(count) / Double(total))
        let rawPrecision = (binWidth >= 1.0 || binWidth <= 0) ? 0 : Int(ceil(-log10(binWidth)))
        let precision = Swift.min(rawPrecision, 3)
        let format = "[%12.\(precision)f, %12.\(precision)f) %8d (%6@) |%@"
        return String(format: format, lowerBound, upperBound, count, percent as NSString, stars as NSString)
    }

    private func spark(withHeight fraction: Double) -> String {
        if fraction <= 0 {
            return " "
        }
        let clamped = Swift.min(1.0, fraction)
        let idx = Int((clamped * Double(Self.sparkCharacters.count - 1)).rounded())
        return Self.sparkCharacters[idx]
    }
}
