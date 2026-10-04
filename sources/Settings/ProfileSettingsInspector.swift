import AppKit

/// A bound profile setting, sharing the editor’s identity and navigation.
/// This inspects stored/resolved profile values, never session expressions.
final class ProfileSettingEntry {
    let info: PreferenceInfo
    let key: String
    let title: String
    let path: String
    let document: iTermPreferencesSearchDocument
    weak var owner: iTermProfilePreferencesBaseViewController?

    init(setting: iTermSetting, owner: iTermProfilePreferencesBaseViewController,
         document: iTermPreferencesSearchDocument) {
        info = setting.info
        key = owner.amendedKey(info.key)
        title = document.displayName
        path = setting.pathComponents.joined(separator: " › ")
        self.document = document
        self.owner = owner
    }

    func binding(in profile: [AnyHashable: Any]) -> String? {
        (profile[KEY_BINDINGS] as? [String: String])?[key]
    }
    func value(in profile: [AnyHashable: Any]) -> Any? {
        iTermProfilePreferences.object(forKey: key, inProfile: profile)
    }
    var factoryValue: Any? { iTermProfilePreferences.resolvedFactoryObject(forKey: key) }
    func isDifferent(in profile: [AnyHashable: Any]) -> Bool {
        if binding(in: profile) != nil { return true }
        return !NSObject.object(factoryValue as? NSObject, isNullablyEqualTo: value(in: profile) as? NSObject, epsilon: 0.001)
    }
    func source(in profile: [AnyHashable: Any]) -> String {
        if binding(in: profile) != nil {
            return NSLocalizedString("Expression binding", comment: "Profile setting source")
        }
        return iTermProfilePreferences.valueSource(forKey: key, inProfile: profile)
    }
    func displayValue(in profile: [AnyHashable: Any]) -> String {
        if info.type == .passwordTextField {
            return NSLocalizedString("Hidden", comment: "Protected profile setting")
        }
        return binding(in: profile) ?? display(value(in: profile))
    }
    func display(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else {
            return NSLocalizedString("Unspecified", comment: "Profile setting value")
        }
        if let number = value as? NSNumber,
           info.type == .checkbox || info.type == .invertedCheckbox {
            return number.boolValue ? NSLocalizedString("Yes", comment: "Profile setting value") :
                NSLocalizedString("No", comment: "Profile setting value")
        }
        if let number = value as? NSNumber, let popup = info.control as? NSPopUpButton,
           let item = popup.itemArray.first(where: { $0.tag == number.intValue }) {
            return item.title
        }
        if let value = value as? String, value.isEmpty {
            return NSLocalizedString("Empty string", comment: "Profile setting value")
        }
        if let dictionary = value as? [String: Any], let color = Self.colorDescription(dictionary) {
            return color
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
    private static func colorDescription(_ dictionary: [String: Any]) -> String? {
        let keys = [kEncodedColorDictionaryRedComponent, kEncodedColorDictionaryGreenComponent,
                    kEncodedColorDictionaryBlueComponent]
        let components = keys.compactMap { dictionary[$0] as? Double }
        guard components.count == 3, components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let color = String(format: "#%02X%02X%02X", arguments: components.map { Int(($0 * 255).rounded()) })
        let space = dictionary[kEncodedColorDictionaryColorSpace] as? String ?? kEncodedColorDictionaryCalibratedColorSpace
        let alpha = dictionary[kEncodedColorDictionaryAlphaComponent] as? Double ?? 1
        let opacity = alpha.isFinite && alpha < 1 ? String(format: " · %.0f%%", alpha * 100) : ""
        return color + " · " + space + opacity
    }
    func detailValue(in profile: [AnyHashable: Any]) -> String {
        if info.type == .passwordTextField || binding(in: profile) != nil { return displayValue(in: profile) }
        guard let value = value(in: profile), JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else { return displayValue(in: profile) }
        return text
    }
    func matches(_ query: String) -> Bool {
        let text = [key, title, path].joined(separator: " ")
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

@objc(iTermProfileSettingsInspector)
final class ProfileSettingsInspector: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                                      NSSearchFieldDelegate {
    private final class ContentView: NSView {
        var onLayout: (() -> Void)?
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }
        override func layout() { super.layout(); onLayout?() }
    }
    private let model: ProfileModel
    private let guid: String
    private let entries: [ProfileSettingEntry]
    private var rows: [ProfileSettingEntry] = []
    private var profile: [AnyHashable: Any] = [:]
    private let search = NSSearchField()
    private let differences = NSButton(checkboxWithTitle:
        NSLocalizedString("Only differences from factory", comment: "Profile inspector filter"), target: nil, action: nil)
    private let table = NSTableView()
    private let count = NSTextField(labelWithString: "")
    private let detailTitle = NSTextField(labelWithString: "")
    private let detailSource = NSTextField(labelWithString: "")
    private let detail = NSTextView()
    private let scroll = NSScrollView()
    private let detailScroll = NSScrollView()
    private var emptyState: SettingsEmptyStateView!
    private let explanation = NSTextField(wrappingLabelWithString:
        NSLocalizedString("Profile values are shown before session expressions are evaluated. Restore writes the factory value only to this profile.", comment: "Profile inspector help"))
    private let restore = NSButton(title: NSLocalizedString("Restore Factory Value", comment: "Profile inspector action"), target: nil, action: nil)
    private let reveal = NSButton(title: NSLocalizedString("Show in Settings", comment: "Profile inspector action"), target: nil, action: nil)
    private let done = NSButton(title: NSLocalizedString("Done", comment: "Profile inspector action"), target: nil, action: nil)

    @objc init(settings: [iTermSetting], controllers: [iTermProfilePreferencesBaseViewController],
               model: ProfileModel, guid: String) {
        self.model = model
        self.guid = guid
        var seen = Set<String>()
        var catalog: [ProfileSettingEntry] = []
        for setting in settings {
            let info = setting.info
            guard info.syntheticGetter == nil, info.syntheticSetter == nil,
                  let owner = controllers.first(where: { $0.safeInfo(forControl: info.control) === info }),
                  let document = owner.searchableViewControllerDocuments().first(where: { $0.identifier == info.key }) else { continue }
            let entry = ProfileSettingEntry(setting: setting, owner: owner, document: document)
            guard seen.insert(entry.key).inserted else { continue }
            catalog.append(entry)
        }
        entries = catalog.sorted { ($0.path, $0.title, $0.key) < ($1.path, $1.title, $1.key) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.contentMinSize = NSSize(width: 780, height: 560)
        window.title = NSLocalizedString("Inspect Profile Settings", comment: "Profile inspector title")
        buildContent()
        for notification in [Notification.Name(kReloadAllProfiles), .reloadAddressBook,
                             Notification.Name(iTermAdvancedSettingsDidChange)] {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: notification, object: nil)
        }
        reload()
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildContent() {
        guard let window else { return }
        let content = ContentView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizesSubviews = false
        content.onLayout = { [weak self] in self?.layoutContent() }
        window.contentView = content
        search.placeholderString = NSLocalizedString("Search profile settings", comment: "Profile inspector search")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        differences.state = .on
        differences.target = self
        differences.action = #selector(reload)
        count.textColor = .secondaryLabelColor
        count.lineBreakMode = .byTruncatingTail
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.frame = scroll.bounds
        table.rowHeight = 52
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (identifier, title, width) in [
            ("setting", NSLocalizedString("Setting", comment: "Profile inspector column"), 330.0),
            ("value", NSLocalizedString("Profile Value", comment: "Profile inspector column"), 235.0),
            ("factory", NSLocalizedString("Factory Value", comment: "Profile inspector column"), 235.0)
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        table.setAccessibilityLabel(NSLocalizedString("Profile settings", comment: "Inspector table accessibility"))
        emptyState = SettingsEmptyStateView(scrollView: scroll)
        detailTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        detailTitle.lineBreakMode = .byTruncatingTail
        detailSource.font = .systemFont(ofSize: 11)
        detailSource.textColor = .secondaryLabelColor
        detailSource.lineBreakMode = .byTruncatingTail
        detailSource.isSelectable = true
        detailScroll.borderType = .bezelBorder
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.documentView = detail
        detail.isEditable = false
        detail.isSelectable = true
        detail.isRichText = false
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .labelColor
        detail.backgroundColor = .textBackgroundColor
        detail.textContainerInset = NSSize(width: 6, height: 6)
        detail.isVerticallyResizable = true
        detail.isHorizontallyResizable = false
        detail.autoresizingMask = [.width]
        detail.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detail.textContainer?.widthTracksTextView = true
        detail.setAccessibilityLabel(NSLocalizedString("Full profile value", comment: "Inspector detail accessibility"))
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        restore.bezelStyle = .rounded
        restore.target = self
        restore.action = #selector(restoreSelected)
        reveal.bezelStyle = .rounded
        reveal.target = self
        reveal.action = #selector(revealSelected)
        done.target = self
        done.action = #selector(dismiss)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        for view in [search, differences, count, scroll, detailTitle, detailSource, detailScroll,
                     explanation, restore, reveal, done] { content.addSubview(view) }
        window.initialFirstResponder = search
        layoutContent()
    }

    private func layoutContent() {
        guard let bounds = window?.contentView?.bounds else { return }
        let width = max(0, bounds.width - 40)
        let filterWidth = max(250, min(310, differences.fittingSize.width + 8))
        search.frame = NSRect(x: 20, y: bounds.height - 52, width: width - filterWidth - 20, height: 28)
        differences.frame = NSRect(x: bounds.width - 20 - filterWidth, y: bounds.height - 52, width: filterWidth, height: 28)
        count.frame = NSRect(x: 20, y: bounds.height - 82, width: width, height: 20)
        scroll.frame = NSRect(x: 20, y: 234, width: width, height: max(0, bounds.height - 324))
        let tableWidth = scroll.contentSize.width
        for (column, fraction) in zip(table.tableColumns, [0.40, 0.30, 0.30]) { column.width = tableWidth * fraction }
        detailTitle.frame = NSRect(x: 20, y: 204, width: width, height: 22)
        detailSource.frame = NSRect(x: 20, y: 183, width: width, height: 18)
        detailScroll.frame = NSRect(x: 20, y: 100, width: width, height: 76)
        detail.frame.size.width = detailScroll.contentSize.width
        detail.minSize = NSSize(width: 0, height: detailScroll.contentSize.height)
        explanation.frame = NSRect(x: 20, y: 56, width: width, height: 38)
        restore.frame = NSRect(x: 20, y: 16, width: 210, height: 32)
        reveal.frame = NSRect(x: 242, y: 16, width: 190, height: 32)
        done.frame = NSRect(x: bounds.width - 130, y: 16, width: 110, height: 32)
    }

    @objc private func reload() {
        let selectedKey = selected?.key
        profile = model.bookmark(withGuid: guid) ?? [:]
        rows = profile.isEmpty ? [] : entries.filter {
            $0.matches(search.stringValue) && (differences.state != .on || $0.isDifferent(in: profile))
        }
        let name = profile[KEY_NAME] as? String ?? NSLocalizedString("Profile unavailable", comment: "Profile inspector missing profile")
        count.stringValue = String(format: NSLocalizedString("%@ — %ld settings", comment: "Profile inspector result count"), name, rows.count)
        count.toolTip = count.stringValue
        table.reloadData()
        if let selectedKey, let index = rows.firstIndex(where: { $0.key == selectedKey }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        updateSelection()
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyState.isHidden = !rows.isEmpty
        guard rows.isEmpty else { return }
        emptyState.onAction = nil
        if profile.isEmpty {
            emptyState.show(title: NSLocalizedString("Profile unavailable", comment: "Profile inspector missing profile"),
                            message: NSLocalizedString("This profile was removed. Close the inspector to select another profile.", comment: "Inspector empty state"), actionTitle: nil)
        } else if !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState.show(title: NSLocalizedString("No matching profile settings", comment: "Profile inspector empty state"),
                            message: NSLocalizedString("Try another setting name or key, or clear the search.", comment: "Inspector empty state"),
                            actionTitle: NSLocalizedString("Clear Search", comment: "Inspector empty state action"))
            emptyState.onAction = { [weak self] in self?.search.stringValue = ""; self?.reload() }
        } else {
            emptyState.show(title: NSLocalizedString("No differences from factory", comment: "Inspector empty state"),
                            message: NSLocalizedString("Show all settings to inspect unchanged values too.", comment: "Inspector empty state"),
                            actionTitle: NSLocalizedString("Show All Settings", comment: "Inspector empty state action"))
            emptyState.onAction = { [weak self] in self?.differences.state = .off; self?.reload() }
        }
    }

    private var selected: ProfileSettingEntry? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
    }
    private func updateSelection() {
        guard let selected else {
            detailTitle.stringValue = NSLocalizedString("Select a setting to inspect its source and factory value.", comment: "Profile inspector selection help")
            detailSource.stringValue = ""
            detail.string = ""
            restore.isEnabled = false
            reveal.isEnabled = false
            return
        }
        let source = selected.source(in: profile)
        detailTitle.stringValue = selected.title
        detailTitle.toolTip = selected.title
        detailSource.stringValue = "\(source) · \(selected.key)"
        detailSource.toolTip = detailSource.stringValue
        detail.string = selected.detailValue(in: profile)
        detail.scrollToBeginningOfDocument(nil)
        reveal.isEnabled = matchesCurrentOwner(selected)
        restore.isEnabled = canRestore(selected)
        restore.toolTip = restore.isEnabled ? nil : !selected.isDifferent(in: profile) ?
            NSLocalizedString("Already at the factory value.", comment: "Profile inspector reset help") :
            NSLocalizedString("Use the setting’s editor for bindings, dependent settings, and special actions.", comment: "Profile inspector reset help")
    }
    private func matchesCurrentOwner(_ entry: ProfileSettingEntry) -> Bool {
        guard let owner = entry.owner,
              let current = owner.delegate?.profilePreferencesCurrentProfile(),
              current[KEY_GUID] as? String == guid,
              owner.amendedKey(entry.info.key) == entry.key else { return false }
        return true
    }
    private func canRestore(_ entry: ProfileSettingEntry) -> Bool {
        matchesCurrentOwner(entry) && (entry.owner?.canRestoreFactoryValue(for: entry.info) ?? false)
    }
    @objc private func restoreSelected() {
        guard let selected, canRestore(selected) else { reload(); return }
        _ = selected.owner?.restoreFactoryValue(for: selected.info)
        reload()
    }
    @objc private func revealSelected() {
        guard let selected, let owner = selected.owner,
              owner.delegate?.profilePreferencesCurrentProfile()[KEY_GUID] as? String == guid else { return }
        dismiss()
        var changing = ObjCBool(false)
        _ = owner.searchableViewControllerRevealItem(for: selected.document, forQuery: "", willChangeTab: &changing)
    }
    @objc private func dismiss() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
    }
    override func cancelOperation(_ sender: Any?) { dismiss() }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let width = tableColumn?.width ?? 300
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "value": text = entry.displayValue(in: profile)
        case "factory": text = entry.info.type == .passwordTextField ? NSLocalizedString("Hidden", comment: "Protected profile setting") : entry.display(entry.factoryValue)
        default: text = entry.title
        }
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 6, y: 27, width: width - 12, height: 18)
        label.lineBreakMode = .byTruncatingTail
        label.autoresizingMask = [.width]
        cell.addSubview(label)
        if tableColumn?.identifier.rawValue == "setting" {
            let path = NSTextField(labelWithString: entry.path)
            path.frame = NSRect(x: 6, y: 7, width: width - 12, height: 16)
            path.font = .systemFont(ofSize: 11)
            path.textColor = .secondaryLabelColor
            path.lineBreakMode = .byTruncatingTail
            path.autoresizingMask = [.width]
            cell.addSubview(path)
        } else if tableColumn?.identifier.rawValue == "value" {
            let source = NSTextField(labelWithString: entry.source(in: profile))
            source.frame = NSRect(x: 6, y: 7, width: width - 12, height: 16)
            source.font = .systemFont(ofSize: 11)
            source.textColor = .secondaryLabelColor
            source.lineBreakMode = .byTruncatingTail
            source.autoresizingMask = [.width]
            cell.addSubview(source)
        }
        cell.textField = label
        cell.toolTip = [entry.title, entry.path, entry.key, text, entry.source(in: profile)].joined(separator: "\n")
        return cell
    }
}
