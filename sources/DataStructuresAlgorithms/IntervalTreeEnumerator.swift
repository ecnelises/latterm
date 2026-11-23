import Foundation

@objc enum IntervalTreeOrder: Int {
    case forwardLocation, reverseLocation, forwardLimit, reverseLimit
}

/// Enumerates one group of objects sharing a location or limit at a time.
/// Query the live tree between groups so callers can remove a group as they visit it.
@objc final class IntervalTreeEnumerator: NSEnumerator {
    private enum Cursor {
        case first
        case past(Int64)
        case finished
    }

    private let tree: IntervalTree
    private let order: IntervalTreeOrder
    private var cursor: Cursor

    @objc(initWithTree:order:start:)
    init(tree: IntervalTree, order: IntervalTreeOrder, start: NSNumber?) {
        self.tree = tree
        self.order = order
        if let start {
            let value = start.int64Value
            switch order {
            case .forwardLocation:
                // The location APIs include their starting position.
                cursor = value <= 0 ? .first : .past(value - 1)
            case .reverseLocation:
                cursor = value == .max ? .first : .past(value + 1)
            case .forwardLimit, .reverseLimit:
                cursor = .past(value)
            }
        } else {
            cursor = .first
        }
    }

    override func nextObject() -> Any? {
        let batch: [IntervalTreeImmutableObject]?
        switch (order, cursor) {
        case (_, .finished): return nil
        case (.forwardLocation, .first): batch = tree.objectsWithSmallestLocation()
        case (.reverseLocation, .first): batch = tree.objectsWithLargestLocation()
        case (.forwardLimit, .first): batch = tree.objectsWithSmallestLimit()
        case (.reverseLimit, .first): batch = tree.objectsWithLargestLimit()
        case let (.forwardLocation, .past(value)): batch = tree.objectsWithSmallestLocation(after: value)
        case let (.reverseLocation, .past(value)): batch = tree.objectsWithLargestLocation(before: value)
        case let (.forwardLimit, .past(value)): batch = tree.objectsWithSmallestLimit(after: value)
        case let (.reverseLimit, .past(value)): batch = tree.objectsWithLargestLimit(before: value)
        }
        guard let batch, let interval = batch.first?.entry?.interval else {
            cursor = .finished
            return nil
        }
        switch order {
        case .forwardLocation, .reverseLocation: cursor = .past(interval.location)
        case .forwardLimit, .reverseLimit: cursor = .past(interval.limit)
        }
        return batch
    }
}

/// The read-only screen adapter hands out the immutable peer of each object.
/// Using nextObject for every consumption mode also covers Objective-C fast enumeration.
@objc final class IntervalTreeSanitizingEnumerator: NSEnumerator {
    private let source: NSEnumerator?

    @objc(initWithSource:) init(source: NSEnumerator?) {
        self.source = source
    }

    override func nextObject() -> Any? {
        guard let batch = source?.nextObject() as? [IntervalTreeImmutableObject] else { return nil }
        return batch.map { $0.doppelganger() }
    }
}

extension IntervalTree {
    /// Includes empty marks at the end boundary, as used when clearing a screen range.
    @objc(objectsContainedInInterval:)
    func objectsContained(in interval: Interval) -> [IntervalTreeObject] {
        var result: [IntervalTreeObject] = []
        let batches = forwardLocationEnumerator(at: max(0, interval.location))
        for case let batch as [IntervalTreeObject] in batches {
            guard let first = batch.first?.entry?.interval else { continue }
            if first.location > interval.limit { break }
            guard first.location >= interval.location else { continue }
            result.append(contentsOf: batch.filter { object in
                guard let mark = object.entry?.interval else { return false }
                return mark.limit <= interval.limit
            })
        }
        return result
    }
}
