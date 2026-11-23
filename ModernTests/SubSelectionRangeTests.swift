import XCTest
@testable import iTerm2SharedARC

final class SubSelectionRangeTests: XCTestCase {
    func testColumnWindowClipsRowEndsAndConnectsOnlyIntermediatePieces() {
        let range = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(4, 10, 5, 12), 3, 4)
        let selection = iTermSubSelection(absRange: range, mode: .kiTermSelectionModeCharacter, width: 80)
        let pieces = selection.nonwindowedComponents(width: 80)
        let expected = [VT100GridAbsCoordRangeMake(4, 10, 7, 10),
                        VT100GridAbsCoordRangeMake(3, 11, 7, 11),
                        VT100GridAbsCoordRangeMake(3, 12, 5, 12)]
        XCTAssertEqual(pieces.count, expected.count)
        for (piece, range) in zip(pieces, expected) {
            XCTAssertTrue(VT100GridAbsCoordRangeEquals(piece.absRange.coordRange, range))
            XCTAssertEqual(piece.absRange.columnWindow.length, 0)
        }
        XCTAssertEqual(pieces.map(\.connected), [true, true, false])
    }

    func testBoxAndUnwindowedSelectionsRemainSingleObjects() {
        let range = VT100GridAbsCoordRangeMake(3, 5, 9, 7)
        let box = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(range, 4, 5),
                                    mode: .kiTermSelectionModeBox, width: 80)
        let character = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(range, 0, 0),
                                          mode: .kiTermSelectionModeCharacter, width: 80)
        for selection in [box, character] {
            let pieces = selection.nonwindowedComponents(width: 80)
            XCTAssertEqual(pieces.count, 1)
            XCTAssertTrue(pieces.first === selection)
        }
    }

    func testHitTestingReversedRangeAtLargeScrollbackOffsets() {
        // Flattening row and column into one integer would overflow at these offsets.
        let row = Int64.max / 7
        let range = VT100GridAbsCoordRangeMake(6, row, 4, row - 1)
        let selection = iTermSubSelection(absRange: VT100GridAbsWindowedRangeMake(range, 3, 8),
                                          mode: .kiTermSelectionModeCharacter, width: 80)
        XCTAssertTrue(selection.contains(VT100GridAbsCoordMake(4, row - 1)))
        XCTAssertTrue(selection.contains(VT100GridAbsCoordMake(5, row)))
        XCTAssertFalse(selection.contains(VT100GridAbsCoordMake(6, row)))
        XCTAssertFalse(selection.contains(VT100GridAbsCoordMake(12, row - 1)))
    }
}
