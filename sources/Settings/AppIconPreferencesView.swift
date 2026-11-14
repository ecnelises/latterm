//
//  AppIconPreferencesView.swift
//  Latterm
//

import Cocoa

@objc(iTermAppIconPreferencesView)
public final class AppIconPreferencesView: NSView {
    @objc public let lightLabel: NSTextField
    @objc public let darkLabel: NSTextField
    @objc public let lightPopupButton: NSPopUpButton
    @objc public let darkPopupButton: NSPopUpButton

    private let lightCard = NSView(frame: .zero)
    private let darkCard = NSView(frame: .zero)
    private let lightStage = NSView(frame: .zero)
    private let darkStage = NSView(frame: .zero)
    private let lightPreview = NSImageView(frame: .zero)
    private let darkPreview = NSImageView(frame: .zero)
    private let lightModeBadge = NSTextField(labelWithString: "")
    private let darkModeBadge = NSTextField(labelWithString: "")
    private let noteLabel: NSTextField

    private var appearanceObservation: NSKeyValueObservation?
    private let channel: AppIconChannel

    @objc public var preferredWidth: CGFloat { 512 }
    @objc public var preferredHeight: CGFloat { 208 }

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        self.channel = LattermAppIconController.currentChannel()
        self.lightLabel = NSTextField(labelWithString: NSLocalizedString(
            "Light mode icon:",
            comment: "Label for popup selecting app icon in Light appearance"
        ))
        self.darkLabel = NSTextField(labelWithString: NSLocalizedString(
            "Dark mode icon:",
            comment: "Label for popup selecting app icon in Dark appearance"
        ))
        self.lightPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
        self.darkPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)

        let noteText: String
        switch channel {
        case .stable:
            noteText = NSLocalizedString(
                "Switches automatically when macOS or theme appearance changes.",
                comment: "Footnote explaining adaptive Light/Dark app icon behavior on Stable builds"
            )
        case .alpha:
            noteText = NSLocalizedString(
                "Switches automatically with appearance. Alpha builds use an α cursor.",
                comment: "Footnote explaining adaptive Light/Dark app icon behavior on Alpha builds"
            )
        case .beta:
            noteText = NSLocalizedString(
                "Switches automatically with appearance. Beta builds use a β cursor.",
                comment: "Footnote explaining adaptive Light/Dark app icon behavior on Beta builds"
            )
        }
        self.noteLabel = NSTextField(wrappingLabelWithString: noteText)

        let initialFrame = NSRect(x: frameRect.origin.x,
                                  y: frameRect.origin.y,
                                  width: max(512, frameRect.width),
                                  height: max(208, frameRect.height))
        super.init(frame: initialFrame)
        configureViews()
        observeAppearance()
        refreshPreviews()
        layout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    private func configureViews() {
        setAccessibilityIdentifier("AppIconPreferencesView")

        configureCard(lightCard, stage: lightStage, isDarkStage: false, badge: lightModeBadge, badgeText: NSLocalizedString("Light", comment: "Light appearance badge on app icon card"), preview: lightPreview, label: lightLabel, popup: lightPopupButton, accessibilityId: "LightAppIconPopup")
        configureCard(darkCard, stage: darkStage, isDarkStage: true, badge: darkModeBadge, badgeText: NSLocalizedString("Dark", comment: "Dark appearance badge on app icon card"), preview: darkPreview, label: darkLabel, popup: darkPopupButton, accessibilityId: "DarkAppIconPopup")

        populateMenu(of: lightPopupButton)
        populateMenu(of: darkPopupButton)

        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        addSubview(noteLabel)
    }

    private func configureCard(_ card: NSView,
                               stage: NSView,
                               isDarkStage: Bool,
                               badge: NSTextField,
                               badgeText: String,
                               preview: NSImageView,
                               label: NSTextField,
                               popup: NSPopUpButton,
                               accessibilityId: String) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(card)

        stage.wantsLayer = true
        stage.layer?.cornerRadius = 8
        stage.layer?.borderWidth = 1
        if isDarkStage {
            stage.layer?.backgroundColor = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            stage.layer?.borderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
        } else {
            stage.layer?.backgroundColor = CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
            stage.layer?.borderColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08)
        }
        card.addSubview(stage)

        preview.imageScaling = .scaleProportionallyDown
        stage.addSubview(preview)

        badge.stringValue = badgeText
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = isDarkStage ? NSColor(srgbRed: 0.78, green: 0.78, blue: 0.80, alpha: 1)
                                      : NSColor(srgbRed: 0.36, green: 0.36, blue: 0.38, alpha: 1)
        badge.sizeToFit()
        stage.addSubview(badge)

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .left
        label.sizeToFit()
        card.addSubview(label)

        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular))
        popup.setAccessibilityIdentifier(accessibilityId)
        card.addSubview(popup)
    }

    private func populateMenu(of popup: NSPopUpButton) {
        popup.removeAllItems()
        let menu = NSMenu()
        menu.autoenablesItems = false

        for (groupIndex, group) in AppIconGroup.allCases.enumerated() {
            if groupIndex > 0 {
                menu.addItem(.separator())
            }
            let header = NSMenuItem(title: group.localizedTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for variant in AppIconVariant.allCases where variant.group == group {
                let item = NSMenuItem(title: variant.localizedTitle, action: nil, keyEquivalent: "")
                item.representedObject = variant.rawValue
                item.image = LattermAppIconRenderer.makeIconImage(
                    variant: variant,
                    channel: channel,
                    logicalSize: CGSize(width: 18, height: 18),
                    pixelSizes: [18, 36]
                )
                menu.addItem(item)
            }
        }
        popup.menu = menu
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshPreviews()
            }
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPreviews()
    }

    public override func layout() {
        super.layout()

        let totalWidth: CGFloat = min(512, max(440, bounds.width))
        let gap: CGFloat = 14
        let cardWidth = floor((totalWidth - gap) / 2.0)
        let cardHeight: CGFloat = 172

        layoutCard(lightCard, stage: lightStage, preview: lightPreview, badge: lightModeBadge, label: lightLabel, popup: lightPopupButton, frame: NSRect(x: 0, y: 4, width: cardWidth, height: cardHeight))
        layoutCard(darkCard, stage: darkStage, preview: darkPreview, badge: darkModeBadge, label: darkLabel, popup: darkPopupButton, frame: NSRect(x: cardWidth + gap, y: 4, width: cardWidth, height: cardHeight))

        let noteTop: CGFloat = cardHeight + 12
        let noteSize = noteLabel.sizeThatFits(NSSize(width: totalWidth, height: 60))
        noteLabel.frame = NSRect(x: 0, y: noteTop, width: totalWidth, height: ceil(noteSize.height))
    }

    private func layoutCard(_ card: NSView,
                            stage: NSView,
                            preview: NSImageView,
                            badge: NSTextField,
                            label: NSTextField,
                            popup: NSPopUpButton,
                            frame: NSRect) {
        card.frame = frame
        let pad: CGFloat = 12
        let innerWidth = frame.width - pad * 2
        let stageFrame = NSRect(x: pad, y: pad, width: innerWidth, height: 84)
        stage.frame = stageFrame

        let previewSize: CGFloat = 68
        preview.frame = NSRect(
            x: floor((stageFrame.width - previewSize) / 2.0),
            y: floor((stageFrame.height - previewSize) / 2.0),
            width: previewSize,
            height: previewSize
        )

        badge.sizeToFit()
        badge.frame = NSRect(x: 10, y: 8, width: badge.frame.width, height: badge.frame.height)

        label.sizeToFit()
        label.frame = NSRect(x: pad, y: stageFrame.maxY + 10, width: innerWidth, height: ceil(label.frame.height))

        popup.sizeToFit()
        popup.frame = NSRect(x: pad, y: label.frame.maxY + 6, width: innerWidth, height: 26)
    }

    @objc public func refreshPreviews() {
        let lightRaw = (lightPopupButton.selectedItem?.representedObject as? String)
            ?? iTermPreferences.string(forKey: kPreferenceKeyLightAppIcon)
        let darkRaw = (darkPopupButton.selectedItem?.representedObject as? String)
            ?? iTermPreferences.string(forKey: kPreferenceKeyDarkAppIcon)

        let lightVariant = AppIconVariant.resolve(lightRaw, fallback: .defaultLight)
        let darkVariant = AppIconVariant.resolve(darkRaw, fallback: .defaultDark)

        lightPreview.image = LattermAppIconRenderer.makeIconImage(
            variant: lightVariant,
            channel: channel,
            logicalSize: CGSize(width: 68, height: 68),
            pixelSizes: [68, 136]
        )
        darkPreview.image = LattermAppIconRenderer.makeIconImage(
            variant: darkVariant,
            channel: channel,
            logicalSize: CGSize(width: 68, height: 68),
            pixelSizes: [68, 136]
        )

        let isDarkActive = NSApplication.shared.effectiveAppearance.it_isDark
        updateCardHighlight(lightCard, active: !isDarkActive)
        updateCardHighlight(darkCard, active: isDarkActive)
    }

    private func updateCardHighlight(_ card: NSView, active: Bool) {
        if active {
            card.layer?.borderWidth = 1.5
            card.layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            card.layer?.borderWidth = 1
            card.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
