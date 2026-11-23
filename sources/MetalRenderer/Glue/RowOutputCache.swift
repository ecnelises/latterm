//
//  RowOutputCache.swift
//  Latterm
//

import Foundation

/// Byte-exact wrapper around the hole-free `iTermRowCacheKey` POD struct.
private struct RowCacheKeyBytes: Hashable {
    let value: iTermRowCacheKey

    static func == (lhs: Self, rhs: Self) -> Bool {
        withUnsafeBytes(of: lhs.value) { left in
            withUnsafeBytes(of: rhs.value) { right in
                left.elementsEqual(right)
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        withUnsafeBytes(of: value) { hasher.combine(bytes: $0) }
    }
}

@objc(iTermRowOutputCache)
final class iTermRowOutputCache: NSObject {
    private struct Node {
        var key: RowCacheKeyBytes
        var glyphKeys: Data
        var attributes: Data
        var background: Data
        var glyphKeyCount: UInt
        var rleCount: Int32
        var drawableGlyphs: Int32
        var hasUnderlineOrStrikethrough: Bool
        var prev: Int = -1
        var next: Int = -1
    }

    private let capacity: Int
    private var nodes: [Node] = []
    private var freeSlots: [Int] = []
    private var map: [RowCacheKeyBytes: Int] = [:]
    private var head: Int = -1
    private var tail: Int = -1

    @objc(initWithCapacity:)
    init(capacity maxEntries: UInt) {
        let cap = max(1, Int(maxEntries))
        self.capacity = cap
        nodes.reserveCapacity(cap)
        map.reserveCapacity(cap)
        super.init()
    }

    @available(*, unavailable)
    override init() {
        it_fatalError("Use init(capacity:)")
    }

    @objc var count: UInt {
        UInt(map.count)
    }

    @objc(lookup:glyphKeys:attributes:background:glyphKeyCount:rleCount:drawableGlyphs:hasUnderlineOrStrikethrough:)
    func lookup(_ key: UnsafePointer<iTermRowCacheKey>,
                glyphKeys: iTermGlyphKeyData,
                attributes: UnsafeMutableRawPointer,
                background: UnsafeMutableRawPointer,
                glyphKeyCount: UnsafeMutablePointer<UInt>,
                rleCount: UnsafeMutablePointer<Int32>,
                drawableGlyphs: UnsafeMutablePointer<Int32>,
                hasUnderlineOrStrikethrough: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let wrappedKey = RowCacheKeyBytes(value: key.pointee)
        guard let slot = map[wrappedKey] else {
            return false
        }
        moveToFront(slot)

        let entry = nodes[slot]
        if glyphKeys.count < entry.glyphKeyCount {
            glyphKeys.count = entry.glyphKeyCount
        }
        if !entry.glyphKeys.isEmpty {
            entry.glyphKeys.copyBytes(
                to: glyphKeys.mutableBytes.assumingMemoryBound(to: UInt8.self),
                count: entry.glyphKeys.count
            )
        }
        if !entry.attributes.isEmpty {
            entry.attributes.copyBytes(
                to: attributes.assumingMemoryBound(to: UInt8.self),
                count: entry.attributes.count
            )
        }
        if !entry.background.isEmpty {
            entry.background.copyBytes(
                to: background.assumingMemoryBound(to: UInt8.self),
                count: entry.background.count
            )
        }
        glyphKeyCount.pointee = entry.glyphKeyCount
        rleCount.pointee = entry.rleCount
        drawableGlyphs.pointee = entry.drawableGlyphs
        hasUnderlineOrStrikethrough.pointee = ObjCBool(entry.hasUnderlineOrStrikethrough)
        return true
    }

    @objc(store:glyphKeys:glyphKeysLength:attributes:attributesLength:background:backgroundLength:glyphKeyCount:rleCount:drawableGlyphs:hasUnderlineOrStrikethrough:)
    func store(_ key: UnsafePointer<iTermRowCacheKey>,
               glyphKeys: UnsafeRawPointer,
               glyphKeysLength: Int,
               attributes: UnsafeRawPointer,
               attributesLength: Int,
               background: UnsafeRawPointer,
               backgroundLength: Int,
               glyphKeyCount: UInt,
               rleCount: Int32,
               drawableGlyphs: Int32,
               hasUnderlineOrStrikethrough: Bool) {
        let wrappedKey = RowCacheKeyBytes(value: key.pointee)
        let newNode = Node(
            key: wrappedKey,
            glyphKeys: Data(bytes: glyphKeys, count: glyphKeysLength),
            attributes: Data(bytes: attributes, count: attributesLength),
            background: Data(bytes: background, count: backgroundLength),
            glyphKeyCount: glyphKeyCount,
            rleCount: rleCount,
            drawableGlyphs: drawableGlyphs,
            hasUnderlineOrStrikethrough: hasUnderlineOrStrikethrough
        )

        if let existingSlot = map[wrappedKey] {
            unlink(existingSlot)
            nodes[existingSlot] = newNode
            insertAtFront(existingSlot)
            return
        }

        while map.count >= capacity, tail != -1 {
            let victim = tail
            let victimKey = nodes[victim].key
            unlink(victim)
            map.removeValue(forKey: victimKey)
            freeSlots.append(victim)
        }

        let slot: Int
        if let reused = freeSlots.popLast() {
            nodes[reused] = newNode
            slot = reused
        } else {
            slot = nodes.count
            nodes.append(newNode)
        }
        map[wrappedKey] = slot
        insertAtFront(slot)
    }

    @objc func removeAllObjects() {
        nodes.removeAll(keepingCapacity: true)
        freeSlots.removeAll(keepingCapacity: true)
        map.removeAll(keepingCapacity: true)
        head = -1
        tail = -1
    }

    private func unlink(_ slot: Int) {
        let p = nodes[slot].prev
        let n = nodes[slot].next
        if p != -1 {
            nodes[p].next = n
        } else {
            head = n
        }
        if n != -1 {
            nodes[n].prev = p
        } else {
            tail = p
        }
        nodes[slot].prev = -1
        nodes[slot].next = -1
    }

    private func insertAtFront(_ slot: Int) {
        nodes[slot].prev = -1
        nodes[slot].next = head
        if head != -1 {
            nodes[head].prev = slot
        } else {
            tail = slot
        }
        head = slot
    }

    private func moveToFront(_ slot: Int) {
        if slot == head {
            return
        }
        unlink(slot)
        insertAtFront(slot)
    }
}
