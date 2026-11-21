//
//  ExpressionParserCore.swift
//  Latterm
//

import Foundation

/// Zero-dependency tokenizer and recursive-descent parser for Latterm's `\(...)`
/// expression language and function-call autocomplete suggester, replacing `CoreParse`.
@objc(iTermNativeExpressionCore)
final class ExpressionParserCore: NSObject {
    @objc static func parseInvocation(_ invocation: String,
                                      start: String,
                                      parserOwner: iTermExpressionParser) -> iTermParsedExpression {
        let tokens = ExpressionLexer.tokenize(invocation, tolerateTruncatedStrings: false)
        var parser = ExpressionEvaluationParser(input: invocation, tokens: tokens, owner: parserOwner)
        do {
            if start == "callsequence" {
                return try parser.parseCallSequenceRoot()
            } else {
                return try parser.parseExpressionRoot()
            }
        } catch let error as ExpressionParseFailure {
            return iTermParsedExpression(error: error.nsError)
        } catch {
            let fallback = NSError(
                domain: "com.iterm2.parser",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            return iTermParsedExpression(error: fallback)
        }
    }

    @objc static func parseForSuggestions(_ prefix: String,
                                          start: String,
                                          callBuilder: @escaping (String, [String: Any]) -> Any) -> Any? {
        let tokens = ExpressionLexer.tokenize(prefix, tolerateTruncatedStrings: true)
        var parser = ExpressionSuggestionParser(tokens: tokens, callBuilder: callBuilder)
        if start == "callsequence" {
            return parser.parseCallSequenceRoot()
        } else {
            return parser.parseExpressionRoot()
        }
    }
}

// MARK: - Tokens & Lexer

private enum ExpressionToken {
    case optionalPath(String, offset: Int)
    case symbol(String, offset: Int)
    case boolean(Bool, offset: Int)
    case number(NSNumber, offset: Int)
    case identifier(String, offset: Int)
    case swiftyString(content: String, truncated: Bool, endsWithLiteral: Bool, truncatedPart: String?, offset: Int)
    case invalid(offset: Int)
    case eof(offset: Int)

    var offset: Int {
        switch self {
        case let .optionalPath(_, offset),
             let .symbol(_, offset),
             let .boolean(_, offset),
             let .number(_, offset),
             let .identifier(_, offset),
             let .swiftyString(_, _, _, _, offset),
             let .invalid(offset),
             let .eof(offset):
            return offset
        }
    }
}

private enum ExpressionLexer {
    private static let optionalPathExcludedKeywords: Set<String> = ["true", "false", "null"]
    private static let twoCharSymbols: [String] = ["==", "!=", "<=", ">=", "&&", "||"]
    private static let oneCharSymbols: Set<unichar> = Set(
        "<>():,.?[];&+-*/!=".utf16.map { unichar($0) }
    )

    static func tokenize(_ input: String, tolerateTruncatedStrings: Bool) -> [ExpressionToken] {
        let nsString = input as NSString
        let length = nsString.length
        let whitespace = CharacterSet.whitespacesAndNewlines as NSCharacterSet
        var tokens: [ExpressionToken] = []
        var pos = 0

        while pos < length {
            let ch = nsString.character(at: pos)
            if whitespace.characterIsMember(ch) {
                pos += 1
                continue
            }

            // 1. OptionalPath ("name?" or "user.path?" with no space before '?')
            if let (optPath, nextPos) = scanOptionalPath(in: nsString, length: length, from: pos) {
                tokens.append(.optionalPath(optPath, offset: pos))
                pos = nextPos
                continue
            }

            // 2. Quoted SwiftyString ("...")
            if ch == 0x22 { // '"'
                if let (tok, nextPos) = scanSwiftyString(
                    in: nsString,
                    length: length,
                    from: pos,
                    tolerateTruncation: tolerateTruncatedStrings
                ) {
                    tokens.append(tok)
                    pos = nextPos
                    continue
                } else {
                    tokens.append(.invalid(offset: pos))
                    return tokens + [.eof(offset: length)]
                }
            }

            // 3. Multi-character operators
            if pos + 2 <= length {
                let two = nsString.substring(with: NSRange(location: pos, length: 2))
                if twoCharSymbols.contains(two) {
                    tokens.append(.symbol(two, offset: pos))
                    pos += 2
                    continue
                }
            }

            // 4. Single-character punctuation & operators
            if oneCharSymbols.contains(ch) {
                let sym = nsString.substring(with: NSRange(location: pos, length: 1))
                tokens.append(.symbol(sym, offset: pos))
                pos += 1
                continue
            }

            // 5. Numeric literal (starts with ASCII digit '0'...'9')
            if ch >= 0x30 && ch <= 0x39,
               let (number, nextPos) = scanNumber(in: nsString, length: length, from: pos) {
                tokens.append(.number(number, offset: pos))
                pos = nextPos
                continue
            }

            // 6. Identifier or boolean keyword ('true' / 'false')
            if isIdentifierStart(ch) {
                let start = pos
                pos += 1
                while pos < length && isIdentifierBody(nsString.character(at: pos)) {
                    pos += 1
                }
                let word = nsString.substring(with: NSRange(location: start, length: pos - start))
                if word == "true" {
                    tokens.append(.boolean(true, offset: start))
                } else if word == "false" {
                    tokens.append(.boolean(false, offset: start))
                } else {
                    tokens.append(.identifier(word, offset: start))
                }
                continue
            }

            tokens.append(.invalid(offset: pos))
            return tokens + [.eof(offset: length)]
        }

        tokens.append(.eof(offset: length))
        return tokens
    }

    private static func scanNumber(in nsString: NSString,
                                   length: Int,
                                   from start: Int) -> (NSNumber, Int)? {
        var pos = start
        while pos < length && isDigit(nsString.character(at: pos)) {
            pos += 1
        }
        guard pos > start else { return nil }

        if pos < length && nsString.character(at: pos) == 0x2E { // '.'
            let dotPos = pos
            pos += 1
            while pos < length && isDigit(nsString.character(at: pos)) {
                pos += 1
            }
            if pos == dotPos + 1 {
                // Allow trailing decimal like "1." just like NSScanner.scanDouble,
                // unless followed by identifier start (e.g. method/property notation)
                if pos < length && isIdentifierStart(nsString.character(at: pos)) {
                    pos = dotPos
                }
            }
        }

        if pos < length {
            let expChar = nsString.character(at: pos)
            if expChar == 0x65 || expChar == 0x45 { // 'e' or 'E'
                let expPos = pos
                var cursor = pos + 1
                if cursor < length {
                    let sign = nsString.character(at: cursor)
                    if sign == 0x2B || sign == 0x2D { // '+' or '-'
                        cursor += 1
                    }
                }
                let digitsStart = cursor
                while cursor < length && isDigit(nsString.character(at: cursor)) {
                    cursor += 1
                }
                if cursor > digitsStart {
                    pos = cursor
                } else {
                    pos = expPos
                }
            }
        }

        let raw = nsString.substring(with: NSRange(location: start, length: pos - start))
        guard let value = Double(raw) else { return nil }
        return (NSNumber(value: value), pos)
    }

    private static func isDigit(_ c: unichar) -> Bool {
        c >= 0x30 && c <= 0x39
    }

    private static func scanOptionalPath(in nsString: NSString,
                                         length: Int,
                                         from start: Int) -> (String, Int)? {
        guard start < length, isIdentifierStart(nsString.character(at: start)) else {
            return nil
        }
        var pos = start + 1
        while pos < length && isOptionalPathBody(nsString.character(at: pos)) {
            pos += 1
        }
        guard pos < length, nsString.character(at: pos) == 0x3F else { // '?'
            return nil
        }
        let path = nsString.substring(with: NSRange(location: start, length: pos - start))
        guard !optionalPathExcludedKeywords.contains(path), !path.hasSuffix(".") else {
            return nil
        }
        return (path, pos + 1)
    }

    private static func scanSwiftyString(in nsString: NSString,
                                         length: Int,
                                         from start: Int,
                                         tolerateTruncation: Bool) -> (ExpressionToken, Int)? {
        let substring = nsString.substring(from: start + 1)
        let parser = iTermSwiftyStringParser(string: substring)
        parser.stopAtUnescapedQuote = true
        parser.tolerateTruncation = tolerateTruncation
        let index = parser.enumerateSwiftySubstrings(block: nil)
        if index == NSNotFound {
            return nil
        }
        if parser.wasTruncated {
            let truncatedPart = (substring as NSString).substring(from: index)
            let tok = ExpressionToken.swiftyString(
                content: substring,
                truncated: true,
                endsWithLiteral: parser.wasTruncatedInLiteral,
                truncatedPart: truncatedPart,
                offset: start
            )
            return (tok, length)
        } else {
            let content = (substring as NSString).substring(to: index)
            let tok = ExpressionToken.swiftyString(
                content: content,
                truncated: false,
                endsWithLiteral: false,
                truncatedPart: nil,
                offset: start
            )
            return (tok, start + index + 2)
        }
    }

    private static func isIdentifierStart(_ c: unichar) -> Bool {
        (c >= 0x61 && c <= 0x7A) // a-z
            || (c >= 0x41 && c <= 0x5A) // A-Z
            || c == 0x5F // _
    }

    private static func isIdentifierBody(_ c: unichar) -> Bool {
        isIdentifierStart(c)
            || (c >= 0x30 && c <= 0x39) // 0-9
            || c == 0x2D // -
    }

    private static func isOptionalPathBody(_ c: unichar) -> Bool {
        isIdentifierStart(c)
            || (c >= 0x30 && c <= 0x39) // 0-9
            || c == 0x2E // .
    }
}

// MARK: - Evaluation Parser (`iTermExpressionParser`)

private struct ExpressionParseFailure: Error {
    let nsError: NSError
}

private struct ExpressionEvaluationParser {
    private let input: String
    private let tokens: [ExpressionToken]
    private unowned let owner: iTermExpressionParser
    private var index = 0

    init(input: String, tokens: [ExpressionToken], owner: iTermExpressionParser) {
        self.input = input
        self.tokens = tokens
        self.owner = owner
    }

    private func peek(_ delta: Int = 0) -> ExpressionToken {
        let idx = index + delta
        guard idx >= 0 && idx < tokens.count else {
            return tokens.last ?? .eof(offset: (input as NSString).length)
        }
        return tokens[idx]
    }

    @discardableResult
    private mutating func advance() -> ExpressionToken {
        let tok = peek()
        if index < tokens.count - 1 {
            index += 1
        }
        return tok
    }

    private func syntaxError(_ expected: String) -> ExpressionParseFailure {
        let offset = peek().offset
        let reason = "Syntax error at index \(offset) of “\(input)”. Expected: “\(expected)”"
        let err = NSError(
            domain: "com.iterm2.parser",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
        return ExpressionParseFailure(nsError: err)
    }

    private mutating func expectSymbol(_ sym: String) throws {
        guard case let .symbol(actual, _) = peek(), actual == sym else {
            throw syntaxError(sym)
        }
        _ = advance()
    }

    private mutating func matchSymbol(_ sym: String) -> Bool {
        if case let .symbol(actual, _) = peek(), actual == sym {
            _ = advance()
            return true
        }
        return false
    }

    private var isAtEOF: Bool {
        if case .eof = peek() { return true }
        return false
    }

    // MARK: Roots

    mutating func parseCallSequenceRoot() throws -> iTermParsedExpression {
        var calls: [iTermParsedExpression] = [try parseCall()]
        while matchSymbol(";") {
            calls.append(try parseCall())
        }
        guard isAtEOF else {
            throw syntaxError("EOF")
        }
        if calls.count == 1 {
            return calls[0]
        }
        for call in calls where call.expressionType == .error {
            return call
        }
        let extracted = calls.map { $0.functionCall }
        return owner.callSequence(with: extracted)
    }

    mutating func parseExpressionRoot() throws -> iTermParsedExpression {
        let expr = try parseExpression()
        guard isAtEOF else {
            throw syntaxError("EOF")
        }
        return expr
    }

    // MARK: Expressions

    private mutating func parseExpression() throws -> iTermParsedExpression {
        if case .symbol("[", _) = peek() {
            return try parseArrayLiteral()
        }
        return try parseSubexpression()
    }

    private mutating func parseArrayLiteral() throws -> iTermParsedExpression {
        try expectSymbol("[")
        if matchSymbol("]") {
            return iTermParsedExpression(arrayOf: [])
        }
        var elements: [iTermParsedExpression] = [try parseExpression()]
        while matchSymbol(",") {
            elements.append(try parseExpression())
        }
        try expectSymbol("]")
        return iTermParsedExpression(arrayOf: elements)
    }

    private mutating func parseSubexpression() throws -> iTermParsedExpression {
        return try parseConditionalExpression()
    }

    private mutating func parseConditionalExpression() throws -> iTermParsedExpression {
        let lhs = try parseLogicalOr()
        if matchSymbol("?") {
            if isConditionalFollowToken(peek()) {
                return lhs.optionalized()
            }
            let whenTrue = try parseConditionalExpression()
            try expectSymbol(":")
            let whenFalse = try parseConditionalExpression()
            let sub = Subexpression(
                condition: lhs.asSubexpression(),
                whenTrue: whenTrue.asSubexpression(),
                whenFalse: whenFalse.asSubexpression()
            )
            return iTermParsedExpression(subexpression: sub)
        }
        return lhs.deoptionalized()
    }

    private func isConditionalFollowToken(_ token: ExpressionToken) -> Bool {
        switch token {
        case .eof:
            return true
        case let .symbol(s, _) where s == ")" || s == "," || s == "]" || s == ":":
            return true
        default:
            return false
        }
    }

    private mutating func parseLogicalOr() throws -> iTermParsedExpression {
        var lhs = try parseLogicalAnd()
        while matchSymbol("||") {
            let rhs = try parseLogicalAnd()
            let sub = Subexpression(lhs: lhs.asSubexpression(), logicalOr: rhs.asSubexpression())
            lhs = iTermParsedExpression(subexpression: sub)
        }
        return lhs
    }

    private mutating func parseLogicalAnd() throws -> iTermParsedExpression {
        var lhs = try parseEquality()
        while matchSymbol("&&") {
            let rhs = try parseEquality()
            let sub = Subexpression(lhs: lhs.asSubexpression(), logicalAnd: rhs.asSubexpression())
            lhs = iTermParsedExpression(subexpression: sub)
        }
        return lhs
    }

    private mutating func parseEquality() throws -> iTermParsedExpression {
        var lhs = try parseRelational()
        while true {
            if matchSymbol("==") {
                let rhs = try parseRelational()
                let sub = Subexpression(lhs: lhs.asSubexpression(), equalTo: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol("!=") {
                let rhs = try parseRelational()
                let sub = Subexpression(lhs: lhs.asSubexpression(), notEqualTo: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else {
                break
            }
        }
        return lhs
    }

    private mutating func parseRelational() throws -> iTermParsedExpression {
        var lhs = try parseAdditive()
        while true {
            if matchSymbol("<=") {
                let rhs = try parseAdditive()
                let sub = Subexpression(lhs: lhs.asSubexpression(), lessThanOrEqual: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol(">=") {
                let rhs = try parseAdditive()
                let sub = Subexpression(lhs: lhs.asSubexpression(), greaterThanOrEqual: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol("<") {
                let rhs = try parseAdditive()
                let sub = Subexpression(lhs: lhs.asSubexpression(), lessThan: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol(">") {
                let rhs = try parseAdditive()
                let sub = Subexpression(lhs: lhs.asSubexpression(), greaterThan: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else {
                break
            }
        }
        return lhs
    }

    private mutating func parseAdditive() throws -> iTermParsedExpression {
        var lhs = try parseMultiplicative()
        while true {
            if matchSymbol("+") {
                let rhs = try parseMultiplicative()
                let sub = Subexpression(lhs: lhs.asSubexpression(), plus: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol("-") {
                let rhs = try parseMultiplicative()
                let sub = Subexpression(lhs: lhs.asSubexpression(), minus: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else {
                break
            }
        }
        return lhs
    }

    private mutating func parseMultiplicative() throws -> iTermParsedExpression {
        var lhs = try parseUnary()
        while true {
            if matchSymbol("*") {
                let rhs = try parseUnary()
                let sub = Subexpression(lhs: lhs.asSubexpression(), times: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else if matchSymbol("/") {
                let rhs = try parseUnary()
                let sub = Subexpression(lhs: lhs.asSubexpression(), dividedBy: rhs.asSubexpression())
                lhs = iTermParsedExpression(subexpression: sub)
            } else {
                break
            }
        }
        return lhs
    }

    private mutating func parseUnary() throws -> iTermParsedExpression {
        if matchSymbol("!") {
            let operand = try parseUnary()
            return iTermParsedExpression(subexpression: Subexpression(logicalNot: operand.asSubexpression()))
        }
        if matchSymbol("-") {
            let operand = try parseUnary()
            return iTermParsedExpression(subexpression: Subexpression(negated: operand.asSubexpression()))
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> iTermParsedExpression {
        switch peek() {
        case let .number(num, _):
            _ = advance()
            return iTermParsedExpression(subexpression: Subexpression(number: num))
        case let .boolean(flag, _):
            _ = advance()
            return iTermParsedExpression(subexpression: Subexpression(number: NSNumber(value: flag)))
        case let .swiftyString(content, _, _, _, _):
            _ = advance()
            return owner.parsedExpression(withInterpolatedString: content)
        case let .optionalPath(path, _):
            _ = advance()
            let iv = owner.indirectValue(withPath: path, index: nil)
            return owner.parsedExpression(with: iv).optionalized()
        case .symbol("(", _):
            _ = advance()
            let inner = try parseSubexpression()
            try expectSymbol(")")
            return inner
        case .identifier:
            let path = try parsePath()
            if case .symbol("(", _) = peek() {
                let args = try parseArgList()
                return owner.buildFunctionCallParsedExpression(fqName: path, args: args)
            }
            if matchSymbol("[") {
                let indexParsed = try parseSubexpression()
                try expectSymbol("]")
                guard let indexSub = indexParsed.asSubexpression() else {
                    let rawObj: Any? = indexParsed.object
                    let clsName = rawObj.map { NSStringFromClass(type(of: $0 as AnyObject)) } ?? "NSNull"
                    let msg = "Array index for \"\(path)\" must be a number, not \(clsName)"
                    let iv = IndirectValue(error: msg, path: path)
                    return owner.parsedExpression(with: iv)
                }
                let iv = owner.indirectValue(withPath: path, index: indexSub)
                return owner.parsedExpression(with: iv)
            }
            let iv = owner.indirectValue(withPath: path, index: nil)
            return owner.parsedExpression(with: iv)
        default:
            throw syntaxError("expression")
        }
    }

    private mutating func parseCall() throws -> iTermParsedExpression {
        let path = try parsePath()
        let args = try parseArgList()
        return owner.buildFunctionCallParsedExpression(fqName: path, args: args)
    }

    private mutating func parseArgList() throws -> [iTermFunctionArgument] {
        try expectSymbol("(")
        if matchSymbol(")") {
            return []
        }
        var args: [iTermFunctionArgument] = [try parseArg()]
        while matchSymbol(",") {
            args.append(try parseArg())
        }
        try expectSymbol(")")
        return args
    }

    private mutating func parseArg() throws -> iTermFunctionArgument {
        guard case let .identifier(argName, _) = peek() else {
            throw syntaxError("Identifier")
        }
        _ = advance()
        try expectSymbol(":")
        if matchSymbol("&") {
            let path = try parsePath()
            if path == "null" {
                let err = NSError(
                    domain: "com.iterm2.parser",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "&null is never allowed"]
                )
                return owner.newFunctionArgument(
                    withName: argName,
                    expression: iTermParsedExpression(error: err),
                    passByReference: true
                )
            }
            let ref = owner.parsedExpression(withReferenceToPath: path)
            _ = owner.indirectValue(withPath: path, index: nil)
            return owner.newFunctionArgument(withName: argName, expression: ref, passByReference: true)
        }
        let expr = try parseExpression()
        return owner.newFunctionArgument(withName: argName, expression: expr, passByReference: false)
    }

    private mutating func parsePath() throws -> String {
        guard case let .identifier(first, _) = peek() else {
            throw syntaxError("Identifier")
        }
        _ = advance()
        var parts = [first]
        while matchSymbol(".") {
            guard case let .identifier(next, _) = peek() else {
                throw syntaxError("Identifier")
            }
            _ = advance()
            parts.append(next)
        }
        return parts.joined(separator: ".")
    }
}

// MARK: - Suggestion Parser (`iTermFunctionCallSuggester`)

private struct ExpressionSuggestionParser {
    private let tokens: [ExpressionToken]
    private let callBuilder: (String, [String: Any]) -> Any
    private var index = 0

    init(tokens: [ExpressionToken], callBuilder: @escaping (String, [String: Any]) -> Any) {
        self.tokens = tokens
        self.callBuilder = callBuilder
    }

    private func peek(_ delta: Int = 0) -> ExpressionToken {
        let idx = index + delta
        guard idx >= 0 && idx < tokens.count else {
            return tokens.last ?? .eof(offset: 0)
        }
        return tokens[idx]
    }

    @discardableResult
    private mutating func advance() -> ExpressionToken {
        let tok = peek()
        if index < tokens.count - 1 {
            index += 1
        }
        return tok
    }

    private mutating func matchSymbol(_ sym: String) -> Bool {
        if case let .symbol(actual, _) = peek(), actual == sym {
            _ = advance()
            return true
        }
        return false
    }

    private var isAtEOF: Bool {
        if case .eof = peek() { return true }
        return false
    }

    // MARK: Roots

    mutating func parseCallSequenceRoot() -> Any? {
        while true {
            guard let funcName = parseFuncName() else {
                return nil
            }
            if isAtEOF {
                return callBuilder(funcName, ["partial-arglist": true])
            }
            guard let arglist = parseSuggesterArgList() else {
                return nil
            }
            if arglist["partial-arglist"] as? Bool == true {
                return isAtEOF ? callBuilder(funcName, arglist) : nil
            }
            if matchSymbol(";") {
                if isAtEOF {
                    return nil
                }
                continue
            }
            return isAtEOF ? callBuilder(funcName, arglist) : nil
        }
    }

    mutating func parseExpressionRoot() -> Any? {
        guard let result = parseSubexpression(), isAtEOF else {
            return nil
        }
        return result
    }

    // MARK: Calls & Arguments

    private mutating func parseFuncName() -> String? {
        guard case let .identifier(first, _) = peek() else {
            return nil
        }
        _ = advance()
        if matchSymbol(".") {
            guard case let .identifier(second, _) = peek() else {
                return nil
            }
            _ = advance()
            return "\(first).\(second)"
        }
        return first
    }

    private mutating func parseSuggesterArgList() -> [String: Any]? {
        guard matchSymbol("(") else {
            return nil
        }
        if isAtEOF {
            return ["partial-arglist": true, "args": [] as [Any]]
        }
        if matchSymbol(")") {
            return ["complete-arglist": true]
        }

        var items: [Any] = []
        while true {
            guard case let .identifier(argName, _) = peek() else {
                return nil
            }
            _ = advance()
            if isAtEOF {
                items.append(["identifier": argName])
                return ["partial-arglist": true, "args": items]
            }
            guard matchSymbol(":") else {
                return nil
            }
            if isAtEOF {
                items.append(["identifier": argName, "colon": true])
                return ["partial-arglist": true, "args": items]
            }
            let exprDict: [String: Any]
            if matchSymbol("&") {
                guard let refPath = parsePathAllowingTrailingDotAtEOF() else {
                    return nil
                }
                exprDict = ["path": refPath]
            } else {
                guard let parsed = parseSubexpression() else {
                    return nil
                }
                exprDict = parsed
            }
            items.append([
                "identifier": argName,
                "colon": true,
                "expression": exprDict
            ] as [String: Any])

            if isAtEOF {
                return ["partial-arglist": true, "args": items]
            }
            if matchSymbol(",") {
                items.append(",")
                if isAtEOF {
                    return ["partial-arglist": true, "args": items]
                }
                continue
            }
            if matchSymbol(")") {
                return ["complete-arglist": true]
            }
            return nil
        }
    }

    // MARK: Expressions

    private mutating func parseSubexpression() -> [String: Any]? {
        return parseConditional()
    }

    private mutating func parseConditional() -> [String: Any]? {
        guard let lhs = parseLogicalOr() else {
            return nil
        }
        if matchSymbol("?") {
            if isConditionalFollowToken(peek()) {
                return ["terminated": true]
            }
            guard parseConditional() != nil else {
                return nil
            }
            guard matchSymbol(":") else {
                return nil
            }
            if isAtEOF {
                return ["operator_pending": true]
            }
            return parseConditional()
        }
        return lhs
    }

    private func isConditionalFollowToken(_ token: ExpressionToken) -> Bool {
        switch token {
        case .eof:
            return true
        case let .symbol(s, _) where s == ")" || s == "," || s == "]" || s == ":":
            return true
        default:
            return false
        }
    }

    private mutating func parseLogicalOr() -> [String: Any]? {
        guard var current = parseLogicalAnd() else { return nil }
        while matchSymbol("||") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseLogicalAnd() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseLogicalAnd() -> [String: Any]? {
        guard var current = parseEquality() else { return nil }
        while matchSymbol("&&") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseEquality() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseEquality() -> [String: Any]? {
        guard var current = parseRelational() else { return nil }
        while matchSymbol("==") || matchSymbol("!=") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseRelational() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseRelational() -> [String: Any]? {
        guard var current = parseAdditive() else { return nil }
        while matchSymbol("<=") || matchSymbol(">=") || matchSymbol("<") || matchSymbol(">") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseAdditive() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseAdditive() -> [String: Any]? {
        guard var current = parseMultiplicative() else { return nil }
        while matchSymbol("+") || matchSymbol("-") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseMultiplicative() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseMultiplicative() -> [String: Any]? {
        guard var current = parseUnary() else { return nil }
        while matchSymbol("*") || matchSymbol("/") {
            if isAtEOF { return ["operator_pending": true] }
            guard let rhs = parseUnary() else { return nil }
            current = rhs
        }
        return current
    }

    private mutating func parseUnary() -> [String: Any]? {
        if matchSymbol("!") || matchSymbol("-") {
            if isAtEOF { return ["operator_pending": true] }
            return parseUnary()
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> [String: Any]? {
        switch peek() {
        case .number, .boolean:
            _ = advance()
            return ["literal": true]
        case .optionalPath:
            _ = advance()
            return ["terminated": true]
        case let .swiftyString(_, truncated, endsWithLiteral, truncatedPart, _):
            _ = advance()
            if truncated && !endsWithLiteral {
                return ["truncated_interpolation": truncatedPart ?? ""]
            }
            return ["literal": true]
        case .symbol("(", _):
            _ = advance()
            if isAtEOF {
                return ["operator_pending": true]
            }
            guard let inner = parseSubexpression() else {
                return nil
            }
            if matchSymbol(")") || isAtEOF {
                return inner
            }
            return nil
        case .symbol("[", _):
            _ = advance()
            if matchSymbol("]") {
                return ["literal": true]
            }
            if isAtEOF {
                return ["operator_pending": true, "inside-truncated-array-literal": true]
            }
            guard var lastElem = parseSubexpression() else {
                return nil
            }
            while matchSymbol(",") {
                if isAtEOF {
                    return ["operator_pending": true, "inside-truncated-array-literal": true]
                }
                guard let nextElem = parseSubexpression() else {
                    return nil
                }
                lastElem = nextElem
            }
            if matchSymbol("]") {
                return ["literal": true]
            }
            if isAtEOF {
                lastElem["inside-truncated-array-literal"] = true
                return lastElem
            }
            return nil
        case .identifier:
            if isComposedCallStart() {
                guard let fn = parseFuncName(),
                      let arglist = parseSuggesterArgList() else {
                    return nil
                }
                return ["call": callBuilder(fn, arglist)]
            }
            guard let path = parsePathAllowingTrailingDotAtEOF() else {
                return nil
            }
            if matchSymbol("[") {
                if isAtEOF {
                    return ["operator_pending": true]
                }
                guard let sub = parseSubexpression() else {
                    return nil
                }
                if matchSymbol("]") {
                    return ["path": path]
                }
                if isAtEOF {
                    return sub
                }
                return nil
            }
            return ["path": path]
        default:
            return nil
        }
    }

    private func isComposedCallStart() -> Bool {
        guard case .identifier = peek(0) else { return false }
        if case .symbol("(", _) = peek(1) {
            return true
        }
        if case .symbol(".", _) = peek(1),
           case .identifier = peek(2),
           case .symbol("(", _) = peek(3) {
            return true
        }
        return false
    }

    private mutating func parsePathAllowingTrailingDotAtEOF() -> String? {
        guard case let .identifier(first, _) = peek() else {
            return nil
        }
        _ = advance()
        var path = first
        while matchSymbol(".") {
            if isAtEOF {
                return path + "."
            }
            guard case let .identifier(seg, _) = peek() else {
                return nil
            }
            _ = advance()
            path += ".\(seg)"
        }
        return path
    }
}
