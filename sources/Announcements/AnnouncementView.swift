//
//  AnnouncementView.swift
//  iTerm2SharedARC
//
//  Migrated from iTermAnnouncementView.{h,m}.
//

import Cocoa

/// Visual style for an announcement banner.
@objc(iTermAnnouncementViewStyle)
enum iTermAnnouncementViewStyle: Int {
    case warning = 0
    case question = 1
}

/// Banner view presenting an icon, message text, action buttons, and a close button.
@objc(iTermAnnouncementView)
final class iTermAnnouncementView: NSView {
    private static let margin: CGFloat = 8
    private static let heightPadding: CGFloat = 29
    private static let topInset: CGFloat = 10

    @objc var isMarkdown = false

    @objc var title: String = "" {
        didSet {
            rebuildContentForCurrentTitle()
        }
    }

    private var style: iTermAnnouncementViewStyle = .warning
    private var buttonWidth: CGFloat = 0
    private var textView: AutoResizingTextView?
    private var iconView: NSImageView?
    private let closeButton: NSButton
    private var actionButtons: [NSView] = []
    private let internalView: SolidColorView
    private let lineView: SolidColorView
    private let visualEffectView: NSVisualEffectView
    private let shadowView: ShadowView
    private var block: ((Int32) -> Void)?

    @objc(announcementFont)
    static func announcementFont() -> NSFont {
        NSFont.systemFont(ofSize: 12)
    }

    @objc(estimatedHeightForWidth:text:)
    static func estimatedHeight(forWidth width: CGFloat, text: String) -> CGFloat {
        let minHeight = measureHeight("x", width: width)
        let maxHeight = measureHeight("x\nx\nx", width: width)
        let textHeight = measureHeight(text, width: width)
        let clampedHeight = max(minHeight, min(textHeight, maxHeight))
        return clampedHeight + heightPadding
    }

    @objc(announcementViewWithTitle:style:actions:block:)
    static func announcementView(withTitle title: String,
                                 style: iTermAnnouncementViewStyle,
                                 actions: [String],
                                 block: @escaping (Int32) -> Void) -> iTermAnnouncementView {
        makeView(title: title, isMarkdown: false, style: style, actions: actions, block: block)
    }

    @objc(announcementViewWithMarkdownTitle:style:actions:block:)
    static func announcementView(withMarkdownTitle title: String,
                                 style: iTermAnnouncementViewStyle,
                                 actions: [String],
                                 block: @escaping (Int32) -> Void) -> iTermAnnouncementView {
        makeView(title: title, isMarkdown: true, style: style, actions: actions, block: block)
    }

    private static func makeView(title: String,
                                 isMarkdown: Bool,
                                 style: iTermAnnouncementViewStyle,
                                 actions: [String],
                                 block: @escaping (Int32) -> Void) -> iTermAnnouncementView {
        let view = iTermAnnouncementView(frame: NSRect(x: 0, y: 0, width: 1000, height: 44))
        view.style = style
        view.isMarkdown = isMarkdown
        view.createButtons(from: actions, block: block)
        view.title = title
        return view
    }

    override init(frame frameRect: NSRect) {
        var contentRect = frameRect
        contentRect.size.height -= Self.topInset
        contentRect.origin.y = Self.topInset
        contentRect.origin.x = 0

        shadowView = ShadowView(frame: contentRect)
        shadowView.nsShadow.shadowOffset = .zero
        shadowView.nsShadow.shadowBlurRadius = 4
        shadowView.nsShadow.shadowColor = NSColor.black.withAlphaComponent(0.1)
        shadowView.inset = 0
        shadowView.cornerRadius = 0

        visualEffectView = NSVisualEffectView(frame: contentRect)
        visualEffectView.material = .menu
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.isEmphasized = false
        visualEffectView.autoresizingMask = [.width, .height]

        internalView = SolidColorView(
            frame: contentRect,
            color: NSColor.it_dynamicColor(
                forLightMode: NSColor(srgbRed: 1, green: 1, blue: 0.9, alpha: 0.6),
                darkMode: NSColor(srgbRed: 0.25, green: 0.25, blue: 0.1, alpha: 0.15)))
        internalView.autoresizingMask = [.width, .maxYMargin]

        let lineFrame = NSRect(x: 0, y: contentRect.minY, width: contentRect.width, height: 1)
        lineView = SolidColorView(
            frame: lineFrame,
            color: NSColor.it_dynamicColor(
                forLightMode: NSColor(white: 0.8, alpha: 1.0),
                darkMode: NSColor(white: 0.2, alpha: 1.0)))

        let closeImage = NSImage.it_imageNamed("closebutton", for: iTermAnnouncementView.self)
        let closeSize = closeImage?.size ?? NSSize(width: 16, height: 16)
        buttonWidth = ceil(closeSize.width + Self.margin)
        closeButton = NSButton(frame: NSRect(
            x: contentRect.width - buttonWidth,
            y: floor((contentRect.height - closeSize.height) / 2),
            width: closeSize.width,
            height: closeSize.height))
        closeButton.autoresizingMask = [.minXMargin]
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.image = closeImage
        closeButton.isBordered = false
        (closeButton.cell as? NSButtonCell)?.highlightsBy = .contentsCellMask
        closeButton.title = ""

        super.init(frame: frameRect)

        closeButton.target = self
        closeButton.action = #selector(close(_:))

        addSubview(shadowView)
        addSubview(visualEffectView)
        addSubview(internalView)
        addSubview(lineView)
        internalView.addSubview(closeButton)
        autoresizesSubviews = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions & Lifecycle

    @objc func willDismiss() {
        block = nil
    }

    @objc(selectIndex:)
    func select(index: Int) {
        DLog("selectIndex:\(index)")
        block?(Int32(index))
    }

    @objc func addDismissOnKeyDownLabel() {
        guard let textView else {
            return
        }
        let base = textView.originalAttributedString ?? textView.attributedString()
        let updated = NSMutableAttributedString(attributedString: base)
        let notice = NSAttributedString(
            string: "\nPress any key to dismiss this message.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.textColor,
            ])
        updated.append(notice)
        textView.textStorage?.setAttributedString(updated)
        textView.originalAttributedString = updated
    }

    @objc func sizeToFit() {
        updateTextViewFrame()
        guard let textView else {
            return
        }
        var newFrame = frame
        newFrame.size.height = textView.frame.height + Self.heightPadding
        frame = newFrame
    }

    @objc private func close(_ sender: Any?) {
        block?(-1)
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        DLog("Button with tag \(sender.tag) pressed in view \(self)")
        block?(Int32(sender.tag))
    }

    @objc private func pullDownItemSelected(_ sender: NSPopUpButton) {
        block?(Int32(sender.selectedTag()))
    }

    // MARK: - NSView Overrides

    override func updateTrackingAreas() {
        guard window != nil else {
            return
        }
        for existing in trackingAreas {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: internalView.frame,
            options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        var contentRect = bounds
        contentRect.size.height -= Self.topInset
        contentRect.origin.y = Self.topInset
        contentRect.origin.x = 0
        visualEffectView.frame = contentRect
        internalView.frame = contentRect
        lineView.frame = NSRect(x: 0, y: contentRect.minY, width: contentRect.width, height: 1)
        shadowView.frame = contentRect

        updateTextViewFrame()

        let closeSize = closeButton.frame.size
        closeButton.frame = NSRect(
            x: frame.width - closeSize.width - Self.margin,
            y: floor((internalView.frame.height - closeSize.height) / 2),
            width: closeSize.width,
            height: closeSize.height)

        for button in actionButtons {
            let buttonFrame = button.frame
            button.frame = NSRect(
                x: buttonFrame.origin.x,
                y: floor((internalView.frame.height - buttonFrame.height) / 2),
                width: buttonFrame.width,
                height: buttonFrame.height)
        }

        if let iconView {
            let iconSize = iconView.frame.size
            let y = floor((internalView.frame.height - iconSize.height) / 2)
            iconView.frame = NSRect(x: Self.margin, y: y, width: iconSize.width, height: iconSize.height)
        }
    }

    // MARK: - Private Helpers

    private func createButtons(from actions: [String], block: @escaping (Int32) -> Void) {
        self.block = block
        let rect = internalView.frame
        let shouldCreatePopup = actions.count > 2

        if shouldCreatePopup {
            let pullDown = NSPopUpButton(frame: .zero, pullsDown: true)
            pullDown.autoresizingMask = [.minXMargin]
            pullDown.bezelStyle = .texturedRounded
            pullDown.target = self
            pullDown.action = #selector(pullDownItemSelected(_:))
            internalView.addSubview(pullDown)
            pullDown.addItem(withTitle: "More Actions…")
            for index in 1..<actions.count {
                pullDown.addItem(withTitle: stringByAddingShortcut(in: actions[index]))
                pullDown.itemArray.last?.tag = index
            }
            pullDown.sizeToFit()
            buttonWidth += pullDown.frame.width + Self.margin
            pullDown.frame = NSRect(
                x: rect.width - buttonWidth,
                y: floor((rect.height - pullDown.frame.height) / 2),
                width: pullDown.frame.width,
                height: pullDown.frame.height)
            actionButtons.append(pullDown)
        }

        let buttonIndices: [Int] = shouldCreatePopup
            ? (actions.isEmpty ? [] : [0])
            : Array(actions.indices.reversed())
        for index in buttonIndices {
            let button = NSButton()
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(buttonPressed(_:))
            button.tag = index
            button.title = stringByAddingShortcut(in: actions[index])
            button.bezelStyle = .texturedRounded
            button.sizeToFit()
            button.autoresizingMask = [.minXMargin]
            buttonWidth += Self.margin + button.frame.width
            button.frame = NSRect(
                x: rect.width - buttonWidth,
                y: floor((rect.height - button.frame.height) / 2),
                width: button.frame.width,
                height: button.frame.height)
            actionButtons.append(button)
            internalView.addSubview(button)
        }
    }

    private func stringByAddingShortcut(in original: String) -> String {
        guard let underscoreIndex = original.firstIndex(of: "_") else {
            return original
        }
        let nextIndex = original.index(after: underscoreIndex)
        guard nextIndex < original.endIndex else {
            return original
        }
        let shortcut = original[nextIndex]
        var cleaned = original
        cleaned.remove(at: underscoreIndex)
        return "\(cleaned) (⌥\(shortcut))"
    }

    private func iconImage() -> NSImage? {
        let symbolName: String
        let description: String
        switch style {
        case .warning:
            symbolName = SFSymbol.exclamationmarkTriangle.rawValue
            description = "Warning icon"
        case .question:
            symbolName = SFSymbol.questionmarkCircle.rawValue
            description = "Question icon"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private func rebuildContentForCurrentTitle() {
        let image = iconImage()
        let iconSize = image?.size ?? .zero
        let iconY = floor((internalView.frame.height - iconSize.height) / 2)

        iconView?.removeFromSuperview()
        let newIcon = NSImageView(frame: NSRect(x: Self.margin, y: iconY, width: iconSize.width, height: iconSize.height))
        newIcon.image = image
        internalView.addSubview(newIcon)
        iconView = newIcon

        var rect = internalView.frame
        rect.origin.x += Self.margin + newIcon.frame.width + newIcon.frame.origin.x
        rect.size.width -= rect.origin.x + buttonWidth

        let newTextView = AutoResizingTextView(frame: rect)
        let font = Self.announcementFont()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
        ]
        let attributedString: NSAttributedString
        if isMarkdown {
            attributedString = NSAttributedString.iTerm_attributedString(
                markdown: title,
                baseFont: font,
                textColor: .textColor,
                paragraphStyle: .default)
        } else {
            attributedString = NSAttributedString(string: title, attributes: attributes)
        }
        newTextView.textStorage?.setAttributedString(attributedString)
        newTextView.isEditable = false
        newTextView.autoresizingMask = [.width, .maxXMargin]
        newTextView.drawsBackground = false
        newTextView.isSelectable = false

        textView?.removeFromSuperview()
        textView = newTextView

        let height = min(
            Self.measureHeight(title, width: rect.width),
            maximumHeight(forWidth: rect.width))
        newTextView.frame = NSRect(
            x: rect.origin.x,
            y: floor((internalView.frame.height - height) / 2),
            width: rect.width,
            height: height)
        updateTextViewFrame()

        internalView.addSubview(newTextView)
        newTextView.toolTip = title
        newTextView.enableAutoResizing = true
        newTextView.adjustFontSizes()
    }

    private static func measureHeight(_ text: String, width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: announcementFont()]
        return (text as NSString).height(attributes: attributes, constrainedToWidth: width)
    }

    private func maximumHeight(forWidth width: CGFloat) -> CGFloat {
        Self.measureHeight("x\nx\nx", width: width)
    }

    private func minimumHeight(forWidth width: CGFloat) -> CGFloat {
        Self.measureHeight("x", width: width)
    }

    private func updateTextViewFrame() {
        guard let textView, let iconView else {
            return
        }
        var rect = internalView.frame
        rect.origin.x += Self.margin + iconView.frame.width + iconView.frame.origin.x
        rect.size.width -= rect.origin.x + buttonWidth

        let measuredHeight = (textView.originalAttributedString as? NSMutableAttributedString)?.height(forWidth: rect.width)
            ?? (textView.originalAttributedString.map { NSMutableAttributedString(attributedString: $0).height(forWidth: rect.width) })
            ?? 0
        let height = max(minimumHeight(forWidth: rect.width), min(measuredHeight, maximumHeight(forWidth: rect.width)))
        let textRect = NSRect(
            x: rect.origin.x,
            y: floor((internalView.frame.height - height) / 2),
            width: internalView.frame.width - buttonWidth - iconView.frame.maxX - Self.margin,
            height: height)
        textView.frame = textRect
        textView.maxSize = textRect.size
        textView.minSize = textRect.size
    }
}
