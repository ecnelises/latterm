//
//  MarkdownPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/13/22.
//

import AppKit
import Foundation

class MarkdownPortholeRenderer {
    private let markdown: String

    static func wants(_ text: String) -> Bool {
        return text.range(of: "^# .", options: .regularExpression) != nil
    }

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return Self.attributedString(markdown: markdown,
                                     visualAttributes: visualAttributes)
    }

    private static func attributedString(markdown: String,
                                         visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return NSAttributedString.iTerm_attributedString(
            markdown: markdown,
            baseFont: visualAttributes.font,
            textColor: visualAttributes.textColor,
            headingScales: [2, 1.5, 1.3, 1, 0.8, 0.7],
            codeFont: visualAttributes.font)
    }

    init(_ text: String) {
        markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

