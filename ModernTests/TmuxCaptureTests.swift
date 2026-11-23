import XCTest
@testable import iTerm2SharedARC

final class TmuxCaptureTests: XCTestCase {
    func testTablePreservesEmptyFieldsExtraColumnsAndTheLastDuplicateField() {
        let fields = ["id", "name", "id"]
        let table = TmuxTable(response: "one\t\tlast\textra\nshort\trow\n", fields: fields, workAroundTabBug: false)
        XCTAssertEqual(table.records, [["one", "", "last", "extra"]])
        XCTAssertEqual(table.value(in: table.records[0], forField: "id"), "last")
        XCTAssertEqual(table.value(in: table.records[0], forField: "name"), "")
        XCTAssertNil(table.value(in: [], forField: "id"))
        XCTAssertNil(table.value(in: table.records[0], forField: "unrequested"))
    }

    func testLiteralTabsAreSplitOnlyWhenRequestedAndNoRealTabWasPresent() {
        let input = "1\\tfirst\n2\tsecond\\tpart"
        let fields = ["id", "name"]
        let table = TmuxTable(response: input, fields: fields, workAroundTabBug: true)
        XCTAssertEqual(table.records, [["1", "first"], ["2", "second\\tpart"]])
        XCTAssertEqual(TmuxTable(response: input, fields: fields, workAroundTabBug: false).records, [["2", "second\\tpart"]])
    }

    func testCaptureKeepsRenditionAcrossRowsAndPreservesEmptyLastRow() throws {
        let rows = try XCTUnwrap(TmuxHistoryParser.shared.parse("\u{1b}[1mA\n界\u{1b}[0mB\n",
                                                                ambiguousIsDoubleWidth: false, unicodeVersion: 9,
                                                                alternateScreen: false, rtlFound: nil))
        let stride = MemoryLayout<screen_char_t>.stride
        XCTAssertEqual(rows.map(\.count), [stride, 3 * stride, 0])
        let first = rows[0].withUnsafeBytes { $0.loadUnaligned(as: screen_char_t.self) }
        XCTAssertEqual(first.code, 65)
        XCTAssertNotEqual(first.bold, 0)
        let wide = rows[1].withUnsafeBytes { $0.loadUnaligned(as: screen_char_t.self) }
        XCTAssertNotEqual(wide.bold, 0)
        let last = rows[1].withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2 * stride, as: screen_char_t.self) }
        XCTAssertEqual(last.code, 66)
        XCTAssertEqual(last.bold, 0)
    }

    func testEmptyHistoryResetsRTLFlag() {
        var rtl: ObjCBool = true
        XCTAssertEqual(TmuxHistoryParser.shared.parse("", ambiguousIsDoubleWidth: false, unicodeVersion: 9,
                                                      alternateScreen: true, rtlFound: &rtl), [])
        XCTAssertFalse(rtl.boolValue)
    }
}
