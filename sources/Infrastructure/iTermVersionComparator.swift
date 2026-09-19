//
//  iTermVersionComparator.swift
//  iTerm2
//

import Foundation

/// Compares dotted versions, including prerelease suffixes such as 3.7beta1.
@objc(iTermVersionComparator)
final class iTermVersionComparator: NSObject {
    private override init() {
        super.init()
    }

    @objc(compareVersion:toVersion:)
    static func compareVersion(_ version: String, toVersion otherVersion: String) -> ComparisonResult {
        let parts = split(version)
        let otherParts = split(otherVersion)
        let commonCount = min(parts.count, otherParts.count)
        for index in 0..<commonCount {
            let result = parts[index].compare(to: otherParts[index])
            if result != .orderedSame {
                return result
            }
        }
        guard parts.count != otherParts.count else {
            return .orderedSame
        }
        let firstIsLonger = parts.count > otherParts.count
        let extraPart = firstIsLonger ? parts[commonCount] : otherParts[commonCount]
        let extraIsPrerelease = extraPart.type == .string
        return firstIsLonger == extraIsPrerelease ? .orderedAscending : .orderedDescending
    }

    private enum PartType {
        case number, string, separator

        init(_ character: unichar) {
            if (CharacterSet.decimalDigits as NSCharacterSet).characterIsMember(character) {
                self = .number
            } else if (CharacterSet.whitespacesAndNewlines as NSCharacterSet).characterIsMember(character) ||
                        (CharacterSet.punctuationCharacters as NSCharacterSet).characterIsMember(character) {
                self = .separator
            } else {
                self = .string
            }
        }
    }

    private struct Part {
        let text: NSString
        let type: PartType

        func compare(to other: Part) -> ComparisonResult {
            guard type == other.type else {
                if type == .string { return .orderedAscending }
                if other.type == .string { return .orderedDescending }
                return type == .number ? .orderedDescending : .orderedAscending
            }
            switch type {
            case .separator:
                return .orderedSame
            case .string:
                // Preserve Foundation collation, including canonical equivalence.
                return text.compare(other.text as String)
            case .number:
                let number = normalizedNumber
                let otherNumber = other.normalizedNumber
                if number.length != otherNumber.length {
                    return number.length < otherNumber.length ? .orderedAscending : .orderedDescending
                }
                return number.compare(otherNumber as String, options: .literal)
            }
        }

        private var normalizedNumber: NSString {
            var start = 0
            while start < text.length && text.character(at: start) == 48 {
                start += 1
            }
            return start == text.length ? "0" : text.substring(from: start) as NSString
        }
    }

    private static func split(_ version: String) -> [Part] {
        // The existing format classifies UTF-16 units, not grapheme clusters.
        let text = version as NSString
        guard text.length > 0 else { return [] }
        var parts = [Part]()
        var start = 0
        var type = PartType(text.character(at: 0))
        for index in 1..<text.length {
            let nextType = PartType(text.character(at: index))
            if nextType != type || type == .separator {
                parts.append(Part(text: text.substring(with: NSRange(location: start, length: index - start))
                                  as NSString, type: type))
                start = index
                type = nextType
            }
        }
        parts.append(Part(text: text.substring(from: start) as NSString, type: type))
        return parts
    }
}
