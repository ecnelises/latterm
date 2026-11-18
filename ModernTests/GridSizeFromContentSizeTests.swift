//
//  GridSizeFromContentSizeTests.swift
//  ModernTests
//
//  Adding a tab to a window sizes the new session from the existing view's size divided by the
//  profile's cell size. A zero cell size (a font that measures as zero) made that infinite, which
//  Int32(clamping:) turned into Int32.max columns, and allocating the grid's lines threw
//  "-[NSConcreteMutableData initWithLength:]: absurd length". A grid size must be finite and
//  positive whatever the inputs.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class GridSizeFromContentSizeTests: XCTestCase {
    func testZeroCellSizeGivesSaneGrid() {
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: NSSize(width: 800, height: 600),
                                                     cellSize: .zero)
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertLessThanOrEqual(size.width, 800)
        XCTAssertGreaterThanOrEqual(size.height, 1)
        XCTAssertLessThanOrEqual(size.height, 600)
    }

    func testTinyContentSizeGivesAtLeastOneCell() {
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: .zero,
                                                     cellSize: NSSize(width: 7, height: 14))
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertGreaterThanOrEqual(size.height, 1)
    }

    func testNormalSize() {
        let margins = 2.0 * Double(iTermPreferences.sideMargins())
        let vmargins = 2.0 * Double(iTermPreferences.topBottomMargins())
        let size = TerminalWindowSizeHelper.gridSize(forContentSize: NSSize(width: 800 + margins,
                                                                            height: 280 + vmargins),
                                                     cellSize: NSSize(width: 10, height: 14))
        XCTAssertEqual(size.width, 80)
        XCTAssertEqual(size.height, 20)
    }

    // Int32(clamping: CGFloat) compared against Int.max, so values between Int32.max and Int.max
    // reached Int32(value), which traps.
    func testInt32ClampingOfLargeValue() {
        XCTAssertEqual(Int32(clamping: CGFloat(3_000_000_000)), Int32.max)
        XCTAssertEqual(Int32(clamping: CGFloat(-3_000_000_000)), Int32.min)
    }

    func testFractionalHalfPointCharacterWidthQuantization() throws {
        let menlo14 = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 14))
        let rawWidth = try XCTUnwrap(FontSizeEstimator(for: menlo14)).size.width
        // Menlo 14pt has a true advance around 8.43pt; FontSizeEstimator must preserve it unrounded.
        XCTAssertGreaterThan(rawWidth, 8.3)
        XCTAssertLessThan(rawWidth, 8.6)

        let retinaSize = PTYTextView.charSize(for: menlo14,
                                              horizontalSpacing: 1.0,
                                              verticalSpacing: 1.0,
                                              scale: 2.0)
        let nonRetinaSize = PTYTextView.charSize(for: menlo14,
                                                 horizontalSpacing: 1.0,
                                                 verticalSpacing: 1.0,
                                                 scale: 1.0)
        XCTAssertEqual(retinaSize.width, 8.5, accuracy: 0.0001)
        XCTAssertEqual(nonRetinaSize.width, 8.0, accuracy: 0.0001)

        // Horizontal spacing steps smoothly by 0.5pt on 2x Retina.
        let tightened = PTYTextView.charSize(for: menlo14,
                                             horizontalSpacing: 0.90,
                                             verticalSpacing: 1.0,
                                             scale: 2.0)
        XCTAssertEqual(tightened.width, 7.5, accuracy: 0.0001)
    }

    func testHalfPointCellWidthRoundTripsEvenAndOddColumns() {
        let margins = 2.0 * Double(iTermPreferences.sideMargins())
        let vmargins = 2.0 * Double(iTermPreferences.topBottomMargins())
        let cellSize = NSSize(width: 7.5, height: 16.0)

        for columns: Int32 in [80, 81, 82, 119, 120, 121] {
            let helper = TerminalWindowSizeHelper()
            let profile: [AnyHashable: Any] = [
                KEY_COLUMNS: Int(columns),
                KEY_ROWS: 24,
                KEY_WINDOW_TYPE: Int(iTermWindowType.WINDOW_TYPE_NORMAL.rawValue)
            ]
            let preferred = helper.preferredSize(cellSize: cellSize,
                                                 decorationSize: .zero,
                                                 profile: profile,
                                                 screenSize: NSSize(width: 3000, height: 2000))
            // Outer width is integral points (ceil of columns * 7.5 + margins) and maps back 1:1.
            XCTAssertEqual(preferred.width, ceil(CGFloat(columns) * cellSize.width) + margins, accuracy: 0.0001)
            XCTAssertEqual(preferred.width.truncatingRemainder(dividingBy: 1.0), 0.0, accuracy: 0.0001)

            let roundTripped = TerminalWindowSizeHelper.gridSize(
                forContentSize: NSSize(width: preferred.width, height: 24.0 * 16.0 + vmargins),
                cellSize: cellSize)
            XCTAssertEqual(roundTripped.width, columns, "Failed column round-trip for \(columns) columns at 7.5pt")
            XCTAssertEqual(roundTripped.height, 24)
        }
    }

    func testPTYTextViewInitAndSetFontTablePreservesHalfPointCharWidth() throws {
        let textView = try XCTUnwrap(PTYTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300)))
        let menlo14 = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 14))
        let fontTable = FontTable(defaultFont: PTYFontInfo(font: menlo14),
                                  nonAsciiFont: nil,
                                  configString: nil)
        textView.setFontTable(fontTable, horizontalSpacing: 1.0, verticalSpacing: 1.0)
        let expected = PTYTextView.charSize(for: menlo14,
                                            horizontalSpacing: 1.0,
                                            verticalSpacing: 1.0)
        XCTAssertEqual(textView.charWidth, expected.width, accuracy: 0.0001)
        XCTAssertEqual(textView.charWidthWithoutSpacing, expected.width, accuracy: 0.0001)
        textView.viewDidChangeBackingProperties()
    }
}
