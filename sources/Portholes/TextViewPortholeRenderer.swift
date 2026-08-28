//
//  TextViewPortholeRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/22.
//

import Foundation

class TextViewPortholeRenderer {
    enum Specialization: String, CaseIterable {
        case markdown
        case json
    }

    private static let plainTextLanguage = "plaintext"
    private static let supportedLanguageShortNames =
        Set(Specialization.allCases.map(\.rawValue) + [plainTextLanguage])

    static let identifier = "TextViewPortholeRenderer"

    let text: String
    let _languages: Set<String>
    private var markdownRenderer: MarkdownPortholeRenderer?
    private var jsonRenderer: JSONPortholeRenderer?

    var languages: Set<String> {
        guard let db = FileExtensionDB.instance else {
            return _languages
        }
        return Set(_languages.compactMap { db.shortNameToLanguage[$0] })
    }

    var languageCandidateShortNames: [String] {
        return Array(_languages)
    }

    var language: String?

    static var allLanguages: Set<String> {
        guard let db = FileExtensionDB.instance else {
            return Set(["JSON", "Markdown", "Plain text"])
        }
        return Set(supportedLanguageShortNames.compactMap { db.shortNameToLanguage[$0] })
    }

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        if let result = renderIfSpecialized(visualAttributes: visualAttributes) {
            return result
        }
        return NSAttributedString(
            string: text,
            attributes: [
                .font: visualAttributes.font,
                .foregroundColor: visualAttributes.textColor,
            ])
    }

    init(_ text: String, type: String?, filename: String?) {
        self.text = text

        let candidates: Set<String>
        if let type,
           let languages = FileExtensionDB.instance?.languagesForTypeHint(type) {
            candidates = languages
        } else if let filename,
                  let languages = FileExtensionDB.instance?.languagesForPath(filename) {
            candidates = languages
        } else {
            candidates = Set()
        }

        _languages = candidates.intersection(Self.supportedLanguageShortNames)
        if _languages.count == 1 {
            language = _languages.first
        } else if MarkdownPortholeRenderer.wants(text) {
            language = Specialization.markdown.rawValue
        } else if JSONPortholeRenderer.wants(text) {
            language = Specialization.json.rawValue
        } else {
            language = Self.plainTextLanguage
        }
    }

    init(_ text: String, language: String?, languages: [String]?) {
        self.text = text
        if let language,
           Self.supportedLanguageShortNames.contains(language) {
            self.language = language
        } else {
            self.language = Self.plainTextLanguage
        }
        _languages = Set(languages ?? []).intersection(Self.supportedLanguageShortNames)
    }

    private func renderIfSpecialized(
        visualAttributes: TextViewPorthole.VisualAttributes
    ) -> NSAttributedString? {
        guard let language,
              let specialization = Specialization(rawValue: language) else {
            return nil
        }

        switch specialization {
        case .markdown:
            if markdownRenderer == nil {
                markdownRenderer = MarkdownPortholeRenderer(text)
            }
            return markdownRenderer?.render(visualAttributes: visualAttributes)
        case .json:
            if jsonRenderer == nil {
                jsonRenderer = JSONPortholeRenderer.forced(text)
            }
            return jsonRenderer?.render(visualAttributes: visualAttributes)
        }
    }
}
