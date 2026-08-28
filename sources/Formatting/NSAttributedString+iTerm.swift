//
//  NSAttributedString+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/29/22.
//

import AppKit
import Foundation

class AttributeToControlSequenceConverter {
    private var currentCodes = [String]()

    func convert(_ string: String, attributes: [NSAttributedString.Key : Any]) -> String {
        let codes = convert(attributes)
        if codes == currentCodes {
            return string
        }
        currentCodes = codes
        return "\u{1b}[" + Array(codes).sorted().joined(separator: ";") + "m" + string
    }

    // Returns SGR codes
    private func convert(_ attributes: [NSAttributedString.Key : Any]) -> [String] {
        var c = screen_char_t()
        if let fgColor = attributes[.foregroundColor] as? NSColor,
           let srgb = fgColor.usingColorSpace(NSColorSpace.sRGB) {
            c.foregroundColorMode = ColorMode24bit.rawValue
            c.foregroundColor = UInt32(UInt8(srgb.redComponent * 255))
            c.fgGreen = UInt32(UInt8(srgb.greenComponent * 255))
            c.fgBlue = UInt32(UInt8(srgb.blueComponent * 255))
        } else {
            c.foregroundColorMode = ColorModeAlternate.rawValue
            c.foregroundColor = UInt32(ALTSEM_DEFAULT)
        }

        if let bgColor = attributes[.backgroundColor] as? NSColor,
           let srgb = bgColor.usingColorSpace(NSColorSpace.sRGB) {
            c.backgroundColorMode = ColorMode24bit.rawValue
            c.backgroundColor = UInt32(UInt8(srgb.redComponent * 255))
            c.bgGreen = UInt32(UInt8(srgb.greenComponent * 255))
            c.bgBlue = UInt32(UInt8(srgb.blueComponent * 255))
        } else {
            c.backgroundColorMode = ColorModeAlternate.rawValue
            c.backgroundColor = UInt32(ALTSEM_DEFAULT)
        }

        if let font = attributes[.font] as? NSFont {
            if NSFontManager().weight(of: font) > 5 {
                c.bold = 1
            } else {
                c.bold = 0
            }
            if font.fontDescriptor.symbolicTraits.contains(.italic) {
                c.italic = 1
            } else {
                c.italic = 0
            }
        } else {
            c.bold = 0
        }

        if let underlineStyle = attributes[.underlineStyle] as? NSUnderlineStyle {
            switch underlineStyle {
            case .single:
                c.underline = 1
                ScreenCharSetUnderlineStyle(&c, .single)
            case .double:
                c.underline = 1
                ScreenCharSetUnderlineStyle(&c, .double)
            case .patternDot:
                c.underline = 1
                ScreenCharSetUnderlineStyle(&c, .dotted)
            case .patternDash:
                c.underline = 1
                ScreenCharSetUnderlineStyle(&c, .dashed)
            case .patternDashDot, .patternDashDotDot:
                c.underline = 1
                ScreenCharSetUnderlineStyle(&c, .curly)
            default:
                c.underline = 0
            }
        } else {
            c.underline = 0
        }
        if attributes[.strikethroughStyle] != nil {
            c.strikethrough = 1
        } else {
            c.strikethrough = 0
        }

        c.inverse = 0
        if let fgColor = attributes[.foregroundColor] as? NSColor, fgColor.alphaComponent <= 0.5 {
            c.faint = 1
        } else {
            c.faint = 0
        }

        let underlineColor: VT100TerminalColorValue?
        if let unsafeColor = attributes[.underlineColor] as? NSColor,
            let srgb = unsafeColor.usingColorSpace(.sRGB) {
            underlineColor = VT100TerminalColorValue(red: Int32(UInt32(UInt8(srgb.redComponent * 255))),
                                                     green: Int32(UInt8(srgb.greenComponent * 255)),
                                                     blue: Int32(UInt8(srgb.blueComponent * 255)),
                                                     mode: ColorMode24bit,
                                                     hasDarkVariant: false,
                                                     redDark: 0,
                                                     greenDark: 0,
                                                     blueDark: 0)
        } else {
            underlineColor = nil
        }

        let url = { () -> iTermURL? in
            let href: URL? = { () -> URL? in
                if let link = attributes[.link] {
                    if let url = link as? URL {
                        return url
                    } else if let url = link as? String {
                        return URL(string: url)
                    }
                }
                return nil
            }()
            guard let href else {
                return nil
            }
            return iTermURL(url: href, identifier: nil, target: nil)
        }()
        let ea = iTermExternalAttribute(havingUnderlineColor: underlineColor != nil,
                                        underlineColor: underlineColor ?? VT100TerminalColorValue(),
                                        url: url,
                                        blockIDList: nil,
                                        controlCode: nil,
                                        dualModeForeground: iTermDualModeColor(),
                                        dualModeBackground: iTermDualModeColor())
        return VT100Terminal.sgrCodes(forCharacter: c, externalAttributes: ea).array as! [String]
    }
}

extension NSAttributedString {
    var asStringWithControlSequences: String {
        let string = self.string as NSString
        var result = ""
        let converter = AttributeToControlSequenceConverter()
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, stop in
            result.append(converter.convert(string.substring(with: range), attributes: attributes))
        }
        return result
    }

    @objc
    func mapAttributes(_ transform: ([NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString: self)

        let range = NSRange(location: 0, length: length)
        mutableAttributedString.enumerateAttributes(in: range, options: []) { (attributes, range, _) in
            let newAttributes = transform(attributes)
            mutableAttributedString.setAttributes(newAttributes, range: range)
        }

        return NSAttributedString(attributedString: mutableAttributedString)
    }

    @objc(attributedStringWithMarkdown:font:paragraphStyle:)
    class func attributedString(markdown: String, font: NSFont, paragraphStyle: NSParagraphStyle) -> NSAttributedString? {
        return iTerm_attributedString(markdown: markdown,
                                      baseFont: font,
                                      textColor: .textColor,
                                      paragraphStyle: paragraphStyle,
                                      headingScales: [2, 1.5, 1.3, 1, 0.8, 0.7])
    }

    static func iTerm_attributedString(markdown: String,
                                       baseFont: NSFont,
                                       textColor: NSColor,
                                       paragraphStyle: NSParagraphStyle = .default,
                                       headingScales: [CGFloat] = [2, 1.5, 1.3, 1, 0.8, 0.7],
                                       codeFont: NSFont? = nil) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        let body = markdownBodyWithoutFrontMatter(markdown)
        guard let parsed = try? AttributedString(markdown: body, options: options) else {
            return NSAttributedString(string: body,
                                      attributes: [.font: baseFont,
                                                   .foregroundColor: textColor,
                                                   .paragraphStyle: paragraphStyle])
        }

        let result = NSMutableAttributedString()
        var previousBlockIdentity: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let blockIdentity = components.first?.identity
            if blockIdentity != previousBlockIdentity {
                appendMarkdownBlockSeparator(to: result,
                                             presentationIntent: run.presentationIntent,
                                             baseFont: baseFont,
                                             textColor: textColor,
                                             paragraphStyle: paragraphStyle)
                previousBlockIdentity = blockIdentity
            }

            let inlineIntent = run.inlinePresentationIntent ?? []
            let isCodeBlock = components.contains { component in
                if case .codeBlock = component.kind {
                    return true
                }
                return false
            }
            let headingLevel = components.compactMap { component -> Int? in
                if case .header(let level) = component.kind {
                    return level
                }
                return nil
            }.first
            let pointSize: CGFloat
            if let headingLevel,
               headingScales.indices.contains(headingLevel - 1) {
                pointSize = max(4, round(baseFont.pointSize * headingScales[headingLevel - 1]))
            } else {
                pointSize = baseFont.pointSize
            }

            let bold = headingLevel != nil || inlineIntent.contains(.stronglyEmphasized)
            let italic = inlineIntent.contains(.emphasized)
            let code = isCodeBlock || inlineIntent.contains(.code)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: markdownFont(baseFont: baseFont,
                                    pointSize: pointSize,
                                    bold: bold,
                                    italic: italic,
                                    monospaced: code,
                                    codeFont: codeFont),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
            ]
            if inlineIntent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            var string = String(parsed.characters[run.range])
            if inlineIntent.contains(.code) {
                string = string.unicodeScalars.enumerated().map { index, scalar in
                    return index == 0 ? String(scalar) : "\u{feff}" + String(scalar)
                }.joined()
            }
            result.append(NSAttributedString(string: string, attributes: attributes))
        }
        return result
    }

    private static func markdownBodyWithoutFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n"),
              let closingRange = markdown.range(of: "\n---\n",
                                                range: markdown.index(markdown.startIndex,
                                                                      offsetBy: 3)..<markdown.endIndex) else {
            return markdown
        }
        return String(markdown[closingRange.upperBound...])
    }

    private static func appendMarkdownBlockSeparator(
        to result: NSMutableAttributedString,
        presentationIntent: PresentationIntent?,
        baseFont: NSFont,
        textColor: NSColor,
        paragraphStyle: NSParagraphStyle
    ) {
        let components = presentationIntent?.components ?? []
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }

        var listOrdinal: Int?
        var unordered = false
        var blockQuote = false
        for component in components {
            switch component.kind {
            case .listItem(let ordinal):
                listOrdinal = ordinal
            case .unorderedList:
                unordered = true
            case .blockQuote:
                blockQuote = true
            default:
                break
            }
        }
        if let listOrdinal {
            let prefix = unordered ? "• " : "\(listOrdinal). "
            result.append(NSAttributedString(string: prefix, attributes: attributes))
        } else if blockQuote {
            result.append(NSAttributedString(string: "› ", attributes: attributes))
        }
    }

    private static func markdownFont(baseFont: NSFont,
                                     pointSize: CGFloat,
                                     bold: Bool,
                                     italic: Bool,
                                     monospaced: Bool,
                                     codeFont: NSFont?) -> NSFont {
        let manager = NSFontManager.shared
        var font: NSFont
        if monospaced {
            let base = codeFont ?? NSFont.monospacedSystemFont(ofSize: pointSize, weight: .bold)
            font = manager.convert(base, toSize: pointSize)
        } else {
            font = manager.convert(baseFont, toSize: pointSize)
        }
        var traits = NSFontTraitMask()
        if bold {
            traits.insert(.boldFontMask)
        }
        if italic {
            traits.insert(.italicFontMask)
        }
        if !traits.isEmpty {
            font = manager.convert(font, toHaveTrait: traits)
        }
        return font
    }

    // The HTML parser built in to NSAttributedString is unusable because it sets an sRGB color for
    // the default text color, breaking light/dark mode. I <3 AppKit
    @objc(attributedStringWithHTML:font:paragraphStyle:)
    class func attributedString(html htmlString: String, font: NSFont, paragraphStyle: NSParagraphStyle) -> NSAttributedString? {
        let attributedString = NSMutableAttributedString(string: "")
        attributedString.addAttributes([.font: font, .paragraphStyle: paragraphStyle], range: NSRange(location: 0, length: 0))

        var currentIndex = htmlString.startIndex

        while currentIndex < htmlString.endIndex {
            if htmlString[currentIndex] == "<", let endIndex = htmlString[currentIndex...].range(of: ">")?.upperBound, let tagRange = htmlString[currentIndex..<endIndex].range(of: "<a href=\""), tagRange.lowerBound == currentIndex {
                let urlStart = htmlString.index(tagRange.upperBound, offsetBy: 0)
                let urlEnd = htmlString[urlStart...].firstIndex(of: "\"") ?? htmlString.endIndex
                let url = String(htmlString[urlStart..<urlEnd])

                let textStart = htmlString.index(urlEnd, offsetBy: 2)
                let textEnd = htmlString[textStart...].range(of: "</a>")?.lowerBound ?? htmlString.endIndex

                let text = String(htmlString[textStart..<textEnd])

                let linkAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                    .link: url,
                    .cursor: NSCursor.pointingHand
                ]

                attributedString.append(NSAttributedString(string: text, attributes: linkAttributes))
                currentIndex = htmlString.index(textEnd, offsetBy: 4)
            } else {
                let nextIndex = htmlString[currentIndex...].range(of: "<")?.lowerBound ?? htmlString.endIndex
                let text = String(htmlString[currentIndex..<nextIndex])

                attributedString.append(NSAttributedString(string: text, attributes: [.font: font,
                                                                                      .paragraphStyle: paragraphStyle,
                                                                                      .foregroundColor: NSColor.textColor]))
                currentIndex = nextIndex
            }
        }

        return attributedString
    }
}

extension Array where Element: NSAttributedString {
    func joined(separator: NSAttributedString) -> NSAttributedString {
        let combined = NSMutableAttributedString()
        for part in self {
            if part != first {
                combined.append(separator)
            }
            combined.append(part)
        }
        return combined
    }
}

extension NSMutableAttributedString {
    typealias Change = (NSRange, [NSAttributedString.Key : Any]) -> ()
    func editAttributes(_ closure: (Change) -> ()) {
        var replacements = [NSRange: [NSAttributedString.Key : Any]]()
        closure { range, newAttributes in
            replacements[range] = newAttributes
        }
        for (range, attrs) in replacements {
            setAttributes(attrs, range: range)
        }
    }
}

@objc
class iTermTableCellView: NSTableCellView {
    @objc
    var strongTextField: NSTextField? {
        didSet {
            self.textField = strongTextField
        }
    }

    func updateForegroundColor(textField: NSTextField) {
        switch backgroundStyle {
        case .normal:
            textField.attributedStringValue = textField.attributedStringValue.mapAttributes({ attrs in
                var result = attrs
                if result[.foregroundColor] as? NSColor == NSColor.selectedMenuItemTextColor {
                    result[.foregroundColor] = NSColor.textColor
                }
                return result
            })
        case .emphasized:
            textField.attributedStringValue = textField.attributedStringValue.mapAttributes({ attrs in
                var result = attrs
                if result[.foregroundColor] as? NSColor == NSColor.textColor {
                    result[.foregroundColor] = NSColor.selectedMenuItemTextColor
                }
                return result
            })
        default:
            break
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            if let textField = self.textField {
                updateForegroundColor(textField: textField)
            }
        }
    }
}

// A table cell with an optional icon and a text field next to it.
@objc(iTermIconTableCellView)
class IconTableCellView: iTermTableCellView {
    @objc var iconView = NSImageView()
    @objc var icon: NSImage? {
        get { iconView.image }
        set { iconView.image = newValue }
    }

    private var didSetupConstraints = false

    @objc(initWithIcon:color:)
    init(icon: NSImage, iconColor: NSColor) {
        super.init(frame: .zero)
        icon.isTemplate = true
        iconView.contentTintColor = iconColor
        self.icon = icon
        commonInit()
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
    }

    override func updateConstraints() {
        if !didSetupConstraints, let textField = self.textField {
            didSetupConstraints = true
            NSLayoutConstraint.activate([
                // Icon view constraints
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0),
                iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: 0),
                iconView.heightAnchor.constraint(equalToConstant: 10),
                iconView.widthAnchor.constraint(equalToConstant: 10),

                // Text field constraints
                textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0),
                textField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])
        }
        super.updateConstraints()
    }
}
