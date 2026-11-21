//
//  MetalLigatureRenderingTests.swift
//  ModernTests
//
//  Regression tests for Stage 2.1: Unified Metal Rendering Pipeline & Native GPU Ligatures.
//

import AppKit
import CoreText
import Metal
import XCTest
@testable import iTerm2SharedARC

final class MetalLigatureRenderingTests: XCTestCase {

    // MARK: - Helpers

    private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else {
            return nil
        }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private func nonZeroByteCount(_ bitmap: iTermCharacterBitmap) -> Int {
        guard let data = bitmap.data else {
            return 0
        }
        return (data as Data).withUnsafeBytes { rawBuffer in
            rawBuffer.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        }
    }

    // MARK: - 1. Multi-Cell Tile Grid & Lossless Part Encoding

    func testCharacterPartsEncodingSupportsWideLigaturesAndDoubleWidthWithoutWrap() {
        XCTAssertEqual(iTermTextureMapMaxCharacterParts, 9,
                       "Single-width radius must be 4 (9x9 grid) so 4- and 5-cell ligatures never clip")

        let middle = iTermImagePartFromDeltas(0, 0)
        XCTAssertEqual(middle, iTermTextureMapMiddleCharacterPart)
        XCTAssertEqual(iTermImagePartFromDeltas(1, 0), iTermTextureMapMiddleCharacterPart + 1)

        // Verify lossless round-trip across both single-width ([-4, 4]) and double-width ([-9, 9]) ranges.
        let dwRadius = iTermTextureMapMaxCharacterParts
        var seenParts = Set<Int32>()
        for dy in -dwRadius...dwRadius {
            for dx in -dwRadius...dwRadius {
                let part = iTermImagePartFromDeltas(dx, dy)
                XCTAssertFalse(seenParts.contains(part),
                               "Duplicate encoded part \(part) at dx=\(dx), dy=\(dy)")
                seenParts.insert(part)
                XCTAssertEqual(iTermImagePartDX(part), dx, "DX round-trip failed at (\(dx), \(dy))")
                XCTAssertEqual(iTermImagePartDY(part), dy, "DY round-trip failed at (\(dx), \(dy))")
            }
        }
    }

    // MARK: - 2. Blank Spacer Skipping & Antialiasing Selection in iTermGlyphCharacterSource

    func testGlyphCharacterSourceSkipsBlankSpacerGlyphsAndHonorsAntialiasingFlag() {
        let font = NSFont(name: "Menlo-Regular", size: 13) ?? NSFont.userFixedPitchFont(ofSize: 13)!
        let fontInfo = PTYFontInfo(font: font)
        let fontTable = FontTable(defaultFont: fontInfo, nonAsciiFont: nil, configString: nil)

        let scale: CGFloat = 2.0
        let cellWithoutSpacing = PTYTextView.charSize(for: fontTable.fontForCharacterSizeCalculations,
                                                      horizontalSpacing: 1.0,
                                                      verticalSpacing: 1.0,
                                                      scale: scale)
        let cellSize = CGSize(width: cellWithoutSpacing.width * scale,
                              height: cellWithoutSpacing.height * scale)
        let glyphSize = CGSize(width: ceil(cellSize.width) + 4,
                               height: ceil(cellSize.height) + 4)

        let radius = iTermTextureMapMaxCharacterParts / 2
        let maxParts = Int(radius * 2 + 1)
        guard let ctx = makeBitmapContext(width: Int(glyphSize.width) * maxParts,
                                          height: Int(glyphSize.height) * maxParts) else {
            XCTFail("Failed to allocate test CGContext")
            return
        }

        // Deliberately set asciiAntiAliased != nonAsciiAntiAliased so we verify the explicit
        // `antialiased:` parameter controls rasterization rather than descriptor.nonAsciiAntiAliased.
        let descriptor = iTermCharacterSourceDescriptor(fontTable: fontTable,
                                                        asciiOffset: .zero,
                                                        glyphSize: glyphSize,
                                                        cellSize: cellSize,
                                                        cellSizeWithoutSpacing: cellWithoutSpacing,
                                                        scale: scale,
                                                        useBoldFont: true,
                                                        useItalicFont: true,
                                                        usesNonAsciiFont: false,
                                                        asciiAntiAliased: false,
                                                        nonAsciiAntiAliased: true)!
        let attrs = iTermCharacterSourceAttributes(thinStrokes: false, bold: false, italic: false)!

        // 1) Space glyph must yield zero parts so calt spacers and spaces consume zero GPU atlas slots.
        var spaceChar: UniChar = 0x20
        var spaceGlyph: CGGlyph = 0
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, &spaceChar, &spaceGlyph, 1))
        let spaceSource = iTermCharacterSource(fontID: UInt32(font.it_metalFontID),
                                               fakeBold: false,
                                               fakeItalic: false,
                                               antialiased: true,
                                               glyphNumber: spaceGlyph,
                                               position: .zero,
                                               descriptor: descriptor,
                                               attributes: attrs,
                                               radius: radius,
                                               lineAttribute: .singleWidth,
                                               context: ctx)
        XCTAssertNotNil(spaceSource)
        XCTAssertEqual(spaceSource?.parts.count, 0,
                       "Whitespace / invisible spacer glyphs must produce 0 texture atlas tiles")

        // 2) Diagonal glyph '/' must produce binary alpha (0 or 255) when antialiased=false,
        //    and fractional coverage alpha (1...254) when antialiased=true.
        var slashChar: UniChar = 0x2F
        var slashGlyph: CGGlyph = 0
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, &slashChar, &slashGlyph, 1))

        let aliasedSource = iTermCharacterSource(fontID: UInt32(font.it_metalFontID),
                                                 fakeBold: false,
                                                 fakeItalic: false,
                                                 antialiased: false,
                                                 glyphNumber: slashGlyph,
                                                 position: .zero,
                                                 descriptor: descriptor,
                                                 attributes: attrs,
                                                 radius: radius,
                                                 lineAttribute: .singleWidth,
                                                 context: ctx)!
        let aaSource = iTermCharacterSource(fontID: UInt32(font.it_metalFontID),
                                            fakeBold: false,
                                            fakeItalic: false,
                                            antialiased: true,
                                            glyphNumber: slashGlyph,
                                            position: .zero,
                                            descriptor: descriptor,
                                            attributes: attrs,
                                            radius: radius,
                                            lineAttribute: .singleWidth,
                                            context: ctx)!

        let centerPart = iTermImagePartFromDeltas(0, 0)
        guard let aliasedBitmap = aliasedSource.bitmap(forPart: centerPart),
              let aaBitmap = aaSource.bitmap(forPart: centerPart),
              let aliasedData = aliasedBitmap.data as Data?,
              let aaData = aaBitmap.data as Data? else {
            XCTFail("Expected center bitmap for '/'")
            return
        }

        let aliasedIntermediateCount = aliasedData.withUnsafeBytes { buf in
            buf.filter { $0 > 0 && $0 < 255 }.count
        }
        let aaIntermediateCount = aaData.withUnsafeBytes { buf in
            buf.filter { $0 > 0 && $0 < 255 }.count
        }
        XCTAssertEqual(aliasedIntermediateCount, 0,
                       "Aliased glyph source should have no intermediate grayscale coverage bytes")
        XCTAssertGreaterThan(aaIntermediateCount, 0,
                             "Antialiased glyph source should contain antialiased edge coverage bytes")
    }

    // MARK: - 3. 4-Cell Programming Ligature Shaping & Unclipped Multi-Tile Rasterization

    func testFourCellProgrammingLigatureSpansAllTilesWithoutClipping() throws {
        if let jbFont = NSFont(name: "JetBrainsMono-Regular", size: 14) {
            let fontInfo = PTYFontInfo(font: jbFont)
            let fontTable = FontTable(defaultFont: fontInfo, nonAsciiFont: nil, configString: nil)
            let scale: CGFloat = 2.0
            let cellWithoutSpacing = PTYTextView.charSize(for: jbFont,
                                                          horizontalSpacing: 1.0,
                                                          verticalSpacing: 1.0,
                                                          scale: scale)
            let cellSize = CGSize(width: cellWithoutSpacing.width * scale,
                                  height: cellWithoutSpacing.height * scale)
            let glyphSize = CGSize(width: ceil(cellSize.width) + 4,
                                   height: ceil(cellSize.height) + 4)
            let radius = iTermTextureMapMaxCharacterParts / 2
            let maxParts = Int(radius * 2 + 1)
            let ctx = try XCTUnwrap(makeBitmapContext(width: Int(glyphSize.width) * maxParts,
                                                      height: Int(glyphSize.height) * maxParts))
            let descriptor = try XCTUnwrap(
                iTermCharacterSourceDescriptor(fontTable: fontTable,
                                               asciiOffset: .zero,
                                               glyphSize: glyphSize,
                                               cellSize: cellSize,
                                               cellSizeWithoutSpacing: cellWithoutSpacing,
                                               scale: scale,
                                               useBoldFont: true,
                                               useItalicFont: true,
                                               usesNonAsciiFont: false,
                                               asciiAntiAliased: true,
                                               nonAsciiAntiAliased: true)
            )
            let sourceAttrs = try XCTUnwrap(iTermCharacterSourceAttributes(thinStrokes: false, bold: false, italic: false))

            let sample = "<-->"
            var drawCells: [Int32] = [0, 1, 2, 3]
            let drawCellData = Data(bytes: &drawCells, count: drawCells.count * MemoryLayout<Int32>.size)
            let attrStr = NSAttributedString(string: sample, attributes: [
                .font: jbFont,
                NSAttributedString.Key(kCTLigatureAttributeName as String): 2
            ])
            let ctLine = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
            let helper = iTermCoreTextLineRenderingHelper(line: ctLine,
                                                          string: sample,
                                                          drawInCellIndex: drawCellData)

            var touchedColumns = Set<Int>()
            var zeroPartSpacerGlyphs = 0

            helper.enumerateGridAlignedRuns(withColumnPositions: nil, alignToZero: true) { _, runFont, glyphs, positions, glyphToChar, length, _ in
                let nsFont = runFont as NSFont
                let fontID = UInt32(nsFont.it_metalFontID)
                for i in 0..<length {
                    let sourceCell = Int(drawCells[glyphToChar[i]])
                    guard let src = iTermCharacterSource(fontID: fontID,
                                                         fakeBold: false,
                                                         fakeItalic: false,
                                                         antialiased: true,
                                                         glyphNumber: glyphs[i],
                                                         position: positions[i],
                                                         descriptor: descriptor,
                                                         attributes: sourceAttrs,
                                                         radius: radius,
                                                         lineAttribute: .singleWidth,
                                                         context: ctx) else {
                        XCTFail("Expected character source for glyph \(glyphs[i])")
                        continue
                    }
                    if src.parts.isEmpty {
                        zeroPartSpacerGlyphs += 1
                    }
                    for partNum in src.parts {
                        let part = partNum.int32Value
                        if let bmp = src.bitmap(forPart: part), self.nonZeroByteCount(bmp) > 0 {
                            touchedColumns.insert(sourceCell + Int(iTermImagePartDX(part)))
                        }
                    }
                }
            }

            XCTAssertTrue(touchedColumns.isSuperset(of: [0, 1, 2, 3]),
                          "4-cell '<-->' ligature must cover all 4 columns [0,1,2,3], got \(touchedColumns.sorted())")
            XCTAssertGreaterThan(zeroPartSpacerGlyphs, 0,
                                 "JetBrains Mono calt spacer glyphs should skip atlas allocation")
        }
    }

    // MARK: - 4. Session Metal Eligibility with Ligatures Enabled

    func testMetalAllowedWithASCIIAndNonASCIILigaturesEnabled() throws {
        guard MTLCreateSystemDefaultDevice() != nil,
              let screen = NSScreen.main,
              let baseProfile = ProfileModel.sharedInstance()?.defaultProfile() else {
            return
        }

        var mutableProfile = baseProfile
        mutableProfile[KEY_GUID] = "test-metal-allowed-ligatures-\(UUID().uuidString)"
        mutableProfile[KEY_NAME] = "Metal Allowed Ligatures Test"
        let chosenFontName = NSFont(name: "JetBrainsMono-Regular", size: 13) != nil
            ? "JetBrainsMono-Regular 13"
            : "Menlo-Regular 13"
        mutableProfile[KEY_NORMAL_FONT] = chosenFontName
        mutableProfile[KEY_NON_ASCII_FONT] = "PingFangSC-Regular 13"
        mutableProfile[KEY_USE_NONASCII_FONT] = true
        mutableProfile[KEY_ASCII_LIGATURES] = true
        mutableProfile[KEY_NON_ASCII_LIGATURES] = true
        mutableProfile[KEY_FONT_CONFIG] = #"{"version":3,"entries":[],"languageRules":[{"script":"zh-Hans","fontName":"PingFangSC-Regular","scalePercent":100,"baselineOffset":1.5,"enabled":true}]}"#

        let savedUseMetal = iTermPreferences.bool(forKey: kPreferenceKeyUseMetal)
        let savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        let savedLowPower = iTermPreferences.bool(forKey: kPreferenceKeyDisableInLowPowerMode)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseMetal)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyBidi)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyDisableInLowPowerMode)
        defer {
            iTermPreferences.setBool(savedUseMetal, forKey: kPreferenceKeyUseMetal)
            iTermPreferences.setBool(savedBidi, forKey: kPreferenceKeyBidi)
            iTermPreferences.setBool(savedLowPower, forKey: kPreferenceKeyDisableInLowPowerMode)
        }

        let frameSize = NSSize(width: 640, height: 320)
        let session = try XCTUnwrap(PTYSession(synthetic: true))
        session.profile = mutableProfile
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(mutableProfile)
        session.loadInitialColorTableAndResetCursorGuide()

        let window = NSWindow(contentRect: NSRect(origin: screen.frame.origin, size: frameSize),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false,
                              screen: screen)
        window.contentView = session.view
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        var unavailableReason: iTermMetalUnavailableReason = .none
        let allowed = session.metalAllowed(&unavailableReason)
        XCTAssertTrue(allowed,
                      "PTYSession must allow Metal when ligatures are enabled (got reason: \(unavailableReason.rawValue))")
    }
}
