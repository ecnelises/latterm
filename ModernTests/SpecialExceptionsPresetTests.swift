import XCTest
@testable import iTerm2SharedARC

final class SpecialExceptionsPresetTests: XCTestCase {
    private func makeDistinctFonts() -> [NSFont] {
        let candidates = [
            "Menlo",
            "Monaco",
            "Courier",
            "Courier New",
            "Helvetica",
            "Times New Roman"
        ]
        var fonts: [NSFont] = []
        for candidate in candidates {
            guard let font = NSFont(name: candidate, size: 12),
                  let familyName = font.familyName else {
                continue
            }
            if fonts.allSatisfy({ $0.familyName != familyName }) {
                fonts.append(font)
            }
            if fonts.count == 3 {
                return fonts
            }
        }
        XCTFail("Expected at least three distinct fonts for the font table tests")
        let fallback = NSFont.userFixedPitchFont(ofSize: 12)!
        return [fallback, fallback, fallback]
    }

    private func makeFontTable(entries: [FontTable.Entry] = []) -> (FontTable, [NSFont]) {
        let fonts = makeDistinctFonts()
        let ascii = PTYFontInfo(font: fonts[0])
        let nonAscii = PTYFontInfo(font: fonts[1])
        let configString = entries.isEmpty ? nil : FontTable.Config(entries: entries).stringValue
        let table = FontTable(defaultFont: ascii,
                              nonAsciiFont: nonAscii,
                              configString: configString)
        return (table, fonts)
    }

    private func familyName(for codePoint: UTF32Char, in table: FontTable) -> String? {
        var remapped = codePoint
        return table.font(for: codePoint, remapped: &remapped).font.familyName
    }

    func testPresetCatalogMatchesExpectedRanges() {
        XCTAssertEqual(SpecialExceptionRangePreset.han.range, 0x4E00...0x9FFF)
        XCTAssertEqual(SpecialExceptionRangePreset.hiraganaKatakana.range, 0x3040...0x30FF)
        XCTAssertEqual(SpecialExceptionRangePreset.hangulSyllables.range, 0xAC00...0xD7AF)
        XCTAssertEqual(SpecialExceptionRangePreset.arabic.range, 0x0600...0x06FF)
        XCTAssertEqual(SpecialExceptionRangePreset.cyrillic.range, 0x0400...0x04FF)
        XCTAssertEqual(SpecialExceptionRangePreset.greek.range, 0x0370...0x03FF)
        XCTAssertEqual(SpecialExceptionRangePreset.privateUseArea.range, 0xE000...0xF8FF)
    }

    func testPresetMenuOrderIsAlphabetical() {
        let titles = SpecialExceptionRangePreset.menuOrder.map(\.title)
        XCTAssertEqual(titles.count, 7)
        XCTAssertEqual(titles, titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    func testCharacterFontEditorLoadsLocalizedWindowAndPreservesRules() {
        let controller = SpecialExceptionsWindowController.create(configString: nil)
        XCTAssertEqual(controller.window?.title, NSLocalizedString("Character Fonts", comment: "Font editor"))
        XCTAssertNotNil(controller.editorWindowController.window)
        XCTAssertEqual(controller.editorWindowController.window?.title,
                       NSLocalizedString("Edit Special Exception", comment: "Font rule editor"))
        XCTAssertTrue(controller.config.entries.isEmpty)
        controller.close()
    }

    func testNoConfigPreservesLegacyNonAsciiFallbackBehavior() {
        let (table, fonts) = makeFontTable()

        XCTAssertEqual(familyName(for: 0x41, in: table), fonts[0].familyName)
        XCTAssertEqual(familyName(for: 0x4E2D, in: table), fonts[1].familyName)
    }

    func testExplicitPresetOverridesLegacyNonAsciiFallback() {
        let ruleFont = makeDistinctFonts()[2]
        var entry = SpecialExceptionRangePreset.han.entry
        entry.fontName = ruleFont.fontName

        let (table, fonts) = makeFontTable(entries: [entry])

        XCTAssertEqual(familyName(for: 0x4E2D, in: table), ruleFont.familyName)
        XCTAssertEqual(familyName(for: 0x3042, in: table), fonts[1].familyName)
    }

    func testGreekPresetOverridesLegacyNonAsciiFallback() {
        let ruleFont = makeDistinctFonts()[2]
        var entry = SpecialExceptionRangePreset.greek.entry
        entry.fontName = ruleFont.fontName

        let (table, fonts) = makeFontTable(entries: [entry])

        XCTAssertEqual(familyName(for: 0x03A9, in: table), ruleFont.familyName)
        XCTAssertEqual(familyName(for: 0x0416, in: table), fonts[1].familyName)
    }

    func testPresetEntriesDoNotRemapCodePoints() {
        var entry = SpecialExceptionRangePreset.privateUseArea.entry
        entry.fontName = makeDistinctFonts()[2].fontName
        let (table, _) = makeFontTable(entries: [entry])

        let codePoint: UTF32Char = 0xE0B0
        var remapped = codePoint
        _ = table.font(for: codePoint, remapped: &remapped)

        XCTAssertEqual(remapped, codePoint)
    }

    private func configString(entries: [[String: Any]], version: Int = 2) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["version": version, "entries": entries])
        return String(decoding: data, as: UTF8.self)
    }

    func testImportedRulesRejectInvalidAndOverflowingRanges() throws {
        for (start, count, destination) in [
            (-1, 1, nil), (0x110000, 1, nil), (128, 0, nil), (128, -1, nil),
            (Int.max, 2, nil), (128, Int.max, nil), (128, 1, -1),
            (128, 2, Int.max), (0x10FFFF, 2, nil), (128, 2, 0x10FFFF)
        ] as [(Int, Int, Int?)] {
            var entry: [String: Any] = ["start": start, "count": count, "fontName": "Menlo"]
            if let destination { entry["destination"] = destination }
            XCTAssertNil(FontTable.Config(string: try configString(entries: [entry])))
        }
    }

    func testImportedRulesRejectOverlapsAfterRemapping() throws {
        let entries: [[String: Any]] = [
            ["start": 0x400, "count": 16, "fontName": "Menlo"],
            ["start": 0xE000, "count": 16, "destination": 0x408, "fontName": "Monaco"]
        ]
        XCTAssertNil(FontTable.Config(string: try configString(entries: entries)))
    }

    func testImportedRulesValidateVersionFontAndSize() throws {
        let entry: [String: Any] = ["start": 128, "count": 1, "fontName": "Menlo"]
        for version in [0, -1, FontTable.Config.latestKnownVersion + 1] {
            XCTAssertNil(FontTable.Config(string: try configString(entries: [entry], version: version)))
        }
        var invalid = entry
        invalid["fontName"] = ""
        XCTAssertNil(FontTable.Config(string: try configString(entries: [invalid])))
        for size in [0, -1] {
            invalid = entry
            invalid["pointSize"] = size
            XCTAssertNil(FontTable.Config(string: try configString(entries: [invalid])))
        }
    }

    func testImportedBoundaryAndRemappingRulesRoundTrip() throws {
        let entries: [[String: Any]] = [
            ["start": 0x10FFFF, "count": 1, "fontName": "Menlo"],
            ["start": 0xE000, "count": 16, "destination": 128, "fontName": "Monaco", "pointSize": 15]
        ]
        let config = try XCTUnwrap(FontTable.Config(string: configString(entries: entries)))
        XCTAssertEqual(config.entries[0].destination, 128)
        XCTAssertEqual(config.entries[0].pointSize, 15)
        XCTAssertEqual(config.entries[1].range, 0x10FFFF..<0x110000)
        XCTAssertEqual(FontTable.Config(string: config.stringValue), config)
        XCTAssertNotNil(FontTable.Config(string: try configString(entries: entries, version: 1)))
    }

    func testMalformedProfileFontRulesFallBackWithoutChangingCellMetrics() throws {
        let fonts = makeDistinctFonts()
        let invalid = try configString(entries: [["start": Int.max, "count": 2, "fontName": "Menlo"]])
        let table = FontTable(defaultFont: PTYFontInfo(font: fonts[0]),
                              nonAsciiFont: PTYFontInfo(font: fonts[1]),
                              configString: invalid)
        XCTAssertEqual(table.fontForCharacterSizeCalculations, fonts[0])
        XCTAssertEqual(familyName(for: 0x4E2D, in: table), fonts[1].familyName)
    }


    func testFontZoomPersistsExplicitRuleSizesAndKeepsInheritedSizes() throws {
        let font = makeDistinctFonts()[2]
        let entries = [
            FontTable.Entry(start: 0x400, count: 16, fontName: font.fontName, pointSize: 14),
            FontTable.Entry(start: 0x4E00, count: 16, fontName: font.fontName)
        ]
        let (table, _) = makeFontTable(entries: entries)
        let grown = table.fontTable(grownBy: 2)
        let config = try XCTUnwrap(FontTable.Config(string: try XCTUnwrap(grown.configString)))
        XCTAssertEqual(config.entries[0].pointSize, 16)
        XCTAssertNil(config.entries[1].pointSize)
        var remapped: UTF32Char = 0
        XCTAssertEqual(grown.font(for: 0x400, remapped: &remapped).font.pointSize, 16)
        XCTAssertEqual(grown.font(for: 0x4E00, remapped: &remapped).font.pointSize,
                       grown.fontForCharacterSizeCalculations.pointSize)
        let restored = FontTable(defaultFont: grown.asciiFont,
                                 nonAsciiFont: grown.defaultNonASCIIFont,
                                 configString: grown.configString)
        XCTAssertTrue(restored.isEqual(grown))
    }


    func testFontZoomClampsExplicitRuleSizesToSupportedBounds() throws {
        let entries = [FontTable.Entry(start: 0x400, count: 16,
                                      fontName: makeDistinctFonts()[2].fontName, pointSize: 14)]
        let (table, _) = makeFontTable(entries: entries)
        for (delta, expectedSize): (CGFloat, CGFloat) in [(-20, 2), (300, 200)] {
            let grown = table.fontTable(grownBy: delta)
            let config = try XCTUnwrap(FontTable.Config(string: try XCTUnwrap(grown.configString)))
            XCTAssertEqual(config.entries[0].pointSize, expectedSize)
        }
    }

    func testRangeEditorPreservesRuleSizeAndRejectsOverflowingInput() throws {
        let manager = SpecialExceptionsWindowController.create(configString: nil)
        XCTAssertNotNil(manager.window)
        let editor = try XCTUnwrap(manager.editorWindowController)
        editor.delegate = manager
        editor.entry = FontTable.Entry(start: 128, count: 2,
                                       fontName: makeDistinctFonts()[0].familyName!, pointSize: 15)
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification,
                                                    object: editor.end))
        XCTAssertEqual(editor.entry?.pointSize, 15)
        editor.start.stringValue = String(Int.min)
        editor.end.stringValue = String(Int.max)
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.end))
        XCTAssertFalse(editor.ok.isEnabled)
        editor.start.stringValue = "128"
        editor.end.stringValue = "129"
        editor.hasDestination.state = .on
        editor.destination.stringValue = String(Int.max)
        editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.destination))
        XCTAssertFalse(editor.ok.isEnabled)
        manager.close()
    }

}
