import Foundation

// Shared by profile filtering, snippet filtering, and search-result highlighting.
@objc(iTermProfileSearchToken)
final class iTermProfileSearchToken: NSObject {
    @objc static let tagRestrictionOperator = "tag:"

    @objc private(set) var range = NSRange(location: 0, length: 0)
    @objc private(set) var negated = false
    @objc private(set) var `operator`: String?
    @objc var isTag: Bool { `operator` == Self.tagRestrictionOperator }

    private let nonTagOperators: [String]
    private let query: String
    private let wordCount: Int
    private var anchorStart = false
    private var anchorEnd = false

    @objc(initWithPhrase:)
    convenience init(phrase: String) {
        self.init(phrase: phrase, operators: [Self.tagRestrictionOperator, "name:", "command:"])
    }

    @objc(initWithPhrase:operators:)
    init(phrase originalPhrase: String, operators: [String]) {
        nonTagOperators = operators.filter { $0 != Self.tagRestrictionOperator }
        var phrase = originalPhrase as NSString
        if phrase.hasPrefix("-") {
            negated = true
            phrase = phrase.substring(from: 1) as NSString
        }
        var string = phrase
        for op in operators where phrase.hasPrefix(op) {
            string = phrase.substring(from: (op as NSString).length) as NSString
            `operator` = op
            break
        }

        // Preserve the existing grammar: strip quotes from the whole phrase,
        // not from the remainder after an operator or an anchor.
        if phrase.length >= 2 && phrase.hasPrefix("\"") && phrase.hasSuffix("\"") {
            string = phrase.substring(with: NSRange(location: 1, length: phrase.length - 2)) as NSString
        }
        if string.hasPrefix("^") {
            anchorStart = true
            string = string.substring(from: 1) as NSString
        } else if string.hasPrefix("*") {
            // Legacy syntax for an unanchored search.
            string = string.substring(from: 1) as NSString
        }
        if string.hasSuffix("$") {
            anchorEnd = true
            string = string.substring(to: string.length - 1) as NSString
        }
        query = string as String
        wordCount = string.components(separatedBy: " ").count
        super.init()
    }

    @objc(initWithTag:)
    convenience init(tag: String) {
        self.init(tag: tag, operators: [Self.tagRestrictionOperator, "name:"])
    }

    @objc(initWithTag:operators:)
    init(tag: String, operators: [String]) {
        nonTagOperators = operators.filter { $0 != Self.tagRestrictionOperator }
        `operator` = Self.tagRestrictionOperator
        query = tag
        wordCount = tag.components(separatedBy: " ").count
        super.init()
    }

    @objc(matchesAnyWordIn:operator:)
    func matchesAnyWord(in words: [String]?, operator op: String) -> Bool {
        if let restriction = `operator`, !(op as NSString).isEqual(to: restriction) {
            return false
        }
        return matches(words ?? [])
    }

    @objc(matchesAnyWordInNameWords:)
    func matchesAnyWord(inNameWords words: [String]?) -> Bool {
        if let restriction = `operator`, !isNonTagOperator(restriction) {
            return false
        }
        return matches(words ?? [])
    }

    @objc(matchesAnyWordInTagWords:)
    func matchesAnyWord(inTagWords words: [String]?) -> Bool {
        if let restriction = `operator`, isNonTagOperator(restriction) {
            return false
        }
        return matches(words ?? [])
    }

    private func isNonTagOperator(_ op: String) -> Bool {
        nonTagOperators.contains { ($0 as NSString).isEqual(to: op) }
    }

    private func matches(_ words: [String]) -> Bool {
        if query.isEmpty {
            return true
        }
        guard words.count >= wordCount else { return false }
        var options: NSString.CompareOptions = .caseInsensitive
        if anchorStart {
            options.insert(.anchored)
        }
        var offset = 0
        for index in 0...(words.count - wordCount) {
            let candidate = words[index..<(index + wordCount)].joined(separator: " ") as NSString
            range = candidate.range(of: query, options: options)
            if range.location != NSNotFound {
                if anchorEnd && NSMaxRange(range) != candidate.length {
                    range.location = NSNotFound
                } else {
                    // NSString ranges and offsets remain UTF-16 for AppKit highlighting.
                    range.location += offset
                    return true
                }
            }
            offset += (words[index] as NSString).length + 1
        }
        return false
    }
}
