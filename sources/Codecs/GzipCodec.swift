//
//  GzipCodec.swift
//  iTerm2SharedARC
//

import Foundation
import zlib

@objc
extension NSData {
    @objc(isGzippedData)
    var isGzippedData: Bool {
        (self as Data).starts(with: [0x1f, 0x8b])
    }

    @objc(gzippedDataWithCompressionLevel:)
    func gzippedData(compressionLevel level: Float) -> Data? {
        let input = self as Data
        if input.isEmpty || isGzippedData {
            return input
        }

        var stream = z_stream()
        let compression: Int32 = level < 0.0 ? Z_DEFAULT_COMPRESSION : Int32(roundf(level * 9.0))
        guard deflateInit2_(
            &stream,
            compression,
            Z_DEFLATED,
            31,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        let chunkSize = 16384
        var output = Data(count: chunkSize)
        var status: Int32 = Z_OK
        input.withUnsafeBytes { rawInput in
            guard let inBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                return
            }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(rawInput.count)
            while status == Z_OK && stream.avail_out == 0 {
                let totalOut = Int(stream.total_out)
                if totalOut >= output.count {
                    output.count += chunkSize
                }
                status = output.withUnsafeMutableBytes { rawOutput in
                    guard let outBase = rawOutput.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_MEM_ERROR
                    }
                    stream.next_out = outBase.advanced(by: totalOut)
                    stream.avail_out = uInt(rawOutput.count - totalOut)
                    return deflate(&stream, Z_FINISH)
                }
                if status != Z_OK && status != Z_STREAM_END {
                    return
                }
            }
        }
        guard status == Z_STREAM_END else {
            return nil
        }
        output.count = Int(stream.total_out)
        return output
    }

    @objc(gzippedData)
    func gzippedData() -> Data? {
        gzippedData(compressionLevel: -1.0)
    }

    @objc(gunzippedData)
    func gunzippedData() -> Data? {
        let input = self as Data
        if input.isEmpty || !isGzippedData {
            return input
        }

        var stream = z_stream()
        guard inflateInit2_(
            &stream,
            47,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            return nil
        }

        let growthStep = Swift.max(1, input.count / 2)
        var output = Data(count: Swift.max(16, input.count * 2))
        var status: Int32 = Z_OK
        input.withUnsafeBytes { rawInput in
            guard let inBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                status = Z_DATA_ERROR
                return
            }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(rawInput.count)
            while status == Z_OK {
                let totalOut = Int(stream.total_out)
                if totalOut >= output.count {
                    output.count += growthStep
                }
                status = output.withUnsafeMutableBytes { rawOutput in
                    guard let outBase = rawOutput.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_MEM_ERROR
                    }
                    stream.next_out = outBase.advanced(by: totalOut)
                    stream.avail_out = uInt(rawOutput.count - totalOut)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                if status == Z_OK && stream.avail_in == 0 && stream.avail_out > 0 {
                    // Truncated gzip input with no more bytes to consume.
                    status = Z_DATA_ERROR
                }
            }
        }
        let endStatus = inflateEnd(&stream)
        guard status == Z_STREAM_END, endStatus == Z_OK else {
            return nil
        }
        output.count = Int(stream.total_out)
        return output
    }
}
