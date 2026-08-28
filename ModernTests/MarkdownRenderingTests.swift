//
//  MarkdownRenderingTests.swift
//  ModernTests
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class MarkdownRenderingTests: XCTestCase {
    private let baseFont = NSFont.systemFont(ofSize: 13)

    func testFrontMatterAndInlineStyles() throws {
        let markdown = """
        ---
        title: Hidden Metadata
        ---
        # Heading

        Some **bold**, *italic*, and [linked](https://example.com) text.
        """
        let rendered = NSAttributedString.iTerm_attributedString(
            markdown: markdown,
            baseFont: baseFont,
            textColor: .labelColor)

        XCTAssertFalse(rendered.string.contains("Hidden Metadata"))
        XCTAssertTrue(rendered.string.contains("Heading\nSome bold, italic, and linked text."))

        let string = rendered.string as NSString
        let headingFont = try XCTUnwrap(rendered.attribute(.font,
                                                            at: string.range(of: "Heading").location,
                                                            effectiveRange: nil) as? NSFont)
        XCTAssertEqual(headingFont.pointSize, 26)
        XCTAssertTrue(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))

        let boldFont = try XCTUnwrap(rendered.attribute(.font,
                                                         at: string.range(of: "bold").location,
                                                         effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        let italicFont = try XCTUnwrap(rendered.attribute(.font,
                                                           at: string.range(of: "italic").location,
                                                           effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))

        let link = rendered.attribute(.link,
                                      at: string.range(of: "linked").location,
                                      effectiveRange: nil) as? URL
        XCTAssertEqual(link, URL(string: "https://example.com"))
    }

    func testBlockStructureAndCodeFont() throws {
        let markdown = """
        - one
        - two

        > quote

        ```swift
        let value = 1
        ```
        """
        let rendered = NSAttributedString.iTerm_attributedString(
            markdown: markdown,
            baseFont: baseFont,
            textColor: .labelColor)

        XCTAssertEqual(rendered.string, "• one\n• two\n› quote\nlet value = 1\n")
        let codeRange = (rendered.string as NSString).range(of: "let value = 1")
        let codeFont = try XCTUnwrap(rendered.attribute(.font,
                                                         at: codeRange.location,
                                                         effectiveRange: nil) as? NSFont)
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testInlineCodeContainingBackticksRoundTrips() {
        let literal = "left`middle``right"
        let markdown = (literal as NSString).stringEnclosedInMarkdownInlineCode
        let rendered = NSAttributedString.iTerm_attributedString(
            markdown: markdown,
            baseFont: baseFont,
            textColor: .labelColor)

        XCTAssertEqual(rendered.string.replacingOccurrences(of: "\u{feff}", with: ""), literal)
    }
}
