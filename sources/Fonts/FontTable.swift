//
//  FontTable.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/23.
//

import AppKit
import Foundation

enum FontLanguageScript: String, Codable, CaseIterable, Identifiable, Hashable {
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case japaneseKana = "ja-Kana"
    case korean = "ko"
    case koreanHangul = "ko-Hang"
    case cyrillic = "Cyrl"
    case greek = "Grek"
    case arabic = "Arab"
    case hebrew = "Hebr"
    case devanagari = "Deva"
    case thai = "Thai"
    case symbolsAndNerdFont = "Zsym"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .chineseSimplified:
            return NSLocalizedString("Simplified Chinese", comment: "Language font script")
        case .chineseTraditional:
            return NSLocalizedString("Traditional Chinese", comment: "Language font script")
        case .japanese:
            return NSLocalizedString("Japanese (Kana & Kanji)", comment: "Language font script")
        case .japaneseKana:
            return NSLocalizedString("Japanese (Kana Only)", comment: "Language font script")
        case .korean:
            return NSLocalizedString("Korean (Hangul & Hanja)", comment: "Language font script")
        case .koreanHangul:
            return NSLocalizedString("Korean (Hangul Only)", comment: "Language font script")
        case .cyrillic:
            return NSLocalizedString("Cyrillic", comment: "Language font script")
        case .greek:
            return NSLocalizedString("Greek", comment: "Language font script")
        case .arabic:
            return NSLocalizedString("Arabic", comment: "Language font script")
        case .hebrew:
            return NSLocalizedString("Hebrew", comment: "Language font script")
        case .devanagari:
            return NSLocalizedString("Devanagari", comment: "Language font script")
        case .thai:
            return NSLocalizedString("Thai", comment: "Language font script")
        case .symbolsAndNerdFont:
            return NSLocalizedString("Symbols & Nerd Font", comment: "Language font script")
        }
    }

    var coreTextLanguage: String? {
        switch self {
        case .chineseSimplified: return "zh-Hans"
        case .chineseTraditional: return "zh-Hant"
        case .japanese, .japaneseKana: return "ja"
        case .korean, .koreanHangul: return "ko"
        case .cyrillic: return "ru"
        case .greek: return "el"
        case .arabic: return "ar"
        case .hebrew: return "he"
        case .devanagari: return "hi"
        case .thai: return "th"
        case .symbolsAndNerdFont: return nil
        }
    }

    private static let hanRanges: [ClosedRange<Int>] = [
        0x2E80...0x2FDF,   // CJK Radicals Supplement & Kangxi Radicals
        0x3000...0x303F,   // CJK Symbols and Punctuation
        0x31C0...0x31EF,   // CJK Strokes
        0x3200...0x33FF,   // Enclosed CJK Letters and Months & CJK Compatibility
        0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
        0x4E00...0x9FFF,   // CJK Unified Ideographs
        0xF900...0xFAFF,   // CJK Compatibility Ideographs
        0xFE30...0xFE4F,   // CJK Compatibility Forms
        0xFF01...0xFF60,   // Fullwidth ASCII variants & punctuation
        0xFFE0...0xFFE6,   // Fullwidth symbol variants
        0x20000...0x2EE5F, // CJK Unified Ideographs Extensions B, C, D, E, F, I
        0x2F800...0x2FA1F, // CJK Compatibility Ideographs Supplement
        0x30000...0x323AF  // CJK Unified Ideographs Extensions G, H
    ]

    private static let kanaRanges: [ClosedRange<Int>] = [
        0x3040...0x30FF,   // Hiragana & Katakana
        0x31F0...0x31FF,   // Katakana Phonetic Extensions
        0xFF65...0xFF9F,   // Halfwidth Katakana
        0x1B000...0x1B16F  // Kana Supplement, Kana Extended-A, Small Kana Extension
    ]

    private static let hangulRanges: [ClosedRange<Int>] = [
        0x1100...0x11FF,   // Hangul Jamo
        0x3130...0x318F,   // Hangul Compatibility Jamo
        0xA960...0xA97F,   // Hangul Jamo Extended-A
        0xAC00...0xD7AF,   // Hangul Syllables
        0xD7B0...0xD7FF,   // Hangul Jamo Extended-B
        0xFFA0...0xFFDC    // Halfwidth Hangul
    ]

    private var ranges: [ClosedRange<Int>] {
        switch self {
        case .chineseSimplified:
            return Self.hanRanges
        case .chineseTraditional:
            return Self.hanRanges + [0x3100...0x312F, 0x31A0...0x31BF] // + Bopomofo
        case .japanese:
            return Self.kanaRanges + Self.hanRanges
        case .japaneseKana:
            return Self.kanaRanges
        case .korean:
            return Self.hangulRanges + Self.hanRanges
        case .koreanHangul:
            return Self.hangulRanges
        case .cyrillic:
            return [0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F]
        case .greek:
            return [0x0370...0x03FF, 0x1F00...0x1FFF]
        case .arabic:
            return [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF]
        case .hebrew:
            return [0x0590...0x05FF, 0xFB1D...0xFB4F]
        case .devanagari:
            return [0x0900...0x097F, 0xA8E0...0xA8FF]
        case .thai:
            return [0x0E00...0x0E7F]
        case .symbolsAndNerdFont:
            return [
                0x2190...0x23FF,     // Arrows, Math Operators, Misc Technical
                0x25A0...0x27BF,     // Geometric Shapes, Misc Symbols, Dingbats (excludes 2500..259F Box Drawing)
                0x2B00...0x2BFF,     // Misc Symbols and Arrows
                0xE000...0xF8FF,     // BMP Private Use Area (Powerline, Nerd Fonts, Devicons)
                0xF0000...0xFFFFD,   // Supplementary Private Use Area-A (Material Design Icons)
                0x100000...0x10FFFD  // Supplementary Private Use Area-B
            ]
        }
    }

    private static let cachedCodePointSets: [FontLanguageScript: IndexSet] = {
        var dict = [FontLanguageScript: IndexSet]()
        for script in FontLanguageScript.allCases {
            var set = IndexSet()
            for r in script.ranges {
                set.insert(integersIn: r)
            }
            dict[script] = set
        }
        return dict
    }()

    var codePointSet: IndexSet {
        Self.cachedCodePointSets[self] ?? IndexSet()
    }

    func preferredDefaultFontFamily(availableFamilies: [String]) -> String {
        let candidates: [String]
        switch self {
        case .chineseSimplified:
            candidates = ["PingFang SC", "Heiti SC", "STHeiti"]
        case .chineseTraditional:
            candidates = ["PingFang TC", "Heiti TC", "STHeiti"]
        case .japanese, .japaneseKana:
            candidates = ["Hiragino Sans", "Hiragino Kaku Gothic ProN"]
        case .korean, .koreanHangul:
            candidates = ["Apple SD Gothic Neo", "AppleGothic"]
        case .cyrillic, .greek:
            candidates = ["SF Mono", "Menlo", "Helvetica Neue"]
        case .arabic:
            candidates = ["Geeza Pro", "SF Arabic", "Arial"]
        case .hebrew:
            candidates = ["Arial Hebrew", "SF Hebrew", "Helvetica Neue"]
        case .devanagari:
            candidates = ["Kohinoor Devanagari", "Devanagari Sangam MN"]
        case .thai:
            candidates = ["Thonburi", "Ayuthaya"]
        case .symbolsAndNerdFont:
            if let nerd = availableFamilies.first(where: { $0.localizedCaseInsensitiveContains("Symbols Nerd Font") }) ??
                availableFamilies.first(where: { $0.localizedCaseInsensitiveContains("Nerd Font") }) {
                return nerd
            }
            candidates = ["Apple Symbols", "Menlo"]
        }
        let familySet = Set(availableFamilies)
        for c in candidates where familySet.contains(c) {
            return c
        }
        return availableFamilies.first ?? "Menlo"
    }
}

@objc
protocol FontProviderProtocol {
    @objc
    func fontForCharacter(_ char: UTF32Char,
                          useBoldFont: Bool,
                          useItalicFont: Bool,
                          renderBold: UnsafeMutablePointer<ObjCBool>,
                          renderItalic: UnsafeMutablePointer<ObjCBool>,
                          remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo

    func cloneFontProvider() -> FontProviderProtocol
}

// It is very important that this class always remain immutable.
// It is accessed from the Metal thread and the main thread.
@objc(iTermFontTable)
class FontTable: NSObject, FontProviderProtocol {
    @objc static let unicodeLimit = 0x110000
    private let rangeMap: RangeMap<FontBox>

    private class FontBox: NSObject {
        let delta: Int?
        var font: PTYFontInfo {
            didSet {
                font.boldVersion = font.computedBoldVersion()
                font.italicVersion = font.computedItalicVersion()
                font.boldItalicVersion = font.computedBoldItalicVersion()
            }
        }

        static var defaultFont: PTYFontInfo {
            return PTYFontInfo(font: NSFont.userFixedPitchFont(ofSize: 0)!)
        }

        required init(dictionary dict: [AnyHashable : Any]) {
            guard let name = dict["name"] as? String,
                  let size = dict["size"] as? CGFloat else {
                font = Self.defaultFont
                delta = nil
                return
            }
            if let nsfont = NSFont(name: name, size: size) {
                font = PTYFontInfo(font: nsfont)
            } else {
                font = Self.defaultFont
            }
            delta = dict["delta"] as? Int
        }

        var shortDebugDescription: String {
            return "[FontBox \(font.font.familyName ?? "unnamed")]"
        }

        func fakeBold(italic: Bool) -> Bool {
            var fakeBold = ObjCBool(true)
            var fakeItalic = ObjCBool(italic)
            _ = PTYFontInfo.font(forAsciiCharacter: true,
                                 asciiFont: font,
                                 nonAsciiFont: nil,
                                 useBoldFont: true,
                                 useItalicFont: italic,
                                 usesNonAsciiFont: false,
                                 renderBold: &fakeBold,
                                 renderItalic: &fakeItalic)
            return fakeBold.boolValue
        }

        func fakeItalic(bold: Bool) -> Bool {
            var fakeBold = ObjCBool(bold)
            var fakeItalic = ObjCBool(true)
            _ = PTYFontInfo.font(forAsciiCharacter: true,
                                 asciiFont: font,
                                 nonAsciiFont: nil,
                                 useBoldFont: bold,
                                 useItalicFont: true,
                                 usesNonAsciiFont: false,
                                 renderBold: &fakeBold,
                                 renderItalic: &fakeItalic)
            return fakeItalic.boolValue
        }

        func dictionaryValue() -> [AnyHashable : Any] {
            var dict: [AnyHashable : Any] = [ "name": font.font.familyName!, "size": font.font.pointSize ]
            if let delta {
                dict["delta"] = delta
            }
            return dict
        }

        func copyOf() -> Self {
            return FontBox(font, delta: delta) as! Self
        }

        init(_ font: PTYFontInfo, delta: Int?) {
            self.font = font
            self.delta = delta
        }
    }

    @objc
    let asciiFont: PTYFontInfo

    @objc
    let defaultNonASCIIFont: PTYFontInfo?

    @objc
    let anyASCIIDefaultLigatures: Bool

    @objc
    let anyNonASCIIDefaultLigatures: Bool

    @objc
    var fontForCharacterSizeCalculations: NSFont {
        return asciiFont.font
    }

    @objc
    override convenience init() {
        self.init(defaultFont: FontBox.defaultFont, nonAsciiFont: nil, config: nil)
    }

    struct Entry: Codable, Equatable, Hashable {
        // Start code point in `fontName`
        var start: Int
        // Length of run to remap
        var count: Int
        // If set, remap code points in destination..<(destination+count) to start..<(start+count)
        var destination: Int?
        var fontName: String
        var pointSize: CGFloat?

        // Add delta to a "real" code point to get its code point in the special-exception font.
        var delta: Int? {
            guard let destination else {
                return nil
            }
            return start - destination
        }

        // Range after remapping. These are the code points seen as input from the tty.
        var range: Range<Int> {
            if let delta {
                return (start - delta)..<(start - delta + count)
            }
            return start..<(start + count)
        }

        func font(defaultPointSize: CGFloat) -> PTYFontInfo {
            if let font = NSFont(name: fontName, size: pointSize ?? defaultPointSize) {
                return PTYFontInfo(font: font)
            }
            return PTYFontInfo(font: NSFont.monospacedSystemFont(ofSize: defaultPointSize, weight: .regular))
        }

        func byAddingPointSize(_ growth: CGFloat) -> Entry {
            if let pointSize {
                return Entry(start: start,
                             count: count,
                             destination: destination,
                             fontName: fontName,
                             pointSize: min(200, max(2, pointSize + growth)))
            } else {
                return self
            }
        }
    }

    struct LanguageRule: Codable, Equatable, Hashable {
        var script: FontLanguageScript
        var fontName: String
        var scalePercent: Int = 100
        var baselineOffset: CGFloat = 0
        var enabled: Bool = true

        func fontInfo(defaultPointSize: CGFloat) -> PTYFontInfo {
            let scaledSize = min(200, max(2, round(defaultPointSize * CGFloat(scalePercent) / 100.0 * 2.0) / 2.0))
            let resolvedFont = NSFont(name: fontName, size: scaledSize) ??
                NSFontManager.shared.font(withFamily: fontName, traits: [], weight: 5, size: scaledSize) ??
                NSFont.monospacedSystemFont(ofSize: scaledSize, weight: .regular)
            let info = PTYFontInfo(font: resolvedFont)
            info.languageCode = script.coreTextLanguage
            info.customBaselineOffset = baselineOffset
            info.boldVersion = info.computedBoldVersion()
            info.italicVersion = info.computedItalicVersion()
            info.boldItalicVersion = info.computedBoldItalicVersion()
            return info
        }
    }

    struct Config: Codable, Equatable, Hashable {
        static let latestKnownVersion = 3
        var entries: [Entry]
        var languageRules: [LanguageRule]
        var version: Int

        private enum CodingKeys: String, CodingKey {
            case entries
            case languageRules
            case version
        }

        init(entries: [Entry], languageRules: [LanguageRule] = []) {
            self.entries = entries
            self.languageRules = languageRules
            self.version = languageRules.isEmpty ? 2 : Self.latestKnownVersion
            sortEntries()
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(Int.self, forKey: .version)
            self.entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            self.languageRules = try container.decodeIfPresent([LanguageRule].self, forKey: .languageRules) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            let encodedVersion = languageRules.isEmpty ? min(version, 2) : Self.latestKnownVersion
            try container.encode(max(1, encodedVersion), forKey: .version)
            try container.encode(entries, forKey: .entries)
            if !languageRules.isEmpty {
                try container.encode(languageRules, forKey: .languageRules)
            }
        }

        init?(string: String) {
            guard !string.isEmpty else {
                return nil
            }
            let decoder = JSONDecoder()
            do {
                self = try decoder.decode(Config.self, from: string.data(using: .utf8)!)
            } catch {
                return nil
            }
            guard version > 0, version <= Self.latestKnownVersion, hasValidEntries else {
                return nil
            }
            sortEntries()
        }

        var isEmpty: Bool {
            entries.isEmpty && languageRules.isEmpty
        }

        // Imported profiles and exception files are untrusted input. Validate
        // before forming Swift ranges or populating the renderer's range map.
        private var hasValidEntries: Bool {
            var assigned = IndexSet()
            for entry in entries {
                guard entry.start >= 0, entry.start < FontTable.unicodeLimit,
                      entry.count > 0, entry.count <= FontTable.unicodeLimit - entry.start,
                      !entry.fontName.isEmpty else {
                    return false
                }
                let inputStart = entry.destination ?? entry.start
                guard inputStart >= 0, inputStart < FontTable.unicodeLimit,
                      entry.count <= FontTable.unicodeLimit - inputStart else {
                    return false
                }
                if let size = entry.pointSize, !size.isFinite || size <= 0 {
                    return false
                }
                let range = inputStart..<(inputStart + entry.count)
                guard !assigned.intersects(integersIn: range) else { return false }
                assigned.insert(integersIn: range)
            }
            for rule in languageRules {
                guard !rule.fontName.isEmpty,
                      (50...200).contains(rule.scalePercent),
                      rule.baselineOffset.isFinite,
                      abs(rule.baselineOffset) <= 20 else {
                    return false
                }
            }
            return true
        }

        private mutating func sortEntries() {
            entries.sort { lhs, rhs in
                lhs.closedRange.lowerBound < rhs.closedRange.lowerBound
            }
        }

        func byAddingPointSize(_ delta: CGFloat) -> Config {
            return Config(entries: entries.map { $0.byAddingPointSize(delta) },
                          languageRules: languageRules)
        }

        var stringValue: String {
            let encoder = JSONEncoder()
            let data = try! encoder.encode(self)
            return String(data: data, encoding: .utf8)!
        }

        static func makeTuple(_ configString: String?) -> (String, Config)? {
            guard let configString,
                  let parsed = Config(string: configString) else {
                return nil
            }
            return (configString, parsed)
        }
    }

    private let config: Config?
    @objc let configString: String?

    @objc let configHash: String

    @objc
    convenience init(defaultFont: PTYFontInfo,
                     nonAsciiFont: PTYFontInfo?,
                     configString: String?) {
        self.init(defaultFont: defaultFont,
                  nonAsciiFont: nonAsciiFont,
                  config: Config.makeTuple(configString))
    }

    private init(defaultFont: PTYFontInfo,
                 nonAsciiFont: PTYFontInfo?,
                 config tuple: (String, Config)?) {
        defaultFont.boldVersion = defaultFont.computedBoldVersion()
        defaultFont.italicVersion = defaultFont.computedItalicVersion()
        defaultFont.boldItalicVersion = defaultFont.computedBoldItalicVersion()

        if let nonAsciiFont {
            nonAsciiFont.boldVersion = nonAsciiFont.computedBoldVersion()
            nonAsciiFont.italicVersion = nonAsciiFont.computedItalicVersion()
            nonAsciiFont.boldItalicVersion = nonAsciiFont.computedBoldItalicVersion()
        }

        if let tuple {
            configString = tuple.0
            config = tuple.1
            configHash = String(tuple.1.hashValue)
        } else {
            configString = nil
            config = nil
            configHash = ""
        }
        asciiFont = defaultFont

        // Max number of code points
        let asciiLimit = 128
        var unassignedCodePoints = IndexSet(integersIn: 0..<FontTable.unicodeLimit)
        var rangeMap = RangeMap<FontBox>()
        if let config {
            for entry in config.entries {
                let font = entry.font(defaultPointSize: defaultFont.font.pointSize)
                font.boldVersion = font.computedBoldVersion()
                font.italicVersion = font.computedItalicVersion()
                font.boldItalicVersion = font.computedBoldItalicVersion()
                rangeMap.insert(range: entry.range,
                                value: FontBox(font, delta: entry.delta))
                unassignedCodePoints.remove(integersIn: entry.range)
            }
            for rule in config.languageRules where rule.enabled {
                let effectivePoints = rule.script.codePointSet
                    .intersection(unassignedCodePoints)
                    .intersection(IndexSet(integersIn: asciiLimit..<FontTable.unicodeLimit))
                guard !effectivePoints.isEmpty else { continue }
                let box = FontBox(rule.fontInfo(defaultPointSize: defaultFont.font.pointSize), delta: nil)
                for range in effectivePoints.rangeView {
                    rangeMap.insert(range: range, value: box)
                }
                unassignedCodePoints.subtract(effectivePoints)
            }
        }
        defaultNonASCIIFont = nonAsciiFont ?? defaultFont

        for range in unassignedCodePoints.rangeView {
            let asciiRange = range.clamped(to: 0..<asciiLimit)
            if !asciiRange.isEmpty {
                rangeMap.insert(range: asciiRange,
                                value: FontBox(defaultFont, delta: nil))
            }
            let nonASCIIRange = range.clamped(to: asciiLimit..<FontTable.unicodeLimit)
            if !nonASCIIRange.isEmpty {
                rangeMap.insert(range: nonASCIIRange,
                                value: FontBox(nonAsciiFont ?? defaultFont,
                                               delta: nil))
            }
        }
        anyASCIIDefaultLigatures = Self.rangeMapHasLigatures(rangeMap: rangeMap, ascii: true)
        anyNonASCIIDefaultLigatures = Self.rangeMapHasLigatures(rangeMap: rangeMap, ascii: false)

        self.rangeMap = rangeMap
        super.init()
    }

    private static func rangeMapHasLigatures(rangeMap: RangeMap<FontBox>, ascii: Bool) -> Bool {
        let iterator = ascii ? rangeMap.reverseIterate(from: 127) : rangeMap.iterate(from: 128)
        for entry in iterator {
            if entry.value.font.hasDefaultLigatures {
                return true
            }
        }
        return false
    }

    @objc var fontProvider: FontProviderProtocol {
        if rangeMap.count == 1,
           let box = rangeMap.first?.value {
            return box.font;
        }
        if rangeMap.count == 2,
           let first = rangeMap.first,
           first.range == 0..<128,
           let last = rangeMap.last,
           last.range.lowerBound == 128 {
            if first.value.font == last.value.font {
                return first.value.font
            }
            return DualFontProvider(asciiFontInfo: first.value.font,
                                    nonASCIIFontInfo: last.value.font)
        }
        return self
    }
    private func font(for c: Character,
                      remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo {
        return font(for: UTF32Char(c.unicodeScalars.first!.value), remapped: remapped)
    }

    private var cachedRangeMapEntry = MutableAtomicObject<RangeMap<FontBox>.Entry?>(nil)

    @objc
    func font(for codePoint: UTF32Char,
              remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo {
        return cachedRangeMapEntry.mutableAccess { cachedRangeMapEntry in
            let fontBox: FontBox
            if let cachedRangeMapEntry, cachedRangeMapEntry.range.contains(Int(codePoint)) {
                fontBox = cachedRangeMapEntry.value
            } else {
                let entry = rangeMap[Int(codePoint)]!
                cachedRangeMapEntry = entry
                fontBox = entry.value
            }
            if let delta = fontBox.delta {
                remapped.pointee = UTF32Char(Int(codePoint) + delta)
            }
            return fontBox.font
        }
    }

    @objc
    var baselineOffset: CGFloat {
        return asciiFont.baselineOffset
    }

    @objc
    var underlineOffset: CGFloat {
        return asciiFont.underlineOffset
    }

    // use{Bold,Italic}Font: Use a different font if one is available
    // render{Bold,Italic}: On input, whether the character is {bold,italic} and on output whether it needs to be rendered as fake {bold,italic}.
    @objc
    func fontForCharacter(_ char: UTF32Char,
                          useBoldFont: Bool,
                          useItalicFont: Bool,
                          renderBold: UnsafeMutablePointer<ObjCBool>,
                          renderItalic: UnsafeMutablePointer<ObjCBool>,
                          remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo {
        return PTYFontInfo.font(forAsciiCharacter: true,
                                asciiFont: font(for: char, remapped: remapped),
                                nonAsciiFont: nil,
                                useBoldFont: useBoldFont,
                                useItalicFont: useItalicFont,
                                usesNonAsciiFont: false,
                                renderBold: renderBold,
                                renderItalic: renderItalic)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FontTable else {
            return false
        }
        if other === self {
            return true
        }
        if !other.asciiFont.font.isEqual(asciiFont.font) {
            return false
        }
        if other.config != config {
            return false
        }
        guard let otherNonASCII = other.defaultNonASCIIFont,
              let nonASCII = defaultNonASCIIFont else {
            return (other.defaultNonASCIIFont == nil) && (defaultNonASCIIFont == nil)
        }
        return otherNonASCII == nonASCII
    }

    @objc(fontTableGrownBy:)
    func fontTable(grownBy delta: CGFloat) -> FontTable {
        if delta == 0 {
            return self
        }
        let grownConfig = config?.byAddingPointSize(delta)
        return FontTable(
            defaultFont: PTYFontInfo(font: asciiFont.font.it_fontByAdding(toPointSize: delta)),
            nonAsciiFont: defaultNonASCIIFont.map {
                PTYFontInfo(font: $0.font.it_fontByAdding(toPointSize: delta))
            },
            config: grownConfig.map { ($0.stringValue, $0) })
    }

    @objc(fontTableForProfile:)
    static func fontTable(forProfile profile: [AnyHashable : Any]) -> FontTable {
        let asciiFont = iTermProfilePreferences.font(forKey: KEY_NORMAL_FONT,
                                                     inProfile: profile,
                                                     ligaturesEnabled: iTermProfilePreferences.bool(forKey: KEY_ASCII_LIGATURES,
                                                                                                    inProfile: profile)) ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let useNonASCIIFont = iTermProfilePreferences.bool(forKey: KEY_USE_NONASCII_FONT,
                                                           inProfile: profile)
        let nonASCIIFont: NSFont? = useNonASCIIFont
            ? iTermProfilePreferences.font(forKey: KEY_NON_ASCII_FONT,
                                           inProfile: profile,
                                           ligaturesEnabled: iTermProfilePreferences.bool(forKey: KEY_NON_ASCII_LIGATURES,
                                                                                          inProfile: profile))
            : nil
        let config = iTermProfilePreferences.string(forKey: KEY_FONT_CONFIG,
                                                    inProfile: profile)
        return FontTable(
            defaultFont: PTYFontInfo(font: asciiFont),
            nonAsciiFont: nonASCIIFont.map { PTYFontInfo(font: $0) },
            configString: config)
    }

    @objc
    var uniqueIdentifier: [AnyObject] {
        return [asciiFont.font,
                asciiFont.boldVersion?.font ?? NSNull(),
                asciiFont.italicVersion?.font ?? NSNull(),
                asciiFont.boldItalicVersion ?? NSNull(),

                defaultNonASCIIFont?.font ?? NSNull(),
                defaultNonASCIIFont?.boldVersion?.font ?? NSNull(),
                defaultNonASCIIFont?.italicVersion?.font ?? NSNull(),
                defaultNonASCIIFont?.boldItalicVersion?.font ?? NSNull(),

                configHash as NSString]
    }

    @objc(haveSpecialExceptionFor:orCharacter:)
    func haveSpecialException(for c1: screen_char_t, orCharacter c2: screen_char_t) -> Bool {
        guard config != nil else {
            return false
        }
        let box1 = c1.image == 0 ? rangeMap[Int(c1.baseCharacter)]?.value : nil
        let box2 = c2.image == 0 ? rangeMap[Int(c2.baseCharacter)]?.value : nil
        if box1 !== box2 {
            return true
        }
        return box1?.delta != nil || box2?.delta != nil
    }

    func cloneFontProvider() -> any FontProviderProtocol {
        return self
    }
}

extension PTYFontInfo: FontProviderProtocol {
    @objc
    func fontForCharacter(_ char: UTF32Char,
                          useBoldFont: Bool,
                          useItalicFont: Bool,
                          renderBold: UnsafeMutablePointer<ObjCBool>,
                          renderItalic: UnsafeMutablePointer<ObjCBool>,
                          remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo {
        return PTYFontInfo.font(forAsciiCharacter: true,
                                asciiFont: self,
                                nonAsciiFont: nil,
                                useBoldFont: useBoldFont,
                                useItalicFont: useItalicFont,
                                usesNonAsciiFont: false,
                                renderBold: renderBold,
                                renderItalic: renderItalic)
    }
    func cloneFontProvider() -> any FontProviderProtocol {
        return self
    }
}

@objc
class DualFontProvider: NSObject, FontProviderProtocol {
    private let asciiFontInfo: PTYFontInfo
    private let nonASCIIFontInfo: PTYFontInfo

    init(asciiFontInfo: PTYFontInfo,
         nonASCIIFontInfo: PTYFontInfo) {
        self.asciiFontInfo = asciiFontInfo
        self.nonASCIIFontInfo = nonASCIIFontInfo
    }

    @objc
    func fontForCharacter(_ char: UTF32Char,
                          useBoldFont: Bool,
                          useItalicFont: Bool,
                          renderBold: UnsafeMutablePointer<ObjCBool>,
                          renderItalic: UnsafeMutablePointer<ObjCBool>,
                          remapped: UnsafeMutablePointer<UTF32Char>) -> PTYFontInfo {
        return PTYFontInfo.font(forAsciiCharacter: char < 128,
                                asciiFont: asciiFontInfo,
                                nonAsciiFont: nonASCIIFontInfo,
                                useBoldFont: useBoldFont,
                                useItalicFont: useItalicFont,
                                usesNonAsciiFont: true,
                                renderBold: renderBold,
                                renderItalic: renderItalic)
    }

    func cloneFontProvider() -> any FontProviderProtocol {
        return DualFontProvider(asciiFontInfo: asciiFontInfo.copy() as! PTYFontInfo,
                                nonASCIIFontInfo: nonASCIIFontInfo.copy() as! PTYFontInfo)
    }
}

// MARK: - PUA Font Support

extension FontTable {
    /// Returns the font for a Private Use Area code point.
    @objc
    func font(forPUACodePoint codePoint: UTF32Char) -> NSFont {
        var remapped: UTF32Char = 0
        return font(for: codePoint, remapped: &remapped).font
    }
}
