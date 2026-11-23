import XCTest
@testable import iTerm2SharedARC

final class MinimumSubsequenceMatcherTests: XCTestCase {
    func testChoosesShortestMatchAndBreaksTiesByStart() {
        let matcher = MinimumSubsequenceMatcher(query: "AB")
        XCTAssertEqual(matcher.indexSet(for: "axb ab ab"), IndexSet(4...5))
        XCTAssertEqual(matcher.indexSet(for: "axb axb"), IndexSet([0, 2]))
    }

    func testRepeatedLettersAndUTF16Offsets() {
        let matcher = MinimumSubsequenceMatcher(query: "aa")
        XCTAssertEqual(matcher.indexSet(for: "😀aa"), IndexSet(2...3))
        XCTAssertNil(matcher.indexSet(for: "😀a"))
        XCTAssertNil(MinimumSubsequenceMatcher(query: "").indexSet(for: "abc"))
    }
}
