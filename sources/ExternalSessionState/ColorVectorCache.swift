//
//  ColorVectorCache.swift
//  Latterm
//

import AppKit
import simd

@objc(iTermColorVectorCache)
final class ColorVectorCache: NSObject {
    private struct CacheSlot {
        weak var colorSpace: NSColorSpace?
        var entries: [iTermColorMapKey: SIMD4<Float>] = [:]
    }

    private var slot0 = CacheSlot()
    private var slot1 = CacheSlot()

    @objc(vectorForColor:colorSpace:)
    func vector(for color: NSColor, colorSpace: NSColorSpace) -> vector_float4 {
        guard let converted = color.usingColorSpace(colorSpace) else { return .zero }
        return SIMD4<Float>(
            Float(converted.redComponent),
            Float(converted.greenComponent),
            Float(converted.blueComponent),
            Float(converted.alphaComponent)
        )
    }

    @objc(storeVector:forKey:colorSpace:)
    func storeVector(_ vector: vector_float4,
                     forKey key: iTermColorMapKey,
                     colorSpace: NSColorSpace) {
        if slot0.colorSpace === colorSpace {
            slot0.entries[key] = vector
        } else if slot1.colorSpace === colorSpace {
            slot1.entries[key] = vector
        } else {
            evict(for: colorSpace)
            slot0.entries[key] = vector
        }
    }

    @objc(getVector:forKey:colorSpace:)
    func getVector(_ outVector: UnsafeMutablePointer<vector_float4>,
                   forKey key: iTermColorMapKey,
                   colorSpace: NSColorSpace) -> Bool {
        if slot0.colorSpace === colorSpace {
            guard let cached = slot0.entries[key] else {
                return false
            }
            outVector.pointee = cached
            return true
        }
        if slot1.colorSpace === colorSpace {
            let cached = slot1.entries[key]
            swap(&slot0, &slot1)
            if let cached {
                outVector.pointee = cached
                return true
            }
            return false
        }
        evict(for: colorSpace)
        return false
    }

    @objc func clear() {
        slot0 = CacheSlot()
        slot1 = CacheSlot()
    }

    @objc(clearKey:)
    func clearKey(_ key: iTermColorMapKey) {
        slot0.entries.removeValue(forKey: key)
        slot1.entries.removeValue(forKey: key)
    }

    private func evict(for newColorSpace: NSColorSpace) {
        DLog("Color space cache eviction for \(newColorSpace)")
        slot1 = slot0
        slot0 = CacheSlot(colorSpace: newColorSpace, entries: [:])
    }
}
