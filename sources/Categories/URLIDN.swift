//
//  URLIDN.swift
//  iTerm2SharedARC
//

import Foundation

@objc
extension NSURL {
    @objc(IDNEncodedHostname:)
    static func idnEncodedHostname(_ hostname: String) -> String {
        if hostname.canBeConverted(to: .ascii) {
            return hostname
        }
        return hostname
            .components(separatedBy: ".")
            .map { label in
                let normalized = label.precomposedStringWithCompatibilityMapping
                return PunycodeCodec.encode(normalized)
            }
            .joined(separator: ".")
    }

    @objc(IDNDecodedHostname:)
    static func idnDecodedHostname(_ hostname: String) -> String {
        let labels = hostname.components(separatedBy: ".")
        var decodedLabels: [String] = []
        decodedLabels.reserveCapacity(labels.count)
        var changed = false
        for label in labels {
            let decoded = PunycodeCodec.decode(label)
            if !changed && decoded != label {
                changed = true
            }
            decodedLabels.append(decoded)
        }
        return changed ? decodedLabels.joined(separator: ".") : hostname
    }

    @objc(IDNEncodedURL:)
    static func idnEncodedURL(_ urlString: String) -> String {
        transformURLString(urlString, using: idnEncodedHostname)
    }

    @objc(IDNDecodedURL:)
    static func idnDecodedURL(_ urlString: String) -> String {
        transformURLString(urlString, using: idnDecodedHostname)
    }

    private static func transformURLString(_ urlString: String,
                                           using transform: (String) -> String) -> String {
        let authorityStart: String.Index
        if let schemeRange = urlString.range(of: "://") {
            authorityStart = schemeRange.upperBound
        } else {
            authorityStart = urlString.startIndex
        }

        let tail = urlString[authorityStart...]
        let authorityEnd = tail.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? urlString.endIndex
        let authority = urlString[authorityStart..<authorityEnd]

        let hostStart: String.Index
        if let atIndex = authority.lastIndex(of: "@") {
            hostStart = authority.index(after: atIndex)
        } else {
            hostStart = authority.startIndex
        }

        let hostSlice = authority[hostStart...]
        let hostEnd: String.Index
        if hostSlice.hasPrefix("["), let closeBracket = hostSlice.firstIndex(of: "]") {
            hostEnd = hostSlice.index(after: closeBracket)
        } else if let colonIndex = hostSlice.lastIndex(of: ":"),
                  hostSlice[..<colonIndex].contains(":") == false {
            let portSlice = hostSlice[hostSlice.index(after: colonIndex)...]
            if !portSlice.isEmpty && portSlice.allSatisfy({ $0.isASCII && $0.isNumber }) {
                hostEnd = colonIndex
            } else {
                hostEnd = authorityEnd
            }
        } else {
            hostEnd = authorityEnd
        }

        let host = String(urlString[hostStart..<hostEnd])
        let transformedHost = transform(host)
        if transformedHost == host {
            return urlString
        }
        return String(urlString[..<hostStart]) + transformedHost + String(urlString[hostEnd...])
    }
}

private enum PunycodeCodec {
    private static let base = 36
    private static let tMin = 1
    private static let tMax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN = 0x80
    private static let acePrefix = "xn--"

    private static func adapt(delta: Int, numPoints: Int, firstTime: Bool) -> Int {
        var d = firstTime ? delta / damp : delta / 2
        d += d / numPoints
        var k = 0
        let threshold = ((base - tMin) * tMax) / 2
        while d > threshold {
            d /= (base - tMin)
            k += base
        }
        return k + ((base - tMin + 1) * d) / (d + skew)
    }

    private static func encodeDigit(_ d: Int) -> Character {
        if d < 26 {
            return Character(UnicodeScalar(0x61 + d)!)
        }
        return Character(UnicodeScalar(0x30 + (d - 26))!)
    }

    private static func decodeDigit(_ scalar: Unicode.Scalar) -> Int? {
        let v = scalar.value
        if v >= 0x41 && v <= 0x5A {
            return Int(v - 0x41)
        }
        if v >= 0x61 && v <= 0x7A {
            return Int(v - 0x61)
        }
        if v >= 0x30 && v <= 0x39 {
            return Int(v - 0x30) + 26
        }
        return nil
    }

    private static func isValidIDNCodePoint(_ codePoint: Int) -> Bool {
        if codePoint < 0x9F || codePoint > 0x10FFFF {
            return false
        }
        // Reject whitespace and non-printing characters forbidden by RFC 3454 / NAMEPREP.
        if codePoint == 0x00A0 ||
            (codePoint >= 0x2000 && codePoint <= 0x200D) ||
            codePoint == 0x202F ||
            codePoint == 0xFEFF ||
            (codePoint >= 0xFFF9 && codePoint <= 0xFFFF) {
            return false
        }
        // Reject private-use planes and BMP private-use area.
        let plane = codePoint & ~0xFFFF
        if plane == 0x0F0000 || plane == 0x100000 || (codePoint >= 0xE000 && codePoint <= 0xF8FF) {
            return false
        }
        // Reject surrogates and non-characters.
        if (codePoint & 0xFFFE) == 0xFFFE ||
            (codePoint >= 0xD800 && codePoint <= 0xDFFF) ||
            (codePoint >= 0xFDD0 && codePoint <= 0xFDEF) {
            return false
        }
        return UnicodeScalar(codePoint) != nil
    }

    static func encode(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars.map { Int($0.value) })
        if scalars.isEmpty || scalars.allSatisfy({ $0 < 0x80 }) {
            return input
        }

        var output = ""
        for value in scalars where value < 0x80 {
            if let scalar = UnicodeScalar(value) {
                output.unicodeScalars.append(scalar)
            }
        }
        let basicCount = output.unicodeScalars.count
        if basicCount > 0 {
            output.append("-")
        }

        var handled = basicCount
        var n = initialN
        var delta = 0
        var bias = initialBias

        while handled < scalars.count {
            guard let m = scalars.filter({ $0 >= n }).min() else {
                return input
            }
            let (step, overflow1) = (m - n).multipliedReportingOverflow(by: handled + 1)
            if overflow1 {
                return input
            }
            let (nextDelta, overflow2) = delta.addingReportingOverflow(step)
            if overflow2 {
                return input
            }
            delta = nextDelta
            n = m

            for value in scalars {
                if value < n {
                    let (inc, ov) = delta.addingReportingOverflow(1)
                    if ov {
                        return input
                    }
                    delta = inc
                } else if value == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t {
                            break
                        }
                        output.append(encodeDigit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(encodeDigit(q))
                    bias = adapt(delta: delta, numPoints: handled + 1, firstTime: handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }

            let (dInc, ovD) = delta.addingReportingOverflow(1)
            let (nInc, ovN) = n.addingReportingOverflow(1)
            if ovD || ovN {
                return input
            }
            delta = dInc
            n = nInc
        }

        return acePrefix + output
    }

    static func decode(_ label: String) -> String {
        guard label.count >= acePrefix.count,
              label.prefix(acePrefix.count).caseInsensitiveCompare(acePrefix) == .orderedSame,
              label.canBeConverted(to: .ascii) else {
            return label
        }

        let body = String(label.dropFirst(acePrefix.count))
        let basicPart: Substring
        let encodedPart: Substring
        if let dashIndex = body.lastIndex(of: "-") {
            basicPart = body[..<dashIndex]
            encodedPart = body[body.index(after: dashIndex)...]
        } else {
            basicPart = body[body.startIndex..<body.startIndex]
            encodedPart = body[body.startIndex...]
        }

        if encodedPart.isEmpty {
            return label
        }

        var output: [Int] = []
        output.reserveCapacity(basicPart.unicodeScalars.count + encodedPart.unicodeScalars.count)
        for scalar in basicPart.unicodeScalars {
            if scalar.value >= 0x80 {
                return label
            }
            output.append(Int(scalar.value))
        }

        let encodedScalars = Array(encodedPart.unicodeScalars)
        var idx = 0
        var n = initialN
        var i = 0
        var bias = initialBias

        while idx < encodedScalars.count {
            let oldi = i
            var w = 1
            var k = base
            while true {
                guard idx < encodedScalars.count,
                      let digit = decodeDigit(encodedScalars[idx]) else {
                    return label
                }
                idx += 1

                let (prod, ov1) = digit.multipliedReportingOverflow(by: w)
                if ov1 {
                    return label
                }
                let (nextI, ov2) = i.addingReportingOverflow(prod)
                if ov2 {
                    return label
                }
                i = nextI

                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t {
                    break
                }
                let (nextW, ov3) = w.multipliedReportingOverflow(by: base - t)
                if ov3 {
                    return label
                }
                w = nextW
                k += base
            }

            let outCount = output.count + 1
            bias = adapt(delta: i - oldi, numPoints: outCount, firstTime: oldi == 0)
            let (nNext, ov4) = n.addingReportingOverflow(i / outCount)
            if ov4 {
                return label
            }
            n = nNext
            i %= outCount

            guard isValidIDNCodePoint(n) else {
                return label
            }
            output.insert(n, at: i)
            i += 1
        }

        var decoded = ""
        decoded.unicodeScalars.reserveCapacity(output.count)
        for value in output {
            guard let scalar = UnicodeScalar(value) else {
                return label
            }
            decoded.unicodeScalars.append(scalar)
        }

        let normalized = decoded.precomposedStringWithCompatibilityMapping
        guard decoded.unicodeScalars.elementsEqual(normalized.unicodeScalars) else {
            return label
        }
        return decoded
    }
}
