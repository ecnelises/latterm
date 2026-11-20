//
//  SixelDecoder.swift
//  Latterm
//

import AppKit

@objc(iTermSixelDecoder)
public final class SixelDecoder: NSObject {
    @objc public static let maxPaletteRegisters: Int = 1024

    private static let maxDimension: Int = 9_999
    private static let maxTotalPixels: Int = 33_554_432 // 32 MP (128 MB RGBA cap)
    private static let maxRepeatCount: Int = 0xFFFF
    private static let maxParams: Int = 16

    private enum State {
        case ground
        case esc
        case dcs
        case body
        case rasterAttributes // " Pan ; Pad ; Ph ; Pv
        case repeatIntroducer // ! Pn <ch>
        case colorIntroducer  // # Pc [; Pu ; Px ; Py ; Pz]
    }

    @objc(decodeImageFromData:)
    public static func decodeImage(from data: Data) -> NSImage? {
        guard !data.isEmpty else {
            return nil
        }
        return data.withUnsafeBytes { rawBuffer -> NSImage? in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return decodeBytes(base, count: rawBuffer.count)
        }
    }

    // MARK: - Core State Machine

    private static func decodeBytes(_ bytes: UnsafePointer<UInt8>, count: Int) -> NSImage? {
        var palette = makeDefaultPalette()

        var state: State = .ground
        var enteredSixel = false
        var transparentBackground = false

        var posX = 0
        var posY = 0
        var maxPaintedX = -1
        var maxPaintedY = -1
        var sawSixelCell = false
        var attributedPh = 0
        var attributedPv = 0
        var repeatCount = 1
        var colorIndex = 15

        var currentParam = -1
        var params = [Int](repeating: 0, count: maxParams)
        var paramCount = 0

        var bufWidth = 0
        var bufHeight = 0
        var pixels: [UInt32] = []

        func ensureCapacity(minWidth: Int, minHeight: Int) -> Bool {
            guard minWidth > 0, minHeight > 0,
                  minWidth <= maxDimension, minHeight <= maxDimension else {
                return false
            }
            if minWidth <= bufWidth && minHeight <= bufHeight {
                return true
            }
            var newWidth = max(bufWidth, 64)
            while newWidth < minWidth {
                newWidth = min(newWidth * 2, maxDimension)
                if newWidth < minWidth && newWidth == maxDimension {
                    return false
                }
            }
            var newHeight = max(bufHeight, 64)
            while newHeight < minHeight {
                newHeight = min(newHeight * 2, maxDimension)
                if newHeight < minHeight && newHeight == maxDimension {
                    return false
                }
            }
            guard newWidth * newHeight <= maxTotalPixels else {
                return false
            }
            var newPixels = [UInt32](repeating: 0, count: newWidth * newHeight)
            if bufWidth > 0 && bufHeight > 0 {
                pixels.withUnsafeBufferPointer { srcBuf in
                    newPixels.withUnsafeMutableBufferPointer { dstBuf in
                        guard let src = srcBuf.baseAddress, let dst = dstBuf.baseAddress else {
                            return
                        }
                        for row in 0..<bufHeight {
                            dst.advanced(by: row * newWidth)
                                .update(from: src.advanced(by: row * bufWidth), count: bufWidth)
                        }
                    }
                }
            }
            pixels = newPixels
            bufWidth = newWidth
            bufHeight = newHeight
            return true
        }

        func accumulateDigit(_ byte: UInt8) -> Bool {
            let digit = Int(byte - 0x30)
            if currentParam < 0 {
                currentParam = 0
            }
            if currentParam > (Int(Int32.max) - digit) / 10 {
                return false
            }
            currentParam = currentParam * 10 + digit
            return true
        }

        func pushParam() {
            let value = max(currentParam, 0)
            if paramCount < maxParams {
                params[paramCount] = value
                paramCount += 1
            }
            currentParam = 0
        }

        func resetParams(initialCurrent: Int = 0) {
            paramCount = 0
            currentParam = initialCurrent
        }

        var index = 0
        decodeLoop: while index < count {
            let b = bytes[index]

            switch state {
            case .ground:
                if b == 0x1B {
                    state = .esc
                } else if b == 0x90 {
                    resetParams(initialCurrent: -1)
                    state = .dcs
                } else if b == 0x9C {
                    break decodeLoop
                }
                index += 1

            case .esc:
                if b == 0x5C || b == 0x9C { // '\\' or C1 ST
                    break decodeLoop
                } else if b == 0x50 { // 'P' -> DCS
                    resetParams(initialCurrent: -1)
                    state = .dcs
                } else if enteredSixel {
                    state = .body
                } else {
                    state = .ground
                }
                index += 1

            case .dcs:
                if b == 0x1B {
                    state = .esc
                    index += 1
                } else if b == 0x9C {
                    break decodeLoop
                } else if b >= 0x30 && b <= 0x39 {
                    guard accumulateDigit(b) else { return nil }
                    index += 1
                } else if b == 0x3B { // ';'
                    pushParam()
                    index += 1
                } else if b == 0x71 { // 'q' -> enter SIXEL body
                    if currentParam >= 0 && paramCount < maxParams {
                        params[paramCount] = currentParam
                        paramCount += 1
                    }
                    if paramCount >= 2 && params[1] == 1 {
                        transparentBackground = true
                    }
                    resetParams()
                    enteredSixel = true
                    state = .body
                    index += 1
                } else {
                    index += 1
                }

            case .body:
                switch b {
                case 0x1B:
                    state = .esc
                    index += 1
                case 0x9C:
                    break decodeLoop
                case 0x22: // '"' DECGRA
                    resetParams()
                    state = .rasterAttributes
                    index += 1
                case 0x21: // '!' DECGRI
                    resetParams()
                    state = .repeatIntroducer
                    index += 1
                case 0x23: // '#' DECGCI
                    resetParams()
                    state = .colorIntroducer
                    index += 1
                case 0x24: // '$' DECGCR
                    posX = 0
                    repeatCount = 1
                    index += 1
                case 0x2D: // '-' DECGNL
                    guard posY >= 0 && posY <= maxDimension - 6 else {
                        return nil
                    }
                    posX = 0
                    posY += 6
                    repeatCount = 1
                    index += 1
                case 0x3F...0x7E: // '?'...'~' sixel bitmap column
                    guard posX >= 0, posY >= 0,
                          posX < maxDimension, posY <= maxDimension - 6,
                          posX + repeatCount <= maxDimension else {
                        return nil
                    }
                    guard ensureCapacity(minWidth: posX + repeatCount, minHeight: posY + 6) else {
                        return nil
                    }
                    sawSixelCell = true
                    let bits = Int(b - 0x3F)
                    if bits != 0 {
                        let color = palette[colorIndex]
                        pixels.withUnsafeMutableBufferPointer { dstBuf in
                            guard let dst = dstBuf.baseAddress else { return }
                            for bit in 0..<6 where (bits & (1 << bit)) != 0 {
                                let y = posY + bit
                                let rowStart = y * bufWidth + posX
                                dst.advanced(by: rowStart).update(repeating: color, count: repeatCount)
                                if y > maxPaintedY {
                                    maxPaintedY = y
                                }
                            }
                        }
                        let endX = posX + repeatCount - 1
                        if endX > maxPaintedX {
                            maxPaintedX = endX
                        }
                    }
                    posX += repeatCount
                    repeatCount = 1
                    index += 1
                default:
                    index += 1
                }

            case .rasterAttributes:
                if b == 0x1B {
                    state = .esc
                    index += 1
                } else if b == 0x9C {
                    break decodeLoop
                } else if b >= 0x30 && b <= 0x39 {
                    guard accumulateDigit(b) else { return nil }
                    index += 1
                } else if b == 0x3B {
                    pushParam()
                    index += 1
                } else {
                    pushParam()
                    if paramCount > 2 && params[2] > 0 {
                        attributedPh = params[2]
                    }
                    if paramCount > 3 && params[3] > 0 {
                        attributedPv = params[3]
                    }
                    if attributedPh > 0 || attributedPv > 0 {
                        let reqW = max(bufWidth, max(attributedPh, 1))
                        let reqH = max(bufHeight, max(attributedPv, 1))
                        guard ensureCapacity(minWidth: reqW, minHeight: reqH) else {
                            return nil
                        }
                    }
                    resetParams()
                    state = .body
                    // Do not advance index: re-dispatch terminating byte in `.body`.
                }

            case .repeatIntroducer:
                if b == 0x1B {
                    state = .esc
                    index += 1
                } else if b == 0x9C {
                    break decodeLoop
                } else if b >= 0x30 && b <= 0x39 {
                    guard accumulateDigit(b) else { return nil }
                    index += 1
                } else {
                    let countValue = currentParam <= 0 ? 1 : currentParam
                    guard countValue <= maxRepeatCount else {
                        return nil
                    }
                    repeatCount = countValue
                    resetParams()
                    state = .body
                    // Re-dispatch the sixel character in `.body`.
                }

            case .colorIntroducer:
                if b == 0x1B {
                    state = .esc
                    index += 1
                } else if b == 0x9C {
                    break decodeLoop
                } else if b >= 0x30 && b <= 0x39 {
                    guard accumulateDigit(b) else { return nil }
                    index += 1
                } else if b == 0x3B {
                    pushParam()
                    index += 1
                } else {
                    pushParam()
                    if paramCount > 0 {
                        colorIndex = min(max(params[0], 0), maxPaletteRegisters - 1)
                    }
                    if paramCount >= 5 {
                        let colorSpace = params[1]
                        if colorSpace == 1 {
                            palette[colorIndex] = hlsToRGBA(hue: params[2], lum: params[3], sat: params[4])
                        } else if colorSpace == 2 {
                            palette[colorIndex] = rgbPercentToRGBA(r: params[2], g: params[3], b: params[4])
                        }
                    }
                    resetParams()
                    state = .body
                    // Re-dispatch terminating byte in `.body`.
                }
            }
        }

        guard enteredSixel else {
            return nil
        }

        var finalWidth = max(maxPaintedX + 1, attributedPh)
        var finalHeight = max(maxPaintedY + 1, attributedPv)
        if finalWidth <= 0 || finalHeight <= 0 {
            guard sawSixelCell else {
                return nil
            }
            finalWidth = max(posX, 1)
            finalHeight = max(posY + 6, 1)
        }
        guard finalWidth <= maxDimension, finalHeight <= maxDimension,
              finalWidth * finalHeight <= maxTotalPixels else {
            return nil
        }
        if finalWidth > bufWidth || finalHeight > bufHeight {
            guard ensureCapacity(minWidth: finalWidth, minHeight: finalHeight) else {
                return nil
            }
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: finalWidth,
            pixelsHigh: finalHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: finalWidth * 4,
            bitsPerPixel: 32
        ), let dstBytes = rep.bitmapData else {
            return nil
        }

        let bgColor: UInt32 = transparentBackground ? 0 : palette[0]
        dstBytes.withMemoryRebound(to: UInt32.self, capacity: finalWidth * finalHeight) { dstPixels in
            pixels.withUnsafeBufferPointer { srcBuf in
                guard let src = srcBuf.baseAddress else { return }
                for row in 0..<finalHeight {
                    let srcRow = src.advanced(by: row * bufWidth)
                    let dstRow = dstPixels.advanced(by: row * finalWidth)
                    if bgColor == 0 {
                        dstRow.update(from: srcRow, count: finalWidth)
                    } else {
                        for col in 0..<finalWidth {
                            let v = srcRow[col]
                            dstRow[col] = (v == 0) ? bgColor : v
                        }
                    }
                }
            }
        }

        let imageSize = NSSize(width: finalWidth, height: finalHeight)
        let image = NSImage(size: imageSize)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Palette Helpers

    @inline(__always)
    private static func packRGBA(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 0xFF) -> UInt32 {
        return UInt32(r) | (UInt32(g) << 8) | (UInt32(b) << 16) | (UInt32(a) << 24)
    }

    @inline(__always)
    private static func percentToByte(_ value: Int) -> UInt8 {
        let clamped = min(max(value, 0), 100)
        return UInt8((clamped * 255 + 50) / 100)
    }

    private static func rgbPercentToRGBA(r: Int, g: Int, b: Int) -> UInt32 {
        return packRGBA(percentToByte(r), percentToByte(g), percentToByte(b))
    }

    private static func hlsToRGBA(hue: Int, lum: Int, sat: Int) -> UInt32 {
        let l = min(max(lum, 0), 100)
        let s = min(max(sat, 0), 100)
        if s == 0 {
            let gray = percentToByte(l)
            return packRGBA(gray, gray, gray)
        }

        let lf = Double(l)
        let sf = Double(s)
        let spread = (1.0 - (lf > 50.0 ? (2.0 * (lf / 100.0) - 1.0) : -(2.0 * (lf / 100.0) - 1.0))) / 2.0
        let maxVal = lf + sf * spread
        let minVal = lf - sf * spread

        // VT340 SIXEL HLS places Blue at 0°, Red at 120°, and Green at 240°.
        let h = (min(max(hue, 0), 360) + 240) % 360
        let hd = Double(h)
        let r: Double
        let g: Double
        let b: Double
        switch h / 60 {
        case 0:
            r = maxVal
            g = minVal + (maxVal - minVal) * (hd / 60.0)
            b = minVal
        case 1:
            r = minVal + (maxVal - minVal) * ((120.0 - hd) / 60.0)
            g = maxVal
            b = minVal
        case 2:
            r = minVal
            g = maxVal
            b = minVal + (maxVal - minVal) * ((hd - 120.0) / 60.0)
        case 3:
            r = minVal
            g = minVal + (maxVal - minVal) * ((240.0 - hd) / 60.0)
            b = maxVal
        case 4:
            r = minVal + (maxVal - minVal) * ((hd - 240.0) / 60.0)
            g = minVal
            b = maxVal
        default:
            r = maxVal
            g = minVal
            b = minVal + (maxVal - minVal) * ((360.0 - hd) / 60.0)
        }
        return rgbPercentToRGBA(r: Int(r), g: Int(g), b: Int(b))
    }

    private static func makeDefaultPalette() -> [UInt32] {
        var palette = [UInt32](repeating: packRGBA(255, 255, 255), count: maxPaletteRegisters)

        // VT340 default 16-color palette
        let vt340Defaults: [(Int, Int, Int)] = [
            (0, 0, 0),    //  0 Black
            (20, 20, 80), //  1 Blue
            (80, 13, 13), //  2 Red
            (20, 80, 20), //  3 Green
            (80, 20, 80), //  4 Magenta
            (20, 80, 80), //  5 Cyan
            (80, 80, 20), //  6 Yellow
            (53, 53, 53), //  7 Gray 50%
            (26, 26, 26), //  8 Gray 25%
            (33, 33, 60), //  9 Blue*
            (60, 26, 26), // 10 Red*
            (33, 60, 33), // 11 Green*
            (60, 33, 60), // 12 Magenta*
            (33, 60, 60), // 13 Cyan*
            (60, 60, 33), // 14 Yellow*
            (80, 80, 80)  // 15 Gray 75%
        ]
        for (idx, rgb) in vt340Defaults.enumerated() {
            palette[idx] = rgbPercentToRGBA(r: rgb.0, g: rgb.1, b: rgb.2)
        }

        // Indices 16..231: 6x6x6 xterm color cube
        var idx = 16
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    palette[idx] = packRGBA(UInt8(r * 51), UInt8(g * 51), UInt8(b * 51))
                    idx += 1
                }
            }
        }

        // Indices 232..255: 24-step grayscale ramp
        for step in 0..<24 {
            let v = UInt8(step * 11)
            palette[idx] = packRGBA(v, v, v)
            idx += 1
        }

        return palette
    }
}
