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
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
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
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let explanation = NSTextField(wrappingLabelWithString:
        NSLocalizedString("Profile values are shown before session expressions are evaluated. Restore writes the factory value only to this profile.", comment: "Profile inspector help"))
    private let restore = NSButton(title: NSLocalizedString("Restore Factory Value", comment: "Profile inspector action"), target: nil, action: nil)
    private let reveal = NSButton(title: NSLocalizedString("Show in Settings", comment: "Profile inspector action"), target: nil, action: nil)

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
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
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
        guard let content = window?.contentView else { return }
        search.frame = NSRect(x: 20, y: 566, width: 490, height: 28)
        search.placeholderString = NSLocalizedString("Search profile settings", comment: "Profile inspector search")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        differences.frame = NSRect(x: 530, y: 566, width: 310, height: 28)
        differences.state = .on
        differences.target = self
        differences.action = #selector(reload)
        count.frame = NSRect(x: 20, y: 536, width: 820, height: 20)
        count.textColor = .secondaryLabelColor
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 186, width: 820, height: 342))
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
        detail.frame = NSRect(x: 20, y: 112, width: 820, height: 64)
        detail.isSelectable = true
        explanation.frame = NSRect(x: 20, y: 64, width: 820, height: 42)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        restore.frame = NSRect(x: 20, y: 18, width: 210, height: 32)
        restore.bezelStyle = .rounded
        restore.target = self
        restore.action = #selector(restoreSelected)
        reveal.frame = NSRect(x: 242, y: 18, width: 190, height: 32)
        reveal.bezelStyle = .rounded
        reveal.target = self
        reveal.action = #selector(revealSelected)
        let done = NSButton(title: NSLocalizedString("Done", comment: "Profile inspector action"), target: self, action: #selector(dismiss))
        done.frame = NSRect(x: 730, y: 18, width: 110, height: 32)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        for view in [search, differences, count, scroll, detail, explanation, restore, reveal, done] { content.addSubview(view) }
        window?.initialFirstResponder = search
    }

    @objc private func reload() {
        let selectedKey = selected?.key
        profile = model.bookmark(withGuid: guid) ?? [:]
        rows = profile.isEmpty ? [] : entries.filter {
            $0.matches(search.stringValue) && (differences.state != .on || $0.isDifferent(in: profile))
        }
        let name = profile[KEY_NAME] as? String ?? NSLocalizedString("Profile unavailable", comment: "Profile inspector missing profile")
        count.stringValue = String(format: NSLocalizedString("%@ — %ld settings", comment: "Profile inspector result count"), name, rows.count)
        table.reloadData()
        if let selectedKey, let index = rows.firstIndex(where: { $0.key == selectedKey }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        updateSelection()
    }

    private var selected: ProfileSettingEntry? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil
    }
    private func updateSelection() {
        guard let selected else {
            detail.stringValue = rows.isEmpty ? NSLocalizedString("No matching profile settings", comment: "Profile inspector empty state") :
                NSLocalizedString("Select a setting to inspect its source and factory value.", comment: "Profile inspector selection help")
            restore.isEnabled = false
            reveal.isEnabled = false
            return
        }
        let source = selected.source(in: profile)
        detail.stringValue = "\(selected.key)\n\(source)\n\(selected.displayValue(in: profile))"
        detail.toolTip = detail.stringValue
        reveal.isEnabled = selected.owner != nil
        restore.isEnabled = canRestore(selected)
        restore.toolTip = restore.isEnabled ? nil :
            NSLocalizedString("Use the setting’s editor for bindings, dependent settings, and special actions.", comment: "Profile inspector reset help")
    }
    private func canRestore(_ entry: ProfileSettingEntry) -> Bool {
        guard let owner = entry.owner,
              let current = owner.delegate?.profilePreferencesCurrentProfile(),
              current[KEY_GUID] as? String == guid,
              owner.amendedKey(entry.info.key) == entry.key else { return false }
        return owner.canRestoreFactoryValue(for: entry.info)
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
