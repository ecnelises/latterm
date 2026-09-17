import AppKit

/// Grouped navigation shares the window’s titlebar surface. Pages retain their
/// stable identities independently of visual group headings and row positions.
@objc(iTermSettingsSidebarView)
final class SettingsSidebarView: NSVisualEffectView, NSTableViewDataSource, NSTableViewDelegate {
    @objc static let preferredWidth: CGFloat = 224
    @objc var onSelect: ((SettingsPage) -> Void)?

    private enum Entry {
        case group(SettingsGroup)
        case page(SettingsPage)
    }
    private let pages: [SettingsPage]
    private let entries: [Entry]
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField: NSSearchField
    private let brand = NSTextField(labelWithString: "Latterm")
    private var selectingProgrammatically = false

    private final class Row: NSTableRowView {
        override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
        override func drawSelection(in dirtyRect: NSRect) {
            guard isSelected else { return }
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
    }

    @objc init(pages: [SettingsPage], searchField: NSSearchField) {
        self.searchField = searchField
        self.pages = pages
        entries = SettingsGroup.allCases.flatMap { group -> [Entry] in
            let members = pages.filter { $0.group == group }
            return members.isEmpty ? [] : [.group(group)] + members.map { .page($0) }
        }
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        autoresizingMask = [.height]

        brand.font = .systemFont(ofSize: 13, weight: .semibold)
        brand.textColor = .secondaryLabelColor
        addSubview(brand)
        searchField.focusRingType = .none
        searchField.controlSize = .regular
        searchField.placeholderString = NSLocalizedString("Search Settings", comment: "Settings search")
        addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SettingsCategory"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(NSLocalizedString("Settings categories", comment: "Settings navigation"))
        tableView.setAccessibilityIdentifier("SettingsSidebar")
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        it_fatalError("SettingsSidebarView must be created with its categories")
    }

    override func layout() {
        super.layout()
        // Keep the native traffic lights unobstructed in the unified titlebar.
        brand.frame = NSRect(x: 84, y: bounds.height - 30, width: bounds.width - 100, height: 18)
        searchField.frame = NSRect(x: 16, y: bounds.height - 83, width: bounds.width - 32, height: 28)
        scrollView.frame = NSRect(x: 10, y: 16, width: bounds.width - 20, height: max(0, bounds.height - 113))
        tableView.frame.size.width = scrollView.contentSize.width
        tableView.tableColumns.first?.width = scrollView.contentSize.width
    }

    @objc var selectedIndex: Int {
        guard entries.indices.contains(tableView.selectedRow), case .page(let page) = entries[tableView.selectedRow] else { return -1 }
        return pages.firstIndex(where: { $0 === page }) ?? -1
    }

    @objc func row(for page: SettingsPage) -> Int {
        entries.firstIndex {
            if case .page(let candidate) = $0 { return candidate === page }
            return false
        } ?? -1
    }

    /// Search and programmatic deep links must not re-enter the user callback.
    @objc func selectPage(_ page: SettingsPage?) {
        guard let page else { return }
        let index = row(for: page)
        guard index >= 0 else { return }
        selectingProgrammatically = true
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        selectingProgrammatically = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .page = entries[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .group = entries[row] { return 30 }
        return 36
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 36))
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.autoresizingMask = [.width]
        cell.addSubview(text)
        cell.textField = text
        switch entries[row] {
        case .group(let group):
            text.stringValue = group.title
            text.font = .systemFont(ofSize: 11, weight: .semibold)
            text.textColor = .secondaryLabelColor
            text.frame = NSRect(x: 10, y: 4, width: max(0, tableView.bounds.width - 20), height: 16)
        case .page(let page):
            text.stringValue = page.title
            text.frame = NSRect(x: 38, y: 9, width: max(0, tableView.bounds.width - 46), height: 18)
            let icon = NSImageView(frame: NSRect(x: 12, y: 9, width: 18, height: 18))
            icon.image = page.image
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            cell.addSubview(icon)
            cell.imageView = icon
            cell.toolTip = page.title
            style(cell, selected: row == tableView.selectedRow)
        }
        return cell
    }

    private func style(_ cell: NSTableCellView, selected: Bool) {
        cell.textField?.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        cell.textField?.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        cell.imageView?.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { Row() }

    func tableViewSelectionDidChange(_ notification: Notification) {
        for row in entries.indices {
            guard case .page = entries[row],
                  let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
            style(cell, selected: row == tableView.selectedRow)
        }
        guard !selectingProgrammatically, entries.indices.contains(tableView.selectedRow),
              case .page(let page) = entries[tableView.selectedRow] else { return }
        onSelect?(page)
    }
}
