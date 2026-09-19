import XCTest
@testable import iTerm2SharedARC

final class ProfileSearchTokenTests: XCTestCase {
    func testOperatorsAndNegationKeepTheirExistingRouting() {
        let tag = iTermProfileSearchToken(phrase: "-tag:prod")
        XCTAssertTrue(tag.negated)
        XCTAssertTrue(tag.isTag)
        XCTAssertEqual(tag.operator, "tag:")
        XCTAssertFalse(tag.matchesAnyWord(inNameWords: ["production"]))
        XCTAssertTrue(tag.matchesAnyWord(inTagWords: ["production"]))
        XCTAssertFalse(tag.matchesAnyWord(in: ["production"], operator: "name:"))
        XCTAssertTrue(tag.matchesAnyWord(in: ["production"], operator: "tag:"))

        let command = iTermProfileSearchToken(phrase: "command:ssh")
        XCTAssertFalse(command.isTag)
        XCTAssertTrue(command.matchesAnyWord(inNameWords: ["ssh"]))
        XCTAssertFalse(command.matchesAnyWord(inTagWords: ["ssh"]))
    }

    func testCustomOperatorsRespectOrderAndUnknownPrefixesStayLiteral() {
        let token = iTermProfileSearchToken(phrase: "text:hello", operators: ["tag:", "text:"])
        XCTAssertTrue(token.matchesAnyWord(inNameWords: ["HELLO"]))
        XCTAssertFalse(token.matchesAnyWord(inTagWords: ["HELLO"]))
        XCTAssertFalse(token.matchesAnyWord(in: ["hello"], operator: "name:"))
        XCTAssertTrue(token.matchesAnyWord(in: ["hello"], operator: "text:"))

        let unknown = iTermProfileSearchToken(phrase: "text:hello")
        XCTAssertNil(unknown.operator)
        XCTAssertFalse(unknown.matchesAnyWord(inNameWords: ["hello"]))
        XCTAssertTrue(unknown.matchesAnyWord(inNameWords: ["text:hello"]))
        let overlap = iTermProfileSearchToken(phrase: "name:foo", operators: ["name", "name:"])
        XCTAssertEqual(overlap.operator, "name")
        XCTAssertTrue(overlap.matchesAnyWord(inNameWords: [":foo"]))
    }

    func testAnchorsAndLegacyWildcard() {
        XCTAssertTrue(iTermProfileSearchToken(phrase: "*foo").matchesAnyWord(inNameWords: ["xFOOx"]))
        XCTAssertFalse(iTermProfileSearchToken(phrase: "^foo").matchesAnyWord(inNameWords: ["xfoo"]))
        XCTAssertTrue(iTermProfileSearchToken(phrase: "foo$").matchesAnyWord(inNameWords: ["xfoo"]))
        XCTAssertTrue(iTermProfileSearchToken(phrase: "^foo$").matchesAnyWord(inNameWords: ["foo"]))
        XCTAssertFalse(iTermProfileSearchToken(phrase: "^foo$").matchesAnyWord(inNameWords: ["foobar"]))
        // The existing suffix check tests the first substring match only.
        XCTAssertFalse(iTermProfileSearchToken(phrase: "foo$").matchesAnyWord(inNameWords: ["foofoo"]))
    }

    func testWholePhraseQuotesAndEmbeddedQuotesKeepLegacySemantics() {
        let phrase = iTermProfileSearchToken(phrase: "\"two words\"")
        XCTAssertTrue(phrase.matchesAnyWord(inNameWords: ["prefix", "two", "words"]))
        XCTAssertEqual(phrase.range, NSRange(location: 7, length: 9))
        let restricted = iTermProfileSearchToken(phrase: "name:\"two words\"")
        XCTAssertFalse(restricted.matchesAnyWord(inNameWords: ["two", "words"]))
        XCTAssertTrue(restricted.matchesAnyWord(inNameWords: ["\"two", "words\""]))
    }

    func testEmptyQueriesAndNilNames() {
        for phrase in ["", "^$", "\"\"", "*", "-"] {
            let token = iTermProfileSearchToken(phrase: phrase)
            XCTAssertTrue(token.matchesAnyWord(inNameWords: nil), phrase)
            XCTAssertTrue(token.matchesAnyWord(inTagWords: []), phrase)
            XCTAssertTrue(token.matchesAnyWord(inTagWords: nil), phrase)
            XCTAssertTrue(token.matchesAnyWord(in: nil, operator: "name:"), phrase)
            XCTAssertEqual(token.range, NSRange(location: 0, length: 0))
        }
        XCTAssertFalse(iTermProfileSearchToken(phrase: "foo").matchesAnyWord(inNameWords: nil))
        XCTAssertFalse(iTermProfileSearchToken(phrase: "command:ssh").matchesAnyWord(in: nil, operator: "command:"))
    }

    func testUTF16HighlightOffsetsAndRepeatedSpaces() {
        let token = iTermProfileSearchToken(phrase: "CAFÉ")
        XCTAssertTrue(token.matchesAnyWord(inNameWords: ["😀", "Xcafé"]))
        XCTAssertEqual(token.range, NSRange(location: 4, length: 4))
        let emoji = iTermProfileSearchToken(phrase: "👩‍💻")
        XCTAssertTrue(emoji.matchesAnyWord(inNameWords: ["aa", "👩‍💻"]))
        XCTAssertEqual(emoji.range, NSRange(location: 3, length: 5))
        let spaced = iTermProfileSearchToken(phrase: "two  words")
        XCTAssertFalse(spaced.matchesAnyWord(inNameWords: ["two", "words"]))
        XCTAssertTrue(spaced.matchesAnyWord(inNameWords: ["two", "", "words"]))
        XCTAssertEqual(spaced.range, NSRange(location: 0, length: 10))
    }

    func testRangeStateAfterRejectedMatches() {
        let token = iTermProfileSearchToken(phrase: "name:two words")
        XCTAssertTrue(token.matchesAnyWord(inNameWords: ["x", "two", "words"]))
        let matchedRange = token.range
        XCTAssertFalse(token.matchesAnyWord(inNameWords: ["short"]))
        XCTAssertEqual(token.range, matchedRange)
        XCTAssertFalse(token.matchesAnyWord(inTagWords: ["two", "words"]))
        XCTAssertEqual(token.range, matchedRange)
        XCTAssertFalse(token.matchesAnyWord(inNameWords: ["other", "text"]))
        XCTAssertEqual(token.range.location, NSNotFound)
        XCTAssertEqual(token.range.length, 0)
    }

    func testTagInitializerTreatsSyntaxAsLiteralText() {
        let token = iTermProfileSearchToken(tag: "-^prod$", operators: ["tag:", "text:"])
        XCTAssertFalse(token.negated)
        XCTAssertTrue(token.isTag)
        XCTAssertFalse(token.matchesAnyWord(inNameWords: ["-^prod$"]))
        XCTAssertFalse(token.matchesAnyWord(inTagWords: ["prod"]))
        XCTAssertTrue(token.matchesAnyWord(inTagWords: ["prefix-^prod$suffix"]))
    }

    func testSearchEngineCombinesTagsNegationAndDisjunction() {
        let query = ProfileStyleSearchEngineQuery(query: "name:^prod|name:^stage -tag:old",
                                                  operators: ["name:", "tag:"])
        let engine = ProfileStyleSearchEngine(query: query)
        let result = engine.search(document: .init(phrases: ["name:": "stage server"], tags: ["current"]))
        XCTAssertEqual(result?.phraseIndexes["name:"], IndexSet(integersIn: 0..<5))
        XCTAssertNil(engine.search(document: .init(phrases: ["name:": "prod server"], tags: ["old"])))
        XCTAssertNil(engine.search(document: .init(phrases: ["name:": "dev server"], tags: ["current"])))
    }

    func testObjectiveCRuntimeContract() {
        XCTAssertTrue(NSClassFromString("iTermProfileSearchToken") === iTermProfileSearchToken.self)
        let token = iTermProfileSearchToken(phrase: "-name:foo")
        for selector in ["initWithPhrase:", "initWithPhrase:operators:", "initWithTag:", "initWithTag:operators:",
                         "matchesAnyWordIn:operator:", "matchesAnyWordInNameWords:", "matchesAnyWordInTagWords:"] {
            XCTAssertTrue(token.responds(to: NSSelectorFromString(selector)), selector)
        }
        XCTAssertEqual(token.value(forKey: "operator") as? String, "name:")
        XCTAssertEqual(token.value(forKey: "negated") as? Bool, true)
    }
}
