//
//  WordStemmer.swift
//  iTerm2SharedARC
//

import Foundation
import NaturalLanguage

@objc(iTermWordStemmer)
final class WordStemmer: NSObject {
    @objc(stemString:)
    static func stem(_ string: String) -> String {
        guard !string.isEmpty else {
            return ""
        }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = string
        var stemmed: String?
        tagger.enumerateTags(in: string.startIndex..<string.endIndex,
                             unit: .word,
                             scheme: .lemma) { tag, _ in
            if let raw = tag?.rawValue, !raw.isEmpty {
                stemmed = raw.lowercased()
                return false
            }
            return true
        }
        return stemmed ?? string
    }
}
