//
//  LineBufferSorting.swift
//  Latterm
//

import Foundation

@_cdecl("SortedPositionsFromResultRanges")
func SortedPositionsFromResultRanges(_ ranges: NSArray, _ includeEnds: ObjCBool) -> UnsafeMutablePointer<Int32>? {
    let count = ranges.count
    let withEnds = includeEnds.boolValue
    let resultCount = withEnds ? count * 2 : count
    let raw = iTermMalloc(MemoryLayout<Int32>.stride * max(resultCount, 1))
    let result = raw.assumingMemoryBound(to: Int32.self)
    guard resultCount > 0 else {
        return result
    }
    var offset = 0
    for element in ranges {
        let rr = element as! ResultRange
        let pos = rr.position
        result[offset] = pos
        offset += 1
        if withEnds {
            result[offset] = pos + rr.length - 1
            offset += 1
        }
    }
    var positions = UnsafeMutableBufferPointer(start: result, count: resultCount)
    positions.sort()
    return result
}

@objc(LineBufferSearchIntermediateMap)
final class LineBufferSearchIntermediateMap: NSObject {
    private var map: [Int32: VT100GridCoord]

    @objc(initWithCapacity:)
    init(capacity: Int32) {
        map = Dictionary(minimumCapacity: max(0, Int(capacity)))
        super.init()
    }

    @available(*, unavailable)
    override init() {
        it_fatalError("Use init(capacity:)")
    }

    @objc(addCoordinate:forPosition:)
    func addCoordinate(_ coord: VT100GridCoord, forPosition position: Int32) {
        map[position] = coord
    }

    @objc(enumerateCoordPairsForRanges:block:)
    func enumerateCoordPairs(forRanges ranges: [ResultRange],
                             block: (VT100GridCoord, VT100GridCoord) -> Void) {
        for rr in ranges {
            guard let start = map[rr.position],
                  let end = map[rr.position + rr.length - 1] else {
                continue
            }
            block(start, end)
        }
    }
}
