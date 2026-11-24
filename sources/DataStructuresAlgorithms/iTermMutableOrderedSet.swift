//
//  iTermMutableOrderedSet.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/27/24.
//

import Cocoa

private final class OrderStatisticBTree<Element: Comparable> {
    private static var minKeys: Int { 15 }
    private static var maxKeys: Int { 31 }

    private final class Node {
        var keys: [Element] = []
        var children: [Node] = []
        var subtreeCount: Int = 0

        var isLeaf: Bool { children.isEmpty }

        init(keys: [Element] = [], children: [Node] = []) {
            self.keys = keys
            self.children = children
            recomputeCount()
        }

        func recomputeCount() {
            var total = keys.count
            for child in children {
                total += child.subtreeCount
            }
            subtreeCount = total
        }
    }

    private enum InsertResult {
        case alreadyPresent
        case inserted
        case split(median: Element, right: Node)
    }

    private var root = Node()

    var count: Int {
        root.subtreeCount
    }

    private func lowerBound(in keys: [Element], for target: Element) -> (index: Int, found: Bool) {
        var low = 0
        var high = keys.count
        while low < high {
            let mid = low + (high - low) / 2
            if keys[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low < keys.count && keys[low] == target {
            return (low, true)
        }
        return (low, false)
    }

    func contains(_ element: Element) -> Bool {
        var node = root
        while true {
            let (idx, found) = lowerBound(in: node.keys, for: element)
            if found {
                return true
            }
            if node.isLeaf {
                return false
            }
            node = node.children[idx]
        }
    }

    @discardableResult
    func insert(_ element: Element) -> Bool {
        switch insert(into: root, element: element) {
        case .alreadyPresent:
            return false
        case .inserted:
            return true
        case .split(let median, let right):
            root = Node(keys: [median], children: [root, right])
            return true
        }
    }

    private func insert(into node: Node, element: Element) -> InsertResult {
        let (idx, found) = lowerBound(in: node.keys, for: element)
        if found {
            return .alreadyPresent
        }

        if node.isLeaf {
            node.keys.insert(element, at: idx)
            node.subtreeCount += 1
        } else {
            switch insert(into: node.children[idx], element: element) {
            case .alreadyPresent:
                return .alreadyPresent
            case .inserted:
                node.subtreeCount += 1
            case .split(let median, let right):
                node.keys.insert(median, at: idx)
                node.children.insert(right, at: idx + 1)
                node.subtreeCount += 1
            }
        }

        if node.keys.count > Self.maxKeys {
            let mid = node.keys.count / 2
            let median = node.keys[mid]
            let rightKeys = Array(node.keys[(mid + 1)...])
            let rightChildren: [Node]
            if node.isLeaf {
                rightChildren = []
            } else {
                rightChildren = Array(node.children[(mid + 1)...])
                node.children.removeSubrange((mid + 1)...)
            }
            node.keys.removeSubrange(mid...)
            node.recomputeCount()
            let right = Node(keys: rightKeys, children: rightChildren)
            return .split(median: median, right: right)
        }

        return .inserted
    }

    func element(at index: Int) -> Element {
        it_assert(index >= 0 && index < count, "Index \(index) out of bounds \(count)")
        var remaining = index
        var node = root
        while !node.isLeaf {
            var descended = false
            for i in 0..<node.keys.count {
                let leftCount = node.children[i].subtreeCount
                if remaining < leftCount {
                    node = node.children[i]
                    descended = true
                    break
                }
                if remaining == leftCount {
                    return node.keys[i]
                }
                remaining -= (leftCount + 1)
            }
            if !descended {
                node = node.children[node.keys.count]
            }
        }
        return node.keys[remaining]
    }

    @discardableResult
    func remove(at index: Int) -> Element {
        it_assert(index >= 0 && index < count, "Index \(index) out of bounds \(count)")
        let removed = remove(in: root, at: index)
        if !root.isLeaf && root.keys.isEmpty {
            root = root.children[0]
        }
        return removed
    }

    private func mergeChildren(of parent: Node, leftIndex i: Int) {
        let left = parent.children[i]
        let right = parent.children[i + 1]
        let separator = parent.keys.remove(at: i)
        parent.children.remove(at: i + 1)
        left.keys.append(separator)
        left.keys.append(contentsOf: right.keys)
        if !right.children.isEmpty {
            left.children.append(contentsOf: right.children)
        }
        left.recomputeCount()
    }

    private func remove(in node: Node, at index: Int) -> Element {
        if node.isLeaf {
            let removed = node.keys.remove(at: index)
            node.subtreeCount -= 1
            return removed
        }

        var remaining = index
        for i in 0..<node.keys.count {
            let leftCount = node.children[i].subtreeCount
            if remaining < leftCount {
                return removeFromChild(of: node, childIndex: i, targetIndex: remaining)
            }
            if remaining == leftCount {
                return removeInternalKey(of: node, at: i)
            }
            remaining -= (leftCount + 1)
        }
        return removeFromChild(of: node, childIndex: node.keys.count, targetIndex: remaining)
    }

    private func removeInternalKey(of node: Node, at i: Int) -> Element {
        let removed = node.keys[i]
        let leftChild = node.children[i]
        let rightChild = node.children[i + 1]

        if leftChild.keys.count > Self.minKeys {
            node.keys[i] = remove(in: leftChild, at: leftChild.subtreeCount - 1)
            node.subtreeCount -= 1
            return removed
        }
        if rightChild.keys.count > Self.minKeys {
            node.keys[i] = remove(in: rightChild, at: 0)
            node.subtreeCount -= 1
            return removed
        }

        let mergedKeyIndex = leftChild.subtreeCount
        mergeChildren(of: node, leftIndex: i)
        let mergedRemoved = remove(in: leftChild, at: mergedKeyIndex)
        node.subtreeCount -= 1
        return mergedRemoved
    }

    private func removeFromChild(of node: Node, childIndex: Int, targetIndex: Int) -> Element {
        var idx = childIndex
        var target = targetIndex

        if node.children[idx].keys.count == Self.minKeys {
            if idx > 0 && node.children[idx - 1].keys.count > Self.minKeys {
                let left = node.children[idx - 1]
                let child = node.children[idx]
                let separator = node.keys[idx - 1]
                node.keys[idx - 1] = left.keys.removeLast()
                child.keys.insert(separator, at: 0)
                if !left.isLeaf {
                    let moved = left.children.removeLast()
                    target += moved.subtreeCount + 1
                    child.children.insert(moved, at: 0)
                } else {
                    target += 1
                }
                left.recomputeCount()
                child.recomputeCount()
            } else if idx + 1 < node.children.count && node.children[idx + 1].keys.count > Self.minKeys {
                let right = node.children[idx + 1]
                let child = node.children[idx]
                let separator = node.keys[idx]
                node.keys[idx] = right.keys.removeFirst()
                child.keys.append(separator)
                if !right.isLeaf {
                    child.children.append(right.children.removeFirst())
                }
                right.recomputeCount()
                child.recomputeCount()
            } else if idx > 0 {
                let leftCountBefore = node.children[idx - 1].subtreeCount
                mergeChildren(of: node, leftIndex: idx - 1)
                idx -= 1
                target += leftCountBefore + 1
            } else {
                mergeChildren(of: node, leftIndex: idx)
            }
        }

        let removed = remove(in: node.children[idx], at: target)
        node.subtreeCount -= 1
        return removed
    }

    func toArray() -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        func appendInOrder(_ node: Node) {
            if node.isLeaf {
                result.append(contentsOf: node.keys)
                return
            }
            for i in 0..<node.keys.count {
                appendInOrder(node.children[i])
                result.append(node.keys[i])
            }
            appendInOrder(node.children[node.keys.count])
        }
        appendInOrder(root)
        return result
    }
}

// The purpose of these classes is to expose SortedSet behavior to Objective-C.
// I wish generics worked better with ObjC interop!
@objc
class iTermMutableOrderedSetImpl: NSObject {
    private struct Element: Comparable {
        var object: NSObject
        var compare: (NSObject, NSObject) -> ComparisonResult

        static func < (lhs: iTermMutableOrderedSetImpl.Element,
                       rhs: iTermMutableOrderedSetImpl.Element) -> Bool {
            return lhs.compare(lhs.object, rhs.object) == .orderedAscending
        }
        static func == (lhs: iTermMutableOrderedSetImpl.Element, rhs: iTermMutableOrderedSetImpl.Element) -> Bool {
            return lhs.compare(lhs.object, rhs.object) == .orderedSame
        }
    }
    private let sortedSet = OrderStatisticBTree<Element>()
    @objc private(set) var compare: (NSObject, NSObject) -> ComparisonResult

    @objc(initWithComparator:)
    public init(compare: @escaping (NSObject, NSObject) -> ComparisonResult) {
        self.compare = compare
    }

    @objc public var count: Int {
        sortedSet.count
    }

    @objc(removeObjectAtIndex:)
    public func remove(at index: Int) {
        sortedSet.remove(at: index)
    }

    @objc(containsObject:) public func contains(object: NSObject) -> Bool {
        return sortedSet.contains(Element(object: object, compare: compare))
    }

    // Returns true if it was added, false if it was already there.
    @discardableResult
    @objc(insertObject:) public func insert(object: NSObject) -> Bool {
        return sortedSet.insert(Element(object: object, compare: compare))
    }

    @objc subscript(_ i: Int) -> NSObject {
        return sortedSet.element(at: i).object
    }

    @objc var array: [NSObject] {
        return sortedSet.toArray().map { $0.object }
    }
}

@objc
extension iTermMutableOrderedSetImpl: NSFastEnumeration {
    func countByEnumerating(
        with state: UnsafeMutablePointer<NSFastEnumerationState>,
        objects buffer: AutoreleasingUnsafeMutablePointer<AnyObject?>,
        count len: Int) -> Int {
            withUnsafeMutablePointer(to: &state.pointee.extra.0) { ptr in
                state.pointee.mutationsPtr = ptr
            }
            state.pointee.itemsPtr = buffer
            if state.pointee.state < sortedSet.count && len > 0 {
                let i = state.pointee.state
                buffer.pointee = sortedSet.element(at: Int(i)).object
                state.pointee.state += 1
                return 1
            }
            return 0
        }
}
