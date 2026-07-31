//
//  iTermStableSessionID.swift
//  iTerm2
//
//  A stable per-session identifier. Unlike PTYSession.guid, it survives a
//  shell reload and is serialized in the session arrangement so it also
//  survives state restoration.
//

import Foundation

@objc(iTermStableSessionID)
class StableSessionID: NSObject {
    static let prefix = "ptys_"

    private static let alphabetString = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private static let alphabet = Array(alphabetString)
    private static let alphabetIndex: [Character: Int] = {
        var result = [Character: Int]()
        for (index, character) in alphabet.enumerated() {
            result[character] = index
        }
        return result
    }()
    private static let bodyLength = 12

    static let charClass = "[\(alphabetString)]"
    static let tokenPattern = prefix + charClass + "{\(bodyLength + 1)}"

    @objc static func generate() -> String {
        var indices = [Int]()
        indices.reserveCapacity(bodyLength)
        for _ in 0..<bodyLength {
            indices.append(Int(arc4random_uniform(UInt32(alphabet.count))))
        }
        let body = String(indices.map { alphabet[$0] })
        let check = alphabet[checksum(of: indices)]
        return prefix + body + String(check)
    }

    @objc static func isValid(_ candidate: String) -> Bool {
        return canonical(candidate) != nil
    }

    @objc static func canonical(_ candidate: String) -> String? {
        guard candidate.prefix(prefix.count).lowercased() == prefix else {
            return nil
        }
        let rest = candidate.dropFirst(prefix.count)
        guard rest.count == bodyLength + 1 else {
            return nil
        }
        var indices = [Int]()
        indices.reserveCapacity(bodyLength + 1)
        for character in rest {
            guard let index = alphabetIndex[normalize(character)] else {
                return nil
            }
            indices.append(index)
        }
        let bodyIndices = Array(indices.prefix(bodyLength))
        guard indices[bodyLength] == checksum(of: bodyIndices) else {
            return nil
        }
        return prefix + String(indices.map { alphabet[$0] })
    }

    private static func checksum(of body: [Int]) -> Int {
        var sum = 0
        for (index, value) in body.enumerated() {
            sum += (index + 1) * value
        }
        return sum % alphabet.count
    }

    private static func normalize(_ character: Character) -> Character {
        switch character {
        case "i", "I", "l", "L":
            return "1"
        case "o", "O":
            return "0"
        default:
            let uppercase = character.uppercased()
            return uppercase.count == 1 ? Character(uppercase) : character
        }
    }
}
