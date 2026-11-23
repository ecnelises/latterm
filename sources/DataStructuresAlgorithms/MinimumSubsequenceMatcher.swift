//  MinimumSubsequenceMatcher.swift
//  Latterm

import Foundation

@objc(iTermMinimumSubsequenceMatcher)
final class MinimumSubsequenceMatcher: NSObject {
    @objc let query: String
    private let units: [UInt16]

    @objc(initWithQuery:)
    init(query: String) {
        self.query = query
        units = Array((query as NSString).lowercased.utf16)
    }

    // Open Quickly passes normalized text and uses the returned UTF-16 offsets
    // to highlight the match in an attributed string.
    @objc(indexSetForDocument:)
    func indexSet(for document: String) -> IndexSet? {
        guard let first = units.first else { return nil }
        var postings = Dictionary(uniqueKeysWithValues: Set(units).map { ($0, [Int]()) })
        for (offset, unit) in document.utf16.enumerated() {
            postings[unit]?.append(offset)
        }

        var cursors = Array(repeating: 0, count: units.count)
        var offsets = Array(repeating: 0, count: units.count)
        var best: IndexSet?
        var bestSpan = Int.max
        for start in postings[first] ?? [] {
            offsets[0] = start
            for i in units.indices.dropFirst() {
                guard let candidates = postings[units[i]] else { return best }
                while cursors[i] < candidates.count && candidates[cursors[i]] <= offsets[i - 1] {
                    cursors[i] += 1
                }
                guard cursors[i] < candidates.count else { return best }
                offsets[i] = candidates[cursors[i]]
            }
            let span = offsets[units.count - 1] - start
            if span < bestSpan {
                best = IndexSet(offsets)
                bestSpan = span
                if span == units.count - 1 { break }
            }
        }
        return best
    }
}
