//
//  SettingsProfilesView.swift
//  iTerm2SharedARC
//
//  Modern side-by-side Profile sidebar + continuous single-document scrollable Profile editor.
//  Eliminates legacy category tabs and nested scroll traps.
//

import AppKit

// MARK: - Continuous Unified Document View

final class ProfileUnifiedDocumentView: NSView, ProfileFormDocumentProtocol, ProfileUnifiedDocumentHost {
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }

    struct CategorySection {
        let item: NSTabViewItem
        let view: NSView
        let headingLabel: NSTextField
        let topRule: NSView
    }

    private(set) var sections: [CategorySection] = []
    private(set) var computedHeight: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = -1
    private var layoutDirty = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    func syncSections(from tabView: NSTabView) {
        let previous = sections
        var updated: [CategorySection] = []
        updated.reserveCapacity(tabView.numberOfTabViewItems)

        for (idx, item) in tabView.tabViewItems.enumerated() {
            guard let view = item.view else { continue }
            let existing = previous.first { $0.item === item }

            let heading = existing?.headingLabel ?? {
                let lbl = NSTextField(labelWithString: "")
                lbl.font = .systemFont(ofSize: 18, weight: .bold)
                lbl.textColor = .labelColor
                lbl.lineBreakMode = .byTruncatingTail
                lbl.maximumNumberOfLines = 1
                return lbl
            }()
            heading.stringValue = item.label
            heading.setAccessibilityIdentifier("ProfileSection.\(idx)")

            let rule = existing?.topRule ?? {
                let r = NSView()
                r.wantsLayer = true
                return r
            }()

            if rule.superview !== self {
                rule.removeFromSuperview()
                addSubview(rule)
            }
            if heading.superview !== self {
                heading.removeFromSuperview()
                addSubview(heading)
            }
            if view.superview !== self {
                view.removeFromSuperview()
                view.autoresizingMask = []
                addSubview(view)
            }
            view.isHidden = false

            updated.append(CategorySection(item: item, view: view, headingLabel: heading, topRule: rule))
        }

        for old in previous where !updated.contains(where: { $0.item === old.item }) {
            old.headingLabel.removeFromSuperview()
            old.topRule.removeFromSuperview()
            old.view.removeFromSuperview()
        }

        sections = updated
        refreshRuleColors()
        invalidateFormLayout()
    }

    func restoreDetachedSectionViewsIfNeeded() {
        var restoredAny = false
        for section in sections where section.view.superview !== self {
            section.view.removeFromSuperview()
            section.view.autoresizingMask = []
            addSubview(section.view)
            restoredAny = true
        }
        if restoredAny {
            invalidateFormLayout()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshRuleColors()
    }

    private func refreshRuleColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = NSColor.separatorColor.withAlphaComponent(isDark ? 0.50 : 0.40).cgColor
            for section in sections {
                section.topRule.layer?.backgroundColor = color
            }
        }
    }

    func invalidateUnifiedLayout() {
        invalidateFormLayout()
    }

    @objc func markDirtyWithoutPropagating() {
        layoutDirty = true
    }

    @objc func invalidateFormLayout() {
        layoutDirty = true
        needsLayout = true
        if let scroll = enclosingScrollView as? ProfileUnifiedScrollView {
            scroll.needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, (layoutDirty || abs(bounds.width - lastLaidOutWidth) > 0.25) {
            updateFormLayout(forWidth: bounds.width)
        }
    }

    @objc func updateFormLayout(forWidth width: CGFloat) {
        guard width > 0 else { return }
        restoreDetachedSectionViewsIfNeeded()
        if !layoutDirty && abs(width - lastLaidOutWidth) <= 0.25 {
            return
        }
        let forceChildRelayout = layoutDirty
        layoutDirty = false
        lastLaidOutWidth = width

        let outerPadding = width >= ProfileFormMetrics.wideThreshold
            ? ProfileFormMetrics.outerPaddingWide
            : ProfileFormMetrics.outerPaddingCompact
        let usableWidth = max(120, width - outerPadding * 2)
        let cardWidth = min(ProfileFormMetrics.maxFormWidth, usableWidth)
        let cardOriginX = max(0, floor((width - cardWidth) / 2.0))

        var y: CGFloat = 18
        var renderedCount = 0

        for section in sections {
            let sectionHeight: CGFloat
            if let formDoc = section.view.it_childProfileFormDocument() {
                if forceChildRelayout {
                    formDoc.markDirtyWithoutPropagating()
                }
                formDoc.updateFormLayout(forWidth: width)
                sectionHeight = formDoc.computedHeight
            } else {
                sectionHeight = max(0, section.view.frame.height)
            }

            guard sectionHeight > 0 else {
                section.topRule.isHidden = true
                section.headingLabel.isHidden = true
                section.view.isHidden = true
                section.view.frame = .zero
                continue
            }

            if renderedCount > 0 {
                y += 18
                section.topRule.isHidden = false
                section.topRule.frame = NSRect(x: cardOriginX, y: y, width: cardWidth, height: 1)
                y += 20
            } else {
                section.topRule.isHidden = true
            }

            section.headingLabel.isHidden = false
            section.headingLabel.frame = NSRect(x: cardOriginX + 2, y: y, width: max(0, cardWidth - 4), height: 24)
            y += 30

            section.view.isHidden = false
            section.view.frame = NSRect(x: 0, y: y, width: width, height: sectionHeight)
            if let formDoc = section.view.it_childProfileFormDocument() {
                formDoc.frame = section.view.bounds
            }
            y += sectionHeight
            renderedCount += 1
        }

        computedHeight = y + 36
    }

    func headingMinY(at index: Int) -> CGFloat? {
        guard sections.indices.contains(index), !sections[index].headingLabel.isHidden else {
            return nil
        }
        return index == 0 ? 0 : max(0, sections[index].headingLabel.frame.minY - 14)
    }
}

// MARK: - Root Settings > Profiles View

@objc(iTermSettingsProfilesView)
final class SettingsProfilesView: NSView {
    override var isFlipped: Bool { true }

    private static let wideSidebarWidth: CGFloat = 226
    private static let narrowSidebarWidth: CGFloat = 202
    private static let narrowSidebarThreshold: CGFloat = 680
    private static let editorHeaderHeight: CGFloat = 48

    @objc var editingSession = false {
        didSet {
            autoresizesSubviews = false
            refreshSelectionMetadata()
            needsLayout = true
        }
    }

    @objc var isInSplitMode: Bool { !editingSession }

    // Backing XIB references kept alive in hidden vault
    private weak var profileList: ProfileListView?
    private weak var detailsWrapper: NSView?
    private weak var tabView: NSTabView?
    private weak var noProfileSelectedView: NSView?
    private weak var toggleTagsButton: NSButton?
    private weak var addProfileButton: NSButton?
    private weak var removeProfileButton: NSButton?
    private weak var otherActionsPopup: NSPopUpButton?
    private weak var copyToProfileButton: NSButton?
    private weak var profileModel: ProfileModel?
    private weak var setAsDefaultTarget: AnyObject?
    private var setAsDefaultAction: Selector?
    private weak var duplicateTarget: AnyObject?
    private var duplicateAction: Selector?

    private let hiddenLegacyVault = NSView()
    private let sidebarView = ProfilesSidebarView(frame: .zero)

    private let detailContainer = NSView()
    private let editorHeader = NSView()
    private let editorHeaderDivider = NSView()
    private let selectedProfileLabel = NSTextField(labelWithString: "")
    private let defaultBadgePill = NSTextField(labelWithString: "")
    private let setDefaultButton = NSButton()
    private let sectionJumpPopup = NSPopUpButton(frame: .zero, pullsDown: true)

    @objc let profileScrollView = ProfileUnifiedScrollView(frame: .zero)
    private let unifiedDocument = ProfileUnifiedDocumentView(frame: .zero)

    private let emptyStateView = NSView()
    private let emptyStateLabel = NSTextField(wrappingLabelWithString: "")

    private var hasSelectedProfile = true
    private var modelObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupChrome()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupChrome()
    }

    deinit {
        for token in modelObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupChrome() {
        autoresizesSubviews = false

        hiddenLegacyVault.isHidden = true
        hiddenLegacyVault.frame = .zero
        addSubview(hiddenLegacyVault)

        // Left native Profile Sidebar
        sidebarView.onSelectGuid = { [weak self] guid in
            guard let self, let list = self.profileList else { return }
            if list.searchFieldHasText() {
                list.eraseQuery()
            }
            list.selectRow(byGuid: guid)
            self.refreshSelectionMetadata()
        }
        sidebarView.onAddProfile = { [weak self] in
            guard let self, let btn = self.addProfileButton else { return }
            NSApp.sendAction(btn.action!, to: btn.target, from: btn)
            self.reloadProfilesSidebar()
        }
        sidebarView.onDuplicateProfile = { [weak self] in
            guard let self else { return }
            if let action = self.duplicateAction {
                NSApp.sendAction(action, to: self.duplicateTarget, from: self)
            }
            self.reloadProfilesSidebar()
        }
        sidebarView.onRemoveProfile = { [weak self] in
            guard let self, let btn = self.removeProfileButton, btn.isEnabled else { return }
            NSApp.sendAction(btn.action!, to: btn.target, from: btn)
            self.reloadProfilesSidebar()
        }
        sidebarView.actionsMenuProvider = { [weak self] in
            self?.otherActionsPopup?.menu
        }
        addSubview(sidebarView)

        // Right continuous Profile Editor
        detailContainer.autoresizesSubviews = false
        addSubview(detailContainer)

        editorHeader.autoresizesSubviews = false
        editorHeader.wantsLayer = true
        editorHeader.setAccessibilityIdentifier("ProfilesEditorHeader")
        detailContainer.addSubview(editorHeader)

        editorHeaderDivider.wantsLayer = true
        editorHeader.addSubview(editorHeaderDivider)

        selectedProfileLabel.font = .systemFont(ofSize: 16, weight: .bold)
        selectedProfileLabel.textColor = .labelColor
        selectedProfileLabel.lineBreakMode = .byTruncatingTail
        selectedProfileLabel.maximumNumberOfLines = 1
        selectedProfileLabel.setAccessibilityIdentifier("SettingsSelectedProfile")
        editorHeader.addSubview(selectedProfileLabel)

        defaultBadgePill.stringValue = NSLocalizedString("Default Profile", comment: "Header pill for default profile")
        defaultBadgePill.font = .systemFont(ofSize: 11, weight: .semibold)
        defaultBadgePill.alignment = .center
        defaultBadgePill.wantsLayer = true
        defaultBadgePill.layer?.cornerRadius = 6
        defaultBadgePill.layer?.masksToBounds = true
        editorHeader.addSubview(defaultBadgePill)

        setDefaultButton.title = NSLocalizedString("Set as Default", comment: "Header button to make profile default")
        setDefaultButton.bezelStyle = .rounded
        setDefaultButton.controlSize = .small
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setDefaultClicked(_:))
        setDefaultButton.setAccessibilityIdentifier("ProfilesSetDefaultButton")
        editorHeader.addSubview(setDefaultButton)

        sectionJumpPopup.bezelStyle = .rounded
        sectionJumpPopup.controlSize = .small
        sectionJumpPopup.target = self
        sectionJumpPopup.action = #selector(sectionJumpSelected(_:))
        sectionJumpPopup.setAccessibilityIdentifier("ProfilesSectionJumpPopup")
        editorHeader.addSubview(sectionJumpPopup)

        profileScrollView.setAccessibilityIdentifier("ProfileContinuousScrollView")
        profileScrollView.documentView = unifiedDocument
        detailContainer.addSubview(profileScrollView)

        emptyStateView.isHidden = true
        emptyStateLabel.stringValue = NSLocalizedString(
            "Select a profile from the sidebar to edit its settings.",
            comment: "Empty state when no profile is selected"
        )
        emptyStateLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateView.addSubview(emptyStateLabel)
        detailContainer.addSubview(emptyStateView)

        installModelObservers()
        refreshAppearanceColors()
    }

    private func installModelObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .reloadAddressBook,
            Notification.Name(kReloadAllProfiles),
            .profileWasDeleted,
            Notification.Name(kPreferencePanelDidUpdateProfileFields)
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reloadProfilesSidebar()
            }
            modelObservers.append(token)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearanceColors()
    }

    private func refreshAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            editorHeader.layer?.backgroundColor = NSColor(
                calibratedWhite: isDark ? 1.0 : 0.0,
                alpha: isDark ? 0.015 : 0.01
            ).cgColor
            editorHeaderDivider.layer?.backgroundColor = NSColor.separatorColor
                .withAlphaComponent(isDark ? 0.50 : 0.40).cgColor
            defaultBadgePill.textColor = .controlAccentColor
            defaultBadgePill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        }
    }

    // Intercept legacy XIB subviews added during nib unarchiving and park them safely.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview === hiddenLegacyVault || subview === sidebarView || subview === detailContainer {
            return
        }
        if let button = subview as? NSButton,
           button.action.map({ NSStringFromSelector($0) }) == "copyToProfile:" {
            copyToProfileButton = button
            editorHeader.addSubview(button)
            needsLayout = true
            return
        }
        parkInLegacyVault(subview)
    }

    private func parkInLegacyVault(_ view: NSView?) {
        guard let view, view.superview !== hiddenLegacyVault else { return }
        view.removeFromSuperview()
        view.autoresizingMask = []
        view.frame = .zero
        hiddenLegacyVault.addSubview(view)
    }

    @objc func configureMasterDetail(profileList: ProfileListView,
                                     model: ProfileModel?,
                                     detailsWrapper: NSView,
                                     tabView: NSTabView,
                                     noProfileSelectedView: NSView,
                                     toggleTagsButton: NSButton,
                                     addButton: NSButton,
                                     removeButton: NSButton,
                                     actionsPopup: NSPopUpButton,
                                     copyToProfileButton: NSButton?) {
        self.profileList = profileList
        self.profileModel = model
        self.detailsWrapper = detailsWrapper
        self.tabView = tabView
        self.noProfileSelectedView = noProfileSelectedView
        self.toggleTagsButton = toggleTagsButton
        self.addProfileButton = addButton
        self.removeProfileButton = removeButton
        self.otherActionsPopup = actionsPopup
        self.copyToProfileButton = copyToProfileButton

        // Discover Set as Default & Duplicate actions from actionsPopup.menu
        if let menu = actionsPopup.menu {
            for item in menu.items {
                let sel = item.action.map { NSStringFromSelector($0) } ?? ""
                if sel == "setAsDefault:" {
                    setAsDefaultTarget = item.target
                    setAsDefaultAction = item.action
                } else if sel == "duplicateProfile:" {
                    duplicateTarget = item.target
                    duplicateAction = item.action
                }
            }
        }

        [profileList, detailsWrapper, tabView, noProfileSelectedView,
         toggleTagsButton, addButton, removeButton, actionsPopup].forEach {
            parkInLegacyVault($0)
        }

        if let copyToProfileButton, copyToProfileButton.superview !== editorHeader {
            copyToProfileButton.removeFromSuperview()
            copyToProfileButton.controlSize = .small
            editorHeader.addSubview(copyToProfileButton)
        }

        sidebarView.bindModel(model)
        syncCategories()
        reloadProfilesSidebar()
        needsLayout = true
    }

    @objc func reloadProfilesSidebar() {
        let currentGuid = profileList?.selectedGuid
        sidebarView.reloadFromModel(selectedGuid: currentGuid)
        refreshSelectionMetadata()
    }

    private func refreshSelectionMetadata() {
        let guid = profileList?.selectedGuid
        hasSelectedProfile = (guid != nil && !(guid?.isEmpty ?? true)) || editingSession
        let defaultGuid = profileModel?.defaultProfile()?[KEY_GUID] as? String
        let isDefault = (guid != nil && guid == defaultGuid)

        if editingSession {
            defaultBadgePill.isHidden = true
            setDefaultButton.isHidden = true
        } else if hasSelectedProfile {
            defaultBadgePill.isHidden = !isDefault
            setDefaultButton.isHidden = isDefault
        } else {
            defaultBadgePill.isHidden = true
            setDefaultButton.isHidden = true
        }
        needsLayout = true
    }

    @objc func syncCategories() {
        guard let tabView else { return }
        unifiedDocument.syncSections(from: tabView)
        rebuildSectionJumpMenu()
        profileScrollView.needsLayout = true
        needsLayout = true
    }

    @objc func invalidateUnifiedSectionsLayout() {
        unifiedDocument.invalidateFormLayout()
        profileScrollView.needsLayout = true
        needsLayout = true
    }

    @objc func syncSelectedCategory() {
        unifiedDocument.restoreDetachedSectionViewsIfNeeded()
        guard let tabView, let selected = tabView.selectedTabViewItem else { return }
        let idx = tabView.indexOfTabViewItem(selected)
        if idx != NSNotFound {
            scrollToCategory(at: idx)
        }
    }

    @objc func selectCategory(at index: Int) {
        guard let tabView, index >= 0, index < tabView.numberOfTabViewItems else { return }
        tabView.selectTabViewItem(at: index)
        unifiedDocument.restoreDetachedSectionViewsIfNeeded()
        scrollToCategory(at: index)
    }

    @objc func scrollToCategory(at index: Int) {
        profileScrollView.syncDocumentSizeIfNeeded()
        unifiedDocument.layoutSubtreeIfNeeded()
        guard let targetY = unifiedDocument.headingMinY(at: index) else { return }
        let maxScrollY = max(0, unifiedDocument.frame.height - profileScrollView.contentSize.height)
        let clampedY = min(max(0, targetY), maxScrollY)
        profileScrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        profileScrollView.reflectScrolledClipView(profileScrollView.contentView)
    }

    @objc func setSelectedProfileTitle(_ title: String?) {
        selectedProfileLabel.stringValue = title ?? ""
        refreshSelectionMetadata()
        sidebarView.selectGuid(profileList?.selectedGuid, notify: false)
        needsLayout = true
    }

    private func rebuildSectionJumpMenu() {
        let menu = NSMenu()
        let titleItem = NSMenuItem(
            title: NSLocalizedString("Section", comment: "Jump to profile section pull-down title"),
            action: nil,
            keyEquivalent: ""
        )
        titleItem.image = NSImage(systemSymbolName: SFSymbol.listBullet.rawValue,
                                  accessibilityDescription: titleItem.title)
        menu.addItem(titleItem)

        for (idx, section) in unifiedDocument.sections.enumerated() {
            let item = NSMenuItem(title: section.item.label, action: #selector(sectionJumpSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            menu.addItem(item)
        }
        sectionJumpPopup.menu = menu
    }

    @objc private func sectionJumpSelected(_ sender: Any?) {
        let index: Int
        if let menuItem = sender as? NSMenuItem {
            index = menuItem.tag
        } else if let popup = sender as? NSPopUpButton, let selected = popup.selectedItem {
            index = selected.tag
        } else {
            return
        }
        guard index >= 0 else { return }
        scrollToCategory(at: index)
    }

    @objc private func setDefaultClicked(_ sender: Any?) {
        guard let action = setAsDefaultAction else { return }
        NSApp.sendAction(action, to: setAsDefaultTarget, from: self)
        reloadProfilesSidebar()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let detailX: CGFloat
        if editingSession {
            sidebarView.isHidden = true
            detailX = 0
        } else {
            sidebarView.isHidden = false
            let sidebarW = bounds.width < Self.narrowSidebarThreshold
                ? Self.narrowSidebarWidth
                : Self.wideSidebarWidth
            sidebarView.frame = NSRect(x: 0, y: 0, width: min(sidebarW, bounds.width), height: bounds.height)
            sidebarView.layoutSubtreeIfNeeded()
            detailX = sidebarView.frame.maxX
        }

        let detailW = max(0, bounds.width - detailX)
        detailContainer.frame = NSRect(x: detailX, y: 0, width: detailW, height: bounds.height)

        guard hasSelectedProfile else {
            editorHeader.isHidden = true
            profileScrollView.isHidden = true
            emptyStateView.isHidden = false
            emptyStateView.frame = detailContainer.bounds
            let maxLabelW = max(80, detailW - 48)
            let sz = emptyStateLabel.sizeThatFits(NSSize(width: maxLabelW, height: 120))
            emptyStateLabel.frame = NSRect(x: max(0, floor((detailW - maxLabelW) / 2.0)),
                                           y: max(16, floor((bounds.height - sz.height) / 2.0)),
                                           width: maxLabelW,
                                           height: ceil(sz.height))
            return
        }

        emptyStateView.isHidden = true
        editorHeader.isHidden = false
        profileScrollView.isHidden = false

        let headerH = Self.editorHeaderHeight
        editorHeader.frame = NSRect(x: 0, y: 0, width: detailW, height: headerH)
        editorHeaderDivider.frame = NSRect(x: 0, y: headerH - 1, width: detailW, height: 1)
        layoutEditorHeader(width: detailW, height: headerH)

        let scrollH = max(0, bounds.height - headerH)
        profileScrollView.frame = NSRect(x: 0, y: headerH, width: detailW, height: scrollH)
        profileScrollView.syncDocumentSizeIfNeeded()
    }

    private func layoutEditorHeader(width: CGFloat, height: CGFloat) {
        let outerPadding = width >= ProfileFormMetrics.wideThreshold
            ? ProfileFormMetrics.outerPaddingWide
            : ProfileFormMetrics.outerPaddingCompact
        let usableWidth = max(120, width - outerPadding * 2)
        let cardWidth = min(ProfileFormMetrics.maxFormWidth, usableWidth)
        let leftEdge = max(16, floor((width - cardWidth) / 2.0))
        var rightCursor = min(width - 16, leftEdge + cardWidth)

        sectionJumpPopup.sizeToFit()
        let jumpW = min(132, max(84, ceil(sectionJumpPopup.fittingSize.width) + 6))
        let jumpH = max(22, ceil(sectionJumpPopup.fittingSize.height))
        rightCursor -= jumpW
        sectionJumpPopup.frame = NSRect(x: max(leftEdge, rightCursor),
                                        y: floor((height - jumpH) / 2.0),
                                        width: jumpW,
                                        height: jumpH)
        rightCursor -= 8

        if let copyBtn = copyToProfileButton, editingSession, !copyBtn.isHidden {
            copyBtn.sizeToFit()
            let copyW = min(180, ceil(copyBtn.fittingSize.width) + 8)
            let copyH = max(22, ceil(copyBtn.fittingSize.height))
            rightCursor -= copyW
            copyBtn.frame = NSRect(x: max(leftEdge, rightCursor),
                                   y: floor((height - copyH) / 2.0),
                                   width: copyW,
                                   height: copyH)
            rightCursor -= 8
        } else {
            copyToProfileButton?.isHidden = true
        }

        if !setDefaultButton.isHidden {
            setDefaultButton.sizeToFit()
            let btnW = min(140, ceil(setDefaultButton.fittingSize.width) + 8)
            let btnH = max(22, ceil(setDefaultButton.fittingSize.height))
            if rightCursor - btnW > leftEdge + 80 {
                rightCursor -= btnW
                setDefaultButton.frame = NSRect(x: rightCursor,
                                                y: floor((height - btnH) / 2.0),
                                                width: btnW,
                                                height: btnH)
                rightCursor -= 8
            } else {
                setDefaultButton.frame = .zero
            }
        }

        var badgeW: CGFloat = 0
        if !defaultBadgePill.isHidden {
            defaultBadgePill.sizeToFit()
            badgeW = ceil(defaultBadgePill.frame.width) + 14
        }

        let titleText = selectedProfileLabel.stringValue.isEmpty
            ? (editingSession
               ? NSLocalizedString("Current Session", comment: "Header title when editing current session")
               : NSLocalizedString("Profile", comment: "Fallback profile header title"))
            : selectedProfileLabel.stringValue
        if selectedProfileLabel.stringValue.isEmpty && editingSession {
            selectedProfileLabel.stringValue = titleText
        }
        selectedProfileLabel.sizeToFit()
        let titleH = max(20, ceil(selectedProfileLabel.frame.height))
        let availableLeft = max(0, rightCursor - leftEdge)

        if badgeW > 0 && availableLeft > badgeW + 60 {
            let naturalTitleW = min(ceil(selectedProfileLabel.frame.width), availableLeft - badgeW - 8)
            selectedProfileLabel.frame = NSRect(x: leftEdge,
                                                y: floor((height - titleH) / 2.0),
                                                width: max(0, naturalTitleW),
                                                height: titleH)
            defaultBadgePill.frame = NSRect(x: selectedProfileLabel.frame.maxX + 8,
                                            y: floor((height - 20) / 2.0),
                                            width: badgeW,
                                            height: 20)
        } else {
            selectedProfileLabel.frame = NSRect(x: leftEdge,
                                                y: floor((height - titleH) / 2.0),
                                                width: availableLeft,
                                                height: titleH)
            if badgeW > 0 {
                defaultBadgePill.frame = .zero
            }
        }
    }
}
