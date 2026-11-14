//
//  ProfilesSidebarView.swift
//  iTerm2SharedARC
//
//  Modern native Swift sidebar for Settings > Profiles.
//

import AppKit

struct ProfileSidebarEntry: Equatable {
    let guid: String
    let name: String
    let subtitle: String
    let shortcutDisplay: String
    let tags: [String]
    let isDefault: Bool
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let cursorColor: NSColor
}

// MARK: - Mini Terminal Swatch

private final class ProfileTerminalSwatchView: NSView {
    var backgroundFill: NSColor = .black { didSet { needsDisplay = true } }
    var promptColor: NSColor = .white { didSet { needsDisplay = true } }
    var cursorColor: NSColor = .systemOrange { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 4, rect.height > 4 else { return }

        let rounded = NSBezierPath(roundedRect: rect, xRadius: 5.5, yRadius: 5.5)
        backgroundFill.setFill()
        rounded.fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        rounded.lineWidth = 1
        rounded.stroke()

        // Tiny geometric `>_` inside the 22x22 swatch
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: bounds.minX + 5.5, y: bounds.maxY - 6.5))
        chevron.line(to: NSPoint(x: bounds.minX + 9.5, y: bounds.midY))
        chevron.line(to: NSPoint(x: bounds.minX + 5.5, y: bounds.minY + 6.5))
        chevron.lineWidth = 1.8
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        promptColor.setStroke()
        chevron.stroke()

        let cursorRect = NSRect(x: bounds.minX + 11.2, y: bounds.minY + 6.0, width: 5.0, height: 2.2)
        cursorColor.setFill()
        NSBezierPath(roundedRect: cursorRect, xRadius: 0.8, yRadius: 0.8).fill()
    }
}

// MARK: - Tag Filter Chip Button

private final class ProfileTagChipButton: NSButton {
    var isSelectedChip = false {
        didSet {
            if oldValue != isSelectedChip {
                updateChipStyle()
            }
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 11, weight: .medium)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        updateChipStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChipStyle()
    }

    func preferredChipSize() -> NSSize {
        let usedFont = font ?? .systemFont(ofSize: 11, weight: .medium)
        let textWidth = (title as NSString).size(withAttributes: [.font: usedFont]).width
        return NSSize(width: ceil(textWidth) + 16, height: 20)
    }

    private func updateChipStyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let fg: NSColor
            let bg: NSColor
            if isSelectedChip {
                fg = .white
                bg = .controlAccentColor
            } else {
                fg = .secondaryLabelColor
                bg = NSColor(calibratedWhite: isDark ? 1.0 : 0.0, alpha: isDark ? 0.08 : 0.06)
            }
            layer?.backgroundColor = bg.cgColor
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: isSelectedChip ? .semibold : .medium),
                    .foregroundColor: fg,
                    .paragraphStyle: paragraph
                ]
            )
        }
    }
}

// MARK: - Sidebar Row & Cell

private final class ProfileSidebarRowView: NSTableRowView {
    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, !isSelected else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor(calibratedWhite: isDark ? 1.0 : 0.0, alpha: isDark ? 0.055 : 0.04).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

private final class ProfileSidebarCellView: NSTableCellView {
    override var isFlipped: Bool { true }

    private let swatchView = ProfileTerminalSwatchView(frame: .zero)
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let defaultPill = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var isRowSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false

        addSubview(swatchView)

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        addSubview(nameLabel)
        textField = nameLabel

        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.font = .systemFont(ofSize: 11)
        addSubview(subtitleLabel)

        defaultPill.stringValue = NSLocalizedString("Default", comment: "Default profile badge")
        defaultPill.font = .systemFont(ofSize: 9.5, weight: .semibold)
        defaultPill.alignment = .center
        defaultPill.wantsLayer = true
        defaultPill.layer?.cornerRadius = 4.5
        defaultPill.layer?.masksToBounds = true
        addSubview(defaultPill)

        shortcutLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcutLabel.alignment = .right
        addSubview(shortcutLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    func configure(with entry: ProfileSidebarEntry, selected: Bool) {
        isRowSelected = selected
        swatchView.backgroundFill = entry.backgroundColor
        swatchView.promptColor = entry.foregroundColor
        swatchView.cursorColor = entry.cursorColor

        nameLabel.stringValue = entry.name
        subtitleLabel.stringValue = entry.subtitle
        defaultPill.isHidden = !entry.isDefault
        shortcutLabel.stringValue = entry.shortcutDisplay
        shortcutLabel.isHidden = entry.shortcutDisplay.isEmpty
        toolTip = entry.subtitle.isEmpty ? entry.name : "\(entry.name) — \(entry.subtitle)"

        applyColors(selected: selected)
        needsLayout = true
    }

    func applyColors(selected: Bool) {
        isRowSelected = selected
        nameLabel.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        nameLabel.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        subtitleLabel.textColor = selected
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.78)
            : .secondaryLabelColor
        shortcutLabel.textColor = selected
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.82)
            : .tertiaryLabelColor

        effectiveAppearance.performAsCurrentDrawingAppearance {
            if selected {
                defaultPill.textColor = .alternateSelectedControlTextColor
                defaultPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            } else {
                defaultPill.textColor = .controlAccentColor
                defaultPill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors(selected: isRowSelected)
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let swatchSize: CGFloat = 22
        swatchView.frame = NSRect(x: 16,
                                  y: floor((bounds.height - swatchSize) / 2.0),
                                  width: swatchSize,
                                  height: swatchSize)

        let textLeft: CGFloat = 46
        var rightEdge = max(textLeft, bounds.width - 16)

        if !shortcutLabel.isHidden {
            shortcutLabel.sizeToFit()
            let sw = ceil(shortcutLabel.frame.width)
            shortcutLabel.frame = NSRect(x: max(textLeft, rightEdge - sw),
                                         y: 7,
                                         width: sw,
                                         height: 15)
            rightEdge = max(textLeft, shortcutLabel.frame.minX - 6)
        }

        var pillWidth: CGFloat = 0
        if !defaultPill.isHidden {
            defaultPill.sizeToFit()
            pillWidth = ceil(defaultPill.frame.width) + 10
        }

        nameLabel.sizeToFit()
        let naturalNameW = ceil(nameLabel.frame.width)
        let availableTopW = max(0, rightEdge - textLeft)

        if pillWidth > 0 && availableTopW > pillWidth + 36 {
            let nameW = min(naturalNameW, availableTopW - pillWidth - 6)
            nameLabel.frame = NSRect(x: textLeft, y: 6, width: max(0, nameW), height: 17)
            defaultPill.frame = NSRect(x: nameLabel.frame.maxX + 6, y: 7, width: pillWidth, height: 15)
        } else {
            nameLabel.frame = NSRect(x: textLeft, y: 6, width: availableTopW, height: 17)
            if pillWidth > 0 {
                defaultPill.frame = .zero
            }
        }

        let subtitleW = max(0, bounds.width - 16 - textLeft)
        subtitleLabel.frame = NSRect(x: textLeft, y: 25, width: subtitleW, height: 15)
    }
}

// MARK: - ProfilesSidebarView

private final class ContextualProfileTableView: NSTableView {
    var onContextMenuForRow: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }
        return onContextMenuForRow?(clickedRow)
    }
}

final class ProfilesSidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    override var isFlipped: Bool { true }

    var onSelectGuid: ((String) -> Void)?
    var onAddProfile: (() -> Void)?
    var onDuplicateProfile: (() -> Void)?
    var onRemoveProfile: (() -> Void)?
    var actionsMenuProvider: (() -> NSMenu?)?

    private weak var model: ProfileModel?

    private let searchField = NSSearchField()
    private let tagStripContainer = NSView()
    private var tagButtons: [ProfileTagChipButton] = []
    private var allTags: [String] = []
    private var selectedTag: String?

    private let scrollView = NSScrollView()
    private let tableView = ContextualProfileTableView()
    private let emptyFilterView = NSView()
    private let emptyFilterLabel = NSTextField(wrappingLabelWithString: "")
    private let clearFilterButton = NSButton()

    private let footerDivider = NSView()
    private let addButton = NSButton()
    private let duplicateButton = NSButton()
    private let removeButton = NSButton()
    private let actionsPopup = NSPopUpButton(frame: .zero, pullsDown: true)

    private let rightDivider = NSView()

    private var entries: [ProfileSidebarEntry] = []
    private var selectedGuid: String?
    private var isProgrammaticSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    var filterQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setupViews() {
        autoresizesSubviews = false
        wantsLayer = true
        setAccessibilityIdentifier("ProfilesSidebar")

        searchField.focusRingType = .none
        searchField.controlSize = .regular
        searchField.placeholderString = NSLocalizedString("Filter Profiles", comment: "Profiles sidebar filter placeholder")
        searchField.delegate = self
        searchField.setAccessibilityIdentifier("ProfilesFilterField")
        addSubview(searchField)

        tagStripContainer.autoresizesSubviews = false
        addSubview(tagStripContainer)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProfileSidebarColumn"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("ProfilesSidebarTable")
        tableView.onContextMenuForRow = { [weak self] row in
            guard let self, self.entries.indices.contains(row) else { return nil }
            let guid = self.entries[row].guid
            if self.selectedGuid != guid {
                self.selectGuid(guid, notify: true)
            }
            return self.buildContextMenu()
        }

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        addSubview(scrollView)

        // Empty search state
        emptyFilterView.isHidden = true
        emptyFilterLabel.stringValue = NSLocalizedString("No matching profiles", comment: "Profiles sidebar empty filter state")
        emptyFilterLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyFilterLabel.textColor = .secondaryLabelColor
        emptyFilterLabel.alignment = .center
        emptyFilterView.addSubview(emptyFilterLabel)

        clearFilterButton.title = NSLocalizedString("Clear Filter", comment: "Clear profile filter button")
        clearFilterButton.bezelStyle = .rounded
        clearFilterButton.controlSize = .small
        clearFilterButton.target = self
        clearFilterButton.action = #selector(clearFilterClicked(_:))
        emptyFilterView.addSubview(clearFilterButton)
        addSubview(emptyFilterView)

        // Footer controls
        footerDivider.wantsLayer = true
        addSubview(footerDivider)

        addButton.title = NSLocalizedString("New", comment: "Add new profile button")
        addButton.image = NSImage(systemSymbolName: SFSymbol.plus.rawValue,
                                  accessibilityDescription: addButton.title)
        addButton.imagePosition = .imageLeading
        addButton.bezelStyle = .recessed
        addButton.showsBorderOnlyWhileMouseInside = true
        addButton.font = .systemFont(ofSize: 12, weight: .medium)
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        addButton.toolTip = NSLocalizedString("Create a new profile", comment: "Add profile tooltip")
        addButton.setAccessibilityIdentifier("ProfilesAddButton")
        addSubview(addButton)

        duplicateButton.title = ""
        duplicateButton.image = NSImage(systemSymbolName: SFSymbol.docOnDoc.rawValue,
                                        accessibilityDescription: NSLocalizedString("Duplicate Profile", comment: "Duplicate profile action"))
        duplicateButton.imagePosition = .imageOnly
        duplicateButton.bezelStyle = .recessed
        duplicateButton.showsBorderOnlyWhileMouseInside = true
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateClicked(_:))
        duplicateButton.toolTip = NSLocalizedString("Duplicate selected profile", comment: "Duplicate profile tooltip")
        duplicateButton.setAccessibilityIdentifier("ProfilesDuplicateButton")
        addSubview(duplicateButton)

        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: SFSymbol.trash.rawValue,
                                     accessibilityDescription: NSLocalizedString("Delete Profile", comment: "Delete profile action"))
        removeButton.imagePosition = .imageOnly
        removeButton.bezelStyle = .recessed
        removeButton.showsBorderOnlyWhileMouseInside = true
        removeButton.target = self
        removeButton.action = #selector(removeClicked(_:))
        removeButton.toolTip = NSLocalizedString("Delete selected profile", comment: "Delete profile tooltip")
        removeButton.setAccessibilityIdentifier("ProfilesRemoveButton")
        addSubview(removeButton)

        actionsPopup.bezelStyle = .recessed
        actionsPopup.isBordered = false
        actionsPopup.showsBorderOnlyWhileMouseInside = true
        if let cell = actionsPopup.cell as? NSPopUpButtonCell {
            cell.arrowPosition = .noArrow
        }
        actionsPopup.toolTip = NSLocalizedString("More profile actions", comment: "More profile actions tooltip")
        actionsPopup.setAccessibilityIdentifier("ProfilesActionsMenu")
        addSubview(actionsPopup)

        rightDivider.wantsLayer = true
        addSubview(rightDivider)

        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
        reloadFromModel(selectedGuid: selectedGuid)
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            layer?.backgroundColor = NSColor(
                calibratedWhite: isDark ? 1.0 : 0.0,
                alpha: isDark ? 0.022 : 0.022
            ).cgColor
            let hairline = NSColor.separatorColor.withAlphaComponent(isDark ? 0.55 : 0.45).cgColor
            footerDivider.layer?.backgroundColor = hairline
            rightDivider.layer?.backgroundColor = hairline
        }
    }

    func bindModel(_ model: ProfileModel?) {
        self.model = model
    }

    func clearSearchIfNeeded() {
        guard !searchField.stringValue.isEmpty || selectedTag != nil else { return }
        searchField.stringValue = ""
        selectedTag = nil
        reloadFromModel(selectedGuid: selectedGuid)
    }

    func reloadFromModel(selectedGuid: String?) {
        self.selectedGuid = selectedGuid
        guard let model else {
            entries = []
            tableView.reloadData()
            updateFooterState(totalCount: 0)
            needsLayout = true
            return
        }

        let allProfiles = model.bookmarks() ?? []
        let defaultGuid = model.defaultProfile()?[KEY_GUID] as? String
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Gather unique sorted tags
        let discoveredTags = (model.allTags() as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if discoveredTags != allTags {
            allTags = discoveredTags
            if let selectedTag, !allTags.contains(selectedTag) {
                self.selectedTag = nil
            }
            rebuildTagButtons()
        } else {
            syncTagButtonSelection()
        }

        let query = filterQuery.lowercased()
        var built: [ProfileSidebarEntry] = []
        built.reserveCapacity(allProfiles.count)

        for raw in allProfiles {
            guard let guid = raw[KEY_GUID] as? String else { continue }
            let name = (raw[KEY_NAME] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? NSLocalizedString("Untitled", comment: "Fallback profile name")
            let tags = (raw[KEY_TAGS] as? [String]) ?? []

            if let activeTag = selectedTag, !tags.contains(activeTag) {
                continue
            }

            let subtitle = Self.makeSubtitle(for: raw, tags: tags)
            if !query.isEmpty {
                let matchesName = name.lowercased().contains(query)
                let matchesSubtitle = subtitle.lowercased().contains(query)
                let matchesTag = tags.contains { $0.lowercased().contains(query) }
                if !matchesName && !matchesSubtitle && !matchesTag {
                    continue
                }
            }

            let shortcutRaw = (raw[KEY_SHORTCUT] as? String) ?? ""
            let shortcutDisplay = shortcutRaw.isEmpty ? "" : "⌃⌘\(shortcutRaw.uppercased())"
            let bg = iTermProfilePreferences.color(forKey: KEY_BACKGROUND_COLOR, dark: isDark, profile: raw)
                ?? (isDark ? NSColor(calibratedWhite: 0.10, alpha: 1) : .white)
            let fg = iTermProfilePreferences.color(forKey: KEY_FOREGROUND_COLOR, dark: isDark, profile: raw)
                ?? (isDark ? NSColor(calibratedWhite: 0.90, alpha: 1) : .black)
            let cursor = iTermProfilePreferences.color(forKey: KEY_CURSOR_COLOR, dark: isDark, profile: raw)
                ?? .systemOrange

            built.append(ProfileSidebarEntry(
                guid: guid,
                name: name,
                subtitle: subtitle,
                shortcutDisplay: shortcutDisplay,
                tags: tags,
                isDefault: guid == defaultGuid,
                backgroundColor: bg,
                foregroundColor: fg,
                cursorColor: cursor
            ))
        }

        entries = built
        isProgrammaticSelection = true
        tableView.reloadData()

        emptyFilterView.isHidden = !entries.isEmpty || (query.isEmpty && selectedTag == nil)
        scrollView.isHidden = !emptyFilterView.isHidden

        if let selectedGuid, let idx = entries.firstIndex(where: { $0.guid == selectedGuid }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        } else {
            tableView.deselectAll(nil)
        }
        isProgrammaticSelection = false

        rebuildActionsPullDownMenu()
        updateFooterState(totalCount: allProfiles.count)
        needsLayout = true
    }

    func selectGuid(_ guid: String?, notify: Bool) {
        selectedGuid = guid
        if let guid, let idx = entries.firstIndex(where: { $0.guid == guid }) {
            isProgrammaticSelection = !notify
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
            isProgrammaticSelection = false
        }
        updateFooterState(totalCount: model?.bookmarks()?.count ?? entries.count)
    }

    private static func makeSubtitle(for profile: [AnyHashable: Any], tags: [String]) -> String {
        let customCmd = (profile[KEY_CUSTOM_COMMAND] as? String) ?? kProfilePreferenceCommandTypeLoginShellValue
        if customCmd != kProfilePreferenceCommandTypeLoginShellValue {
            if let cmd = profile[KEY_COMMAND_LINE] as? String,
               !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if !tags.isEmpty {
            return tags.prefix(3).map { "#\($0)" }.joined(separator: " · ")
        }
        let customDir = (profile[KEY_CUSTOM_DIRECTORY] as? String) ?? "No"
        if customDir == kProfilePreferenceInitialDirectoryCustomValue,
           let dir = profile[KEY_WORKING_DIRECTORY] as? String,
           !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dir
        }
        return NSLocalizedString("Login shell", comment: "Default profile command summary")
    }

    private func rebuildTagButtons() {
        tagButtons.forEach { $0.removeFromSuperview() }
        tagButtons.removeAll()
        guard !allTags.isEmpty else {
            tagStripContainer.isHidden = true
            return
        }
        tagStripContainer.isHidden = false

        let allBtn = ProfileTagChipButton(title: NSLocalizedString("All", comment: "All profile tags filter chip"))
        allBtn.tag = -1
        allBtn.target = self
        allBtn.action = #selector(tagChipClicked(_:))
        allBtn.isSelectedChip = (selectedTag == nil)
        tagStripContainer.addSubview(allBtn)
        tagButtons.append(allBtn)

        for (index, tag) in allTags.enumerated() {
            let chip = ProfileTagChipButton(title: tag)
            chip.tag = index
            chip.target = self
            chip.action = #selector(tagChipClicked(_:))
            chip.isSelectedChip = (selectedTag == tag)
            tagStripContainer.addSubview(chip)
            tagButtons.append(chip)
        }
    }

    private func syncTagButtonSelection() {
        for chip in tagButtons {
            if chip.tag == -1 {
                chip.isSelectedChip = (selectedTag == nil)
            } else if allTags.indices.contains(chip.tag) {
                chip.isSelectedChip = (selectedTag == allTags[chip.tag])
            }
        }
    }

    private func rebuildActionsPullDownMenu() {
        let menu = NSMenu()
        let iconItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        iconItem.image = NSImage(systemSymbolName: SFSymbol.ellipsisCircle.rawValue,
                                 accessibilityDescription: NSLocalizedString("More profile actions", comment: "More profile actions"))
        menu.addItem(iconItem)

        if let sourceMenu = actionsMenuProvider?() {
            for (idx, srcItem) in sourceMenu.items.enumerated() {
                // Skip pull-down title item at index 0 if the source NSPopUpButton was a pull-down
                if idx == 0 && srcItem.action == nil && !srcItem.isSeparatorItem {
                    continue
                }
                if let copied = srcItem.copy() as? NSMenuItem {
                    menu.addItem(copied)
                }
            }
        }
        actionsPopup.menu = menu
    }

    private func buildContextMenu() -> NSMenu? {
        guard let sourceMenu = actionsMenuProvider?() else { return nil }
        let menu = NSMenu()
        for (idx, srcItem) in sourceMenu.items.enumerated() {
            if idx == 0 && srcItem.action == nil && !srcItem.isSeparatorItem {
                continue
            }
            if let copied = srcItem.copy() as? NSMenuItem {
                menu.addItem(copied)
            }
        }
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(
            title: NSLocalizedString("Delete Profile…", comment: "Context menu delete profile"),
            action: #selector(removeClicked(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = removeButton.isEnabled
        menu.addItem(deleteItem)
        return menu
    }

    private func updateFooterState(totalCount: Int) {
        let hasSelection = selectedGuid != nil
        duplicateButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection && totalCount > 1
        actionsPopup.isEnabled = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let contentW = max(0, bounds.width - 1)
        rightDivider.frame = NSRect(x: contentW, y: 0, width: 1, height: bounds.height)

        let padX: CGFloat = 12
        var cursorY: CGFloat = 12

        searchField.frame = NSRect(x: padX, y: cursorY, width: max(0, contentW - padX * 2), height: 28)
        cursorY += 34

        if !tagButtons.isEmpty {
            tagStripContainer.isHidden = false
            let stripMaxW = max(40, contentW - padX * 2)
            var chipX: CGFloat = 0
            var chipY: CGFloat = 0
            let chipGapX: CGFloat = 5
            let chipGapY: CGFloat = 5
            for chip in tagButtons {
                let sz = chip.preferredChipSize()
                let w = min(stripMaxW, sz.width)
                if chipX > 0 && chipX + w > stripMaxW {
                    chipX = 0
                    chipY += sz.height + chipGapY
                }
                chip.frame = NSRect(x: chipX, y: chipY, width: w, height: sz.height)
                chipX += w + chipGapX
            }
            let stripH = chipY + 20
            tagStripContainer.frame = NSRect(x: padX, y: cursorY, width: stripMaxW, height: stripH)
            cursorY += stripH + 8
        } else {
            tagStripContainer.isHidden = true
        }

        let footerH: CGFloat = 40
        let footerTop = max(cursorY, bounds.height - footerH)
        footerDivider.frame = NSRect(x: 0, y: footerTop, width: contentW, height: 1)

        let listH = max(0, footerTop - cursorY - 4)
        scrollView.frame = NSRect(x: 0, y: cursorY, width: contentW, height: listH)
        let colWidth = max(0, scrollView.contentSize.width)
        if abs(tableView.frame.width - colWidth) > 0.5 {
            tableView.frame.size.width = colWidth
        }
        tableView.tableColumns.first?.width = colWidth

        // Empty filter overlay
        if !emptyFilterView.isHidden {
            emptyFilterView.frame = scrollView.frame
            let labelMaxW = max(40, contentW - 28)
            let labelSize = emptyFilterLabel.sizeThatFits(NSSize(width: labelMaxW, height: 80))
            clearFilterButton.sizeToFit()
            let btnW = min(labelMaxW, ceil(clearFilterButton.fittingSize.width) + 12)
            let btnH: CGFloat = 24
            let groupH = ceil(labelSize.height) + 10 + btnH
            let startY = max(8, floor((listH - groupH) / 2.0))
            emptyFilterLabel.frame = NSRect(x: 14, y: startY, width: labelMaxW, height: ceil(labelSize.height))
            clearFilterButton.frame = NSRect(x: max(0, floor((contentW - btnW) / 2.0)),
                                             y: emptyFilterLabel.frame.maxY + 10,
                                             width: btnW,
                                             height: btnH)
        }

        // Footer button layout
        let btnH: CGFloat = 26
        let btnY = footerTop + floor((footerH - btnH) / 2.0)
        addButton.sizeToFit()
        let addW = min(max(56, ceil(addButton.fittingSize.width) + 8), max(56, contentW - 104))
        addButton.frame = NSRect(x: 10, y: btnY, width: addW, height: btnH)

        let iconW: CGFloat = 28
        var rightX = max(addButton.frame.maxX + 4, contentW - 8)
        rightX -= iconW
        actionsPopup.frame = NSRect(x: rightX, y: btnY, width: iconW, height: btnH)
        rightX -= iconW + 2
        removeButton.frame = NSRect(x: rightX, y: btnY, width: iconW, height: btnH)
        rightX -= iconW + 2
        duplicateButton.frame = NSRect(x: rightX, y: btnY, width: iconW, height: btnH)
    }

    // MARK: - Actions & Delegates

    @objc private func tagChipClicked(_ sender: ProfileTagChipButton) {
        if sender.tag == -1 {
            selectedTag = nil
        } else if allTags.indices.contains(sender.tag) {
            let clicked = allTags[sender.tag]
            selectedTag = (selectedTag == clicked) ? nil : clicked
        }
        reloadFromModel(selectedGuid: selectedGuid)
    }

    @objc private func clearFilterClicked(_ sender: Any?) {
        clearSearchIfNeeded()
    }

    @objc private func addClicked(_ sender: Any?) {
        clearSearchIfNeeded()
        onAddProfile?()
    }

    @objc private func duplicateClicked(_ sender: Any?) {
        onDuplicateProfile?()
    }

    @objc private func removeClicked(_ sender: Any?) {
        onRemoveProfile?()
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadFromModel(selectedGuid: selectedGuid)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ProfileSidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("ProfileSidebarCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ProfileSidebarCellView)
            ?? {
                let c = ProfileSidebarCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 46))
                c.identifier = id
                return c
            }()
        cell.configure(with: entries[row], selected: row == tableView.selectedRow)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        for idx in entries.indices {
            if let cell = tableView.view(atColumn: 0, row: idx, makeIfNecessary: false) as? ProfileSidebarCellView {
                cell.applyColors(selected: idx == tableView.selectedRow)
            }
        }
        guard !isProgrammaticSelection,
              entries.indices.contains(tableView.selectedRow) else {
            return
        }
        let chosenGuid = entries[tableView.selectedRow].guid
        selectedGuid = chosenGuid
        updateFooterState(totalCount: model?.bookmarks()?.count ?? entries.count)
        onSelectGuid?(chosenGuid)
    }
}
