//
//  Data+BigEndian.swift
//  iTerm2
//
//  Big-endian fixed-width integer framing for length-prefixed wire formats.
//

import Foundation

extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendBigEndian(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    func readBigEndianUInt16(at index: Index) -> UInt16 {
        (UInt16(self[index]) << 8) | UInt16(self[index + 1])
    }

    func readBigEndianUInt32(at index: Index) -> UInt32 {
        var result: UInt32 = 0
        for offset in 0..<4 {
            result = (result << 8) | UInt32(self[index + offset])
        }
        return result
    }

    func readBigEndianUInt64(at index: Index) -> UInt64 {
        var result: UInt64 = 0
        for offset in 0..<8 {
            result = (result << 8) | UInt64(self[index + offset])
        }
        return result
    }
}
