//
//  TOMLCodec.swift
//  Latterm
//

import Foundation

enum TOMLError: LocalizedError, Equatable {
    case syntaxError(line: Int, column: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .syntaxError(line, column, message):
            return String(
                format: NSLocalizedString("TOML syntax error at line %d, column %d: %@",
                                          comment: "Declarative config TOML syntax error"),
                line,
                column,
                message
            )
        }
    }
}

struct TOMLTable: Equatable {
    private(set) var keys: [String] = []
    private var storage: [String: TOMLValue] = [:]

    init() {}

    init(_ pairs: [(String, TOMLValue)]) {
        for (key, value) in pairs {
            self[key] = value
        }
    }

    var isEmpty: Bool {
        storage.isEmpty
    }

    var count: Int {
        storage.count
    }

    func contains(_ key: String) -> Bool {
        storage[key] != nil
    }

    subscript(key: String) -> TOMLValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil {
                    keys.append(key)
                }
                storage[key] = newValue
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    func string(_ key: String) -> String? {
        guard case let .string(value)? = storage[key] else { return nil }
        return value
    }

    func int(_ key: String) -> Int? {
        switch storage[key] {
        case let .integer(value)?:
            return Int(exactly: value)
        case let .float(value)? where value.isFinite && value.rounded() == value:
            return Int(exactly: value)
        default:
            return nil
        }
    }

    func int64(_ key: String) -> Int64? {
        guard case let .integer(value)? = storage[key] else { return nil }
        return value
    }

    func double(_ key: String) -> Double? {
        switch storage[key] {
        case let .float(value)?:
            return value
        case let .integer(value)?:
            return Double(value)
        default:
            return nil
        }
    }

    func bool(_ key: String) -> Bool? {
        guard case let .boolean(value)? = storage[key] else { return nil }
        return value
    }

    func table(_ key: String) -> TOMLTable? {
        guard case let .table(value)? = storage[key] else { return nil }
        return value
    }

    func array(_ key: String) -> [TOMLValue]? {
        guard case let .array(value)? = storage[key] else { return nil }
        return value
    }

    func tableArray(_ key: String) -> [TOMLTable]? {
        guard case let .array(items)? = storage[key] else { return nil }
        var tables: [TOMLTable] = []
        tables.reserveCapacity(items.count)
        for item in items {
            guard case let .table(table) = item else { return nil }
            tables.append(table)
        }
        return tables
    }

    func stringArray(_ key: String) -> [String]? {
        guard case let .array(items)? = storage[key] else { return nil }
        var strings: [String] = []
        strings.reserveCapacity(items.count)
        for item in items {
            guard case let .string(str) = item else { return nil }
            strings.append(str)
        }
        return strings
    }
}

enum TOMLValue: Equatable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    static func == (lhs: TOMLValue, rhs: TOMLValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)):
            return a == b
        case let (.integer(a), .integer(b)):
            return a == b
        case let (.float(a), .float(b)):
            if a.isNaN && b.isNaN { return true }
            return a == b
        case let (.boolean(a), .boolean(b)):
            return a == b
        case let (.array(a), .array(b)):
            return a == b
        case let (.table(a), .table(b)):
            return a == b
        default:
            return false
        }
    }
}

enum TOMLCodec {
    static func parse(_ source: String) throws -> TOMLTable {
        var parser = TOMLParser(source: source)
        return try parser.parseDocument()
    }

    static func encode(_ root: TOMLTable, headerComment: String? = nil) -> String {
        var lines: [String] = []
        if let headerComment, !headerComment.isEmpty {
            for commentLine in headerComment.components(separatedBy: "\n") {
                if commentLine.isEmpty {
                    lines.append("#")
                } else if commentLine.hasPrefix("#") {
                    lines.append(commentLine)
                } else {
                    lines.append("# \(commentLine)")
                }
            }
            lines.append("")
        }
        emitTableBody(root, path: [], into: &lines, emitHeader: false)
        while lines.last == "" {
            lines.removeLast()
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Deterministic Encoder

    private static func emitTableBody(_ table: TOMLTable,
                                      path: [String],
                                      into lines: inout [String],
                                      emitHeader: Bool) {
        var scalarPairs: [(String, TOMLValue)] = []
        var subtables: [(String, TOMLTable)] = []
        var tableArrays: [(String, [TOMLTable])] = []

        for key in table.keys {
            guard let value = table[key] else { continue }
            switch value {
            case let .table(subtable):
                subtables.append((key, subtable))
            case let .array(items) where !items.isEmpty && items.allSatisfy({
                if case .table = $0 { return true }
                return false
            }):
                let extracted: [TOMLTable] = items.compactMap {
                    if case let .table(t) = $0 { return t }
                    return nil
                }
                tableArrays.append((key, extracted))
            default:
                scalarPairs.append((key, value))
            }
        }

        if emitHeader && (!scalarPairs.isEmpty || (subtables.isEmpty && tableArrays.isEmpty)) {
            if !lines.isEmpty && lines.last != "" {
                lines.append("")
            }
            lines.append("[\(formatPath(path))]")
        }

        for (key, value) in scalarPairs {
            lines.append("\(formatKey(key)) = \(formatInlineValue(value))")
        }

        for (key, subtable) in subtables {
            emitTableBody(subtable, path: path + [key], into: &lines, emitHeader: true)
        }

        for (key, arrayTables) in tableArrays {
            let childPath = path + [key]
            for element in arrayTables {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                lines.append("[[\(formatPath(childPath))]]")
                emitTableBody(element, path: childPath, into: &lines, emitHeader: false)
            }
        }
    }

    static func formatKey(_ key: String) -> String {
        if !key.isEmpty && key.unicodeScalars.allSatisfy({ isBareKeyScalar($0) }) {
            return key
        }
        return formatBasicString(key)
    }

    private static func formatPath(_ path: [String]) -> String {
        path.map { formatKey($0) }.joined(separator: ".")
    }

    static func formatInlineValue(_ value: TOMLValue) -> String {
        switch value {
        case let .string(str):
            return formatBasicString(str)
        case let .integer(num):
            return String(num)
        case let .float(num):
            if num.isNaN { return "nan" }
            if num == .infinity { return "inf" }
            if num == -.infinity { return "-inf" }
            let formatted = String(num)
            if formatted.contains(".") || formatted.contains("e") || formatted.contains("E") {
                return formatted
            }
            return "\(formatted).0"
        case let .boolean(flag):
            return flag ? "true" : "false"
        case let .array(items):
            if items.isEmpty {
                return "[]"
            }
            if items.count > 6 && items.allSatisfy({
                if case .string = $0 { return true }
                return false
            }) {
                var rows: [String] = []
                var chunk: [String] = []
                for item in items {
                    chunk.append(formatInlineValue(item))
                    if chunk.count == 8 {
                        rows.append("  " + chunk.joined(separator: ", ") + ",")
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty {
                    rows.append("  " + chunk.joined(separator: ", "))
                }
                return "[\n" + rows.joined(separator: "\n") + "\n]"
            }
            return "[" + items.map { formatInlineValue($0) }.joined(separator: ", ") + "]"
        case let .table(table):
            if table.isEmpty {
                return "{}"
            }
            let body = table.keys.compactMap { key -> String? in
                guard let v = table[key] else { return nil }
                return "\(formatKey(key)) = \(formatInlineValue(v))"
            }.joined(separator: ", ")
            return "{ \(body) }"
        }
    }

    static func formatBasicString(_ string: String) -> String {
        var result = "\""
        result.reserveCapacity(string.count + 2)
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x08: result.append("\\b")
            case 0x09: result.append("\\t")
            case 0x0A: result.append("\\n")
            case 0x0C: result.append("\\f")
            case 0x0D: result.append("\\r")
            case 0x22: result.append("\\\"")
            case 0x5C: result.append("\\\\")
            case 0x00...0x1F, 0x7F:
                result.append(String(format: "\\u%04X", scalar.value))
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result.append("\"")
        return result
    }

    fileprivate static func isBareKeyScalar(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (v >= 0x41 && v <= 0x5A) // A-Z
            || (v >= 0x61 && v <= 0x7A) // a-z
            || (v >= 0x30 && v <= 0x39) // 0-9
            || v == 0x5F                // _
            || v == 0x2D                // -
    }
}

// MARK: - Parser

private final class TOMLBoxNode {
    enum Kind {
        case table
        case arrayOfTables([TOMLBoxNode])
        case scalar(TOMLValue)
    }

    var kind: Kind
    var keys: [String] = []
    var children: [String: TOMLBoxNode] = [:]
    var isExplicitlyDefinedTable = false
    var isInlineClosed = false

    init(kind: Kind) {
        self.kind = kind
    }

    func setChild(_ node: TOMLBoxNode, for key: String) {
        if children[key] == nil {
            keys.append(key)
        }
        children[key] = node
    }

    func toTOMLValue() -> TOMLValue {
        switch kind {
        case let .scalar(value):
            return value
        case let .arrayOfTables(elements):
            return .array(elements.map { $0.toTOMLValue() })
        case .table:
            var table = TOMLTable()
            for key in keys {
                if let child = children[key] {
                    table[key] = child.toTOMLValue()
                }
            }
            return .table(table)
        }
    }
}

private struct TOMLParser {
    private let scalars: [UnicodeScalar]
    private var index: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    init(source: String) {
        var loaded = Array(source.unicodeScalars)
        if loaded.first?.value == 0xFEFF {
            loaded.removeFirst()
        }
        self.scalars = loaded
    }

    private var isAtEnd: Bool {
        index >= scalars.count
    }

    private func peek(_ offset: Int = 0) -> UnicodeScalar? {
        let pos = index + offset
        guard pos >= 0 && pos < scalars.count else { return nil }
        return scalars[pos]
    }

    @discardableResult
    private mutating func advance() -> UnicodeScalar? {
        guard index < scalars.count else { return nil }
        let s = scalars[index]
        index += 1
        if s.value == 0x0A {
            line += 1
            column = 1
        } else {
            column += 1
        }
        return s
    }

    private func fail(_ message: String, at customLoc: (Int, Int)? = nil) -> TOMLError {
        let loc = customLoc ?? (line, column)
        return .syntaxError(line: loc.0, column: loc.1, message: message)
    }

    mutating func parseDocument() throws -> TOMLTable {
        let root = TOMLBoxNode(kind: .table)
        var currentTable = root

        while !isAtEnd {
            skipWhitespaceAndComments(allowNewlines: true)
            if isAtEnd { break }

            if peek() == "[" {
                let headerLoc = (line, column)
                if peek(1) == "[" {
                    _ = advance()
                    _ = advance()
                    let path = try parseKeyPath()
                    skipInlineSpace()
                    guard peek() == "]" && peek(1) == "]" else {
                        throw fail("Expected closing ']]' for array of tables header")
                    }
                    _ = advance()
                    _ = advance()
                    try consumeEndOfStatement()
                    currentTable = try openArrayOfTables(root: root, path: path, loc: headerLoc)
                } else {
                    _ = advance()
                    let path = try parseKeyPath()
                    skipInlineSpace()
                    guard peek() == "]" else {
                        throw fail("Expected closing ']' for table header")
                    }
                    _ = advance()
                    try consumeEndOfStatement()
                    currentTable = try openStandardTable(root: root, path: path, loc: headerLoc)
                }
            } else {
                let keyLoc = (line, column)
                let keyPath = try parseKeyPath()
                skipInlineSpace()
                guard peek() == "=" else {
                    throw fail("Expected '=' after key")
                }
                _ = advance()
                skipInlineSpace()
                let value = try parseValue()
                try consumeEndOfStatement()
                try assignValue(value, at: keyPath, into: currentTable, loc: keyLoc)
            }
        }

        guard case let .table(result) = root.toTOMLValue() else {
            it_fatalError("Root TOML node must convert to TOMLTable")
        }
        return result
    }

    // MARK: - Tree Construction

    private func openStandardTable(root: TOMLBoxNode, path: [String], loc: (Int, Int)) throws -> TOMLBoxNode {
        it_assert(!path.isEmpty, "Key path cannot be empty")
        var cursor = root
        for idx in 0..<(path.count - 1) {
            let segment = path[idx]
            if let existing = cursor.children[segment] {
                if existing.isInlineClosed {
                    throw fail("Cannot extend inline table '\(segment)'", at: loc)
                }
                switch existing.kind {
                case .table:
                    cursor = existing
                case let .arrayOfTables(items):
                    guard let last = items.last else {
                        throw fail("Empty array of tables '\(segment)'", at: loc)
                    }
                    cursor = last
                case .scalar:
                    throw fail("Cannot redefine scalar key '\(segment)' as table", at: loc)
                }
            } else {
                let created = TOMLBoxNode(kind: .table)
                cursor.setChild(created, for: segment)
                cursor = created
            }
        }

        let leaf = path[path.count - 1]
        if let existing = cursor.children[leaf] {
            if existing.isInlineClosed {
                throw fail("Cannot reopen inline table '\(leaf)'", at: loc)
            }
            guard case .table = existing.kind else {
                throw fail("Cannot redefine '\(leaf)' as standard table", at: loc)
            }
            if existing.isExplicitlyDefinedTable {
                throw fail("Duplicate table header '[\(path.joined(separator: "."))]'", at: loc)
            }
            existing.isExplicitlyDefinedTable = true
            return existing
        } else {
            let created = TOMLBoxNode(kind: .table)
            created.isExplicitlyDefinedTable = true
            cursor.setChild(created, for: leaf)
            return created
        }
    }

    private func openArrayOfTables(root: TOMLBoxNode, path: [String], loc: (Int, Int)) throws -> TOMLBoxNode {
        it_assert(!path.isEmpty, "Key path cannot be empty")
        var cursor = root
        for idx in 0..<(path.count - 1) {
            let segment = path[idx]
            if let existing = cursor.children[segment] {
                if existing.isInlineClosed {
                    throw fail("Cannot extend inline table '\(segment)'", at: loc)
                }
                switch existing.kind {
                case .table:
                    cursor = existing
                case let .arrayOfTables(items):
                    guard let last = items.last else {
                        throw fail("Empty array of tables '\(segment)'", at: loc)
                    }
                    cursor = last
                case .scalar:
                    throw fail("Cannot redefine scalar key '\(segment)' as table", at: loc)
                }
            } else {
                let created = TOMLBoxNode(kind: .table)
                cursor.setChild(created, for: segment)
                cursor = created
            }
        }

        let leaf = path[path.count - 1]
        let newElement = TOMLBoxNode(kind: .table)
        newElement.isExplicitlyDefinedTable = true

        if let existing = cursor.children[leaf] {
            guard case var .arrayOfTables(items) = existing.kind, !existing.isInlineClosed else {
                throw fail("Cannot redefine '\(leaf)' as array of tables", at: loc)
            }
            items.append(newElement)
            existing.kind = .arrayOfTables(items)
        } else {
            let arrayNode = TOMLBoxNode(kind: .arrayOfTables([newElement]))
            cursor.setChild(arrayNode, for: leaf)
        }
        return newElement
    }

    private func assignValue(_ value: TOMLValue,
                             at path: [String],
                             into base: TOMLBoxNode,
                             loc: (Int, Int)) throws {
        it_assert(!path.isEmpty, "Key path cannot be empty")
        var cursor = base
        for idx in 0..<(path.count - 1) {
            let segment = path[idx]
            if let existing = cursor.children[segment] {
                if existing.isInlineClosed {
                    throw fail("Cannot modify inline table '\(segment)'", at: loc)
                }
                guard case .table = existing.kind else {
                    throw fail("Key '\(segment)' is not a table", at: loc)
                }
                cursor = existing
            } else {
                let created = TOMLBoxNode(kind: .table)
                cursor.setChild(created, for: segment)
                cursor = created
            }
        }

        let leaf = path[path.count - 1]
        if cursor.children[leaf] != nil {
            throw fail("Duplicate key '\(leaf)'", at: loc)
        }

        let leafNode = makeClosedNode(from: value)
        cursor.setChild(leafNode, for: leaf)
    }

    private func makeClosedNode(from value: TOMLValue) -> TOMLBoxNode {
        switch value {
        case let .table(table):
            let node = TOMLBoxNode(kind: .table)
            node.isInlineClosed = true
            for key in table.keys {
                if let v = table[key] {
                    node.setChild(makeClosedNode(from: v), for: key)
                }
            }
            return node
        default:
            let node = TOMLBoxNode(kind: .scalar(value))
            node.isInlineClosed = true
            return node
        }
    }

    // MARK: - Whitespace & Comments

    private mutating func skipInlineSpace() {
        while let s = peek(), s.value == 0x20 || s.value == 0x09 {
            _ = advance()
        }
    }

    private mutating func skipComment() {
        guard peek() == "#" else { return }
        while let s = peek(), s.value != 0x0A && s.value != 0x0D {
            _ = advance()
        }
    }

    private mutating func skipWhitespaceAndComments(allowNewlines: Bool) {
        while let s = peek() {
            if s.value == 0x20 || s.value == 0x09 {
                _ = advance()
            } else if allowNewlines && (s.value == 0x0A || s.value == 0x0D) {
                if s.value == 0x0D && peek(1)?.value == 0x0A {
                    _ = advance()
                }
                _ = advance()
            } else if s == "#" {
                skipComment()
            } else {
                break
            }
        }
    }

    private mutating func consumeEndOfStatement() throws {
        skipInlineSpace()
        if peek() == "#" {
            skipComment()
        }
        if isAtEnd { return }
        if let s = peek(), s.value == 0x0D || s.value == 0x0A {
            if s.value == 0x0D {
                _ = advance()
                guard peek()?.value == 0x0A else {
                    throw fail("Bare carriage return without newline")
                }
            }
            _ = advance()
            return
        }
        throw fail("Unexpected trailing token on line")
    }

    // MARK: - Keys

    private mutating func parseKeyPath() throws -> [String] {
        var parts: [String] = []
        skipInlineSpace()
        parts.append(try parseSimpleKey())
        skipInlineSpace()
        while peek() == "." {
            _ = advance()
            skipInlineSpace()
            parts.append(try parseSimpleKey())
            skipInlineSpace()
        }
        return parts
    }

    private mutating func parseSimpleKey() throws -> String {
        guard let next = peek() else {
            throw fail("Expected key, found end of file")
        }
        if next == "\"" {
            if peek(1) == "\"" && peek(2) == "\"" {
                throw fail("Multi-line strings cannot be used as keys")
            }
            return try parseBasicString()
        }
        if next == "'" {
            if peek(1) == "'" && peek(2) == "'" {
                throw fail("Multi-line strings cannot be used as keys")
            }
            return try parseLiteralString()
        }
        var key = ""
        while let s = peek(), TOMLCodec.isBareKeyScalar(s) {
            key.unicodeScalars.append(s)
            _ = advance()
        }
        if key.isEmpty {
            throw fail("Expected bare or quoted key")
        }
        return key
    }

    // MARK: - Values

    private mutating func parseValue() throws -> TOMLValue {
        guard let next = peek() else {
            throw fail("Expected value, found end of file")
        }
        if next == "\"" {
            if peek(1) == "\"" && peek(2) == "\"" {
                return .string(try parseMultilineBasicString())
            }
            return .string(try parseBasicString())
        }
        if next == "'" {
            if peek(1) == "'" && peek(2) == "'" {
                return .string(try parseMultilineLiteralString())
            }
            return .string(try parseLiteralString())
        }
        if next == "[" {
            return .array(try parseArray())
        }
        if next == "{" {
            return .table(try parseInlineTable())
        }
        return try parseLiteralScalar()
    }

    private mutating func parseBasicString() throws -> String {
        let startLoc = (line, column)
        _ = advance() // opening "
        var out = ""
        while let s = peek() {
            if s == "\"" {
                _ = advance()
                return out
            }
            if s.value == 0x0A || s.value == 0x0D {
                throw fail("Unterminated string literal", at: startLoc)
            }
            if s == "\\" {
                _ = advance()
                out.unicodeScalars.append(try parseEscapeSequence())
            } else {
                out.unicodeScalars.append(s)
                _ = advance()
            }
        }
        throw fail("Unterminated string literal", at: startLoc)
    }

    private mutating func parseMultilineBasicString() throws -> String {
        let startLoc = (line, column)
        _ = advance(); _ = advance(); _ = advance() // """
        if peek()?.value == 0x0D && peek(1)?.value == 0x0A {
            _ = advance(); _ = advance()
        } else if peek()?.value == 0x0A {
            _ = advance()
        }
        var out = ""
        while !isAtEnd {
            if peek() == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                _ = advance(); _ = advance(); _ = advance()
                // Up to two extra quotes allowed inside closing delimiter ("""" or """"")
                while peek() == "\"" && out.count < Int.max {
                    if peek(1) == "\"" && peek(2) == "\"" {
                        break
                    }
                    out.append("\"")
                    _ = advance()
                }
                return out
            }
            guard let s = peek() else { break }
            if s == "\\" {
                _ = advance()
                // Line-ending backslash trims following whitespace + newlines
                if let after = peek(), after.value == 0x20 || after.value == 0x09 || after.value == 0x0D || after.value == 0x0A {
                    var sawNewline = false
                    var lookahead = 0
                    while let p = peek(lookahead) {
                        if p.value == 0x20 || p.value == 0x09 {
                            lookahead += 1
                        } else if p.value == 0x0D || p.value == 0x0A {
                            sawNewline = true
                            break
                        } else {
                            break
                        }
                    }
                    if sawNewline {
                        while let p = peek(), p.value == 0x20 || p.value == 0x09 || p.value == 0x0D || p.value == 0x0A {
                            _ = advance()
                        }
                        continue
                    }
                }
                out.unicodeScalars.append(try parseEscapeSequence())
            } else if s.value == 0x0D && peek(1)?.value == 0x0A {
                _ = advance(); _ = advance()
                out.append("\n")
            } else {
                out.unicodeScalars.append(s)
                _ = advance()
            }
        }
        throw fail("Unterminated multi-line basic string", at: startLoc)
    }

    private mutating func parseEscapeSequence() throws -> UnicodeScalar {
        guard let esc = advance() else {
            throw fail("Unexpected end of file in string escape")
        }
        switch esc {
        case "b": return UnicodeScalar(0x08)
        case "t": return UnicodeScalar(0x09)
        case "n": return UnicodeScalar(0x0A)
        case "f": return UnicodeScalar(0x0C)
        case "r": return UnicodeScalar(0x0D)
        case "e": return UnicodeScalar(0x1B)
        case "\"": return UnicodeScalar(0x22)
        case "\\": return UnicodeScalar(0x5C)
        case "u":
            return try parseUnicodeHex(digits: 4)
        case "U":
            return try parseUnicodeHex(digits: 8)
        default:
            throw fail("Invalid escape sequence '\\\(esc)'")
        }
    }

    private mutating func parseUnicodeHex(digits: Int) throws -> UnicodeScalar {
        var hex = ""
        for _ in 0..<digits {
            guard let c = advance() else {
                throw fail("Incomplete unicode escape sequence")
            }
            hex.unicodeScalars.append(c)
        }
        guard let codePoint = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(codePoint) else {
            throw fail("Invalid unicode scalar '\\u\(hex)'")
        }
        return scalar
    }

    private mutating func parseLiteralString() throws -> String {
        let startLoc = (line, column)
        _ = advance() // '
        var out = ""
        while let s = peek() {
            if s == "'" {
                _ = advance()
                return out
            }
            if s.value == 0x0A || s.value == 0x0D {
                throw fail("Unterminated literal string", at: startLoc)
            }
            out.unicodeScalars.append(s)
            _ = advance()
        }
        throw fail("Unterminated literal string", at: startLoc)
    }

    private mutating func parseMultilineLiteralString() throws -> String {
        let startLoc = (line, column)
        _ = advance(); _ = advance(); _ = advance() // '''
        if peek()?.value == 0x0D && peek(1)?.value == 0x0A {
            _ = advance(); _ = advance()
        } else if peek()?.value == 0x0A {
            _ = advance()
        }
        var out = ""
        while !isAtEnd {
            if peek() == "'" && peek(1) == "'" && peek(2) == "'" {
                _ = advance(); _ = advance(); _ = advance()
                return out
            }
            guard let s = peek() else { break }
            if s.value == 0x0D && peek(1)?.value == 0x0A {
                _ = advance(); _ = advance()
                out.append("\n")
            } else {
                out.unicodeScalars.append(s)
                _ = advance()
            }
        }
        throw fail("Unterminated multi-line literal string", at: startLoc)
    }

    private mutating func parseArray() throws -> [TOMLValue] {
        let startLoc = (line, column)
        _ = advance() // [
        var items: [TOMLValue] = []
        while true {
            skipWhitespaceAndComments(allowNewlines: true)
            if peek() == "]" {
                _ = advance()
                return items
            }
            if isAtEnd {
                throw fail("Unterminated array", at: startLoc)
            }
            items.append(try parseValue())
            skipWhitespaceAndComments(allowNewlines: true)
            if peek() == "," {
                _ = advance()
                continue
            }
            if peek() == "]" {
                _ = advance()
                return items
            }
            throw fail("Expected ',' or ']' in array")
        }
    }

    private mutating func parseInlineTable() throws -> TOMLTable {
        let startLoc = (line, column)
        _ = advance() // {
        let node = TOMLBoxNode(kind: .table)
        while true {
            skipWhitespaceAndComments(allowNewlines: true)
            if peek() == "}" {
                _ = advance()
                guard case let .table(result) = node.toTOMLValue() else {
                    it_fatalError("Inline table node must produce TOMLTable")
                }
                return result
            }
            if isAtEnd {
                throw fail("Unterminated inline table", at: startLoc)
            }
            let keyLoc = (line, column)
            let keyPath = try parseKeyPath()
            skipWhitespaceAndComments(allowNewlines: true)
            guard peek() == "=" else {
                throw fail("Expected '=' in inline table")
            }
            _ = advance()
            skipWhitespaceAndComments(allowNewlines: true)
            let val = try parseValue()
            try assignValue(val, at: keyPath, into: node, loc: keyLoc)
            skipWhitespaceAndComments(allowNewlines: true)
            if peek() == "," {
                _ = advance()
                continue
            }
            if peek() == "}" {
                _ = advance()
                guard case let .table(result) = node.toTOMLValue() else {
                    it_fatalError("Inline table node must produce TOMLTable")
                }
                return result
            }
            throw fail("Expected ',' or '}' in inline table")
        }
    }

    private mutating func parseLiteralScalar() throws -> TOMLValue {
        let loc = (line, column)
        var token = ""
        while let s = peek() {
            if s.value == 0x20 || s.value == 0x09 || s.value == 0x0A || s.value == 0x0D
                || s == "#" || s == "," || s == "]" || s == "}" {
                break
            }
            token.unicodeScalars.append(s)
            _ = advance()
        }
        if token.isEmpty {
            throw fail("Expected value", at: loc)
        }
        if token == "true" { return .boolean(true) }
        if token == "false" { return .boolean(false) }
        if token == "inf" || token == "+inf" { return .float(.infinity) }
        if token == "-inf" { return .float(-.infinity) }
        if token == "nan" || token == "+nan" || token == "-nan" { return .float(.nan) }

        let cleaned = try sanitizeNumericToken(token, loc: loc)
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            guard let v = Int64(String(cleaned.dropFirst(2)), radix: 16) else {
                throw fail("Invalid hexadecimal integer '\(token)'", at: loc)
            }
            return .integer(v)
        }
        if cleaned.hasPrefix("0o") || cleaned.hasPrefix("0O") {
            guard let v = Int64(String(cleaned.dropFirst(2)), radix: 8) else {
                throw fail("Invalid octal integer '\(token)'", at: loc)
            }
            return .integer(v)
        }
        if cleaned.hasPrefix("0b") || cleaned.hasPrefix("0B") {
            guard let v = Int64(String(cleaned.dropFirst(2)), radix: 2) else {
                throw fail("Invalid binary integer '\(token)'", at: loc)
            }
            return .integer(v)
        }
        if cleaned.contains(".") || cleaned.contains("e") || cleaned.contains("E") {
            guard let d = Double(cleaned) else {
                throw fail("Invalid floating-point number '\(token)'", at: loc)
            }
            return .float(d)
        }
        guard let i = Int64(cleaned, radix: 10) else {
            throw fail("Invalid value '\(token)'", at: loc)
        }
        return .integer(i)
    }

    private func sanitizeNumericToken(_ raw: String, loc: (Int, Int)) throws -> String {
        if raw.first == "_" || raw.last == "_" || raw.contains("__") {
            throw fail("Invalid underscore placement in number '\(raw)'", at: loc)
        }
        return raw.replacingOccurrences(of: "_", with: "")
    }
}
