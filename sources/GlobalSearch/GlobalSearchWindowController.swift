//
//  GlobalSearchWindowController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import Cocoa

/// Window controller for searching across all open terminal sessions.
@objc(iTermGlobalSearchWindowController)
class GlobalSearchWindowController: NSWindowController,
                                    iTermFocusReportingSearchFieldDelegate,
                                    NSOutlineViewDelegate,
                                    NSOutlineViewDataSource,
                                    NSWindowDelegate {
    private var engine: GlobalSearchEngine?
    private var resultsBySessionGUID: [String: [GlobalSearchResultProtocol]]?
    @IBOutlet private var _searchField: iTermFocusReportingSearchField!
    @IBOutlet private var _findType: NSPopUpButton!
    @IBOutlet private var _outlineView: NSOutlineView!
    @IBOutlet private var _panel: NSPanel!
    private var ignoreClick = false
    private var animationTimer: Timer?
    private let screenState = NSMutableDictionary()

    @objc convenience init() {
        self.init(windowNibName: "iTermGlobalSearch")
    }

    deinit {
        animationTimer?.invalidate()
        restoreAlternateScreens(announce: true)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        window?.level = .floating
        _outlineView.expandItem(nil, expandChildren: true)
        _panel.becomesKeyOnlyIfNeeded = true
        _findType.selectItem(withTag: Int(iTermUserDefaults.globalSearchMode))
        _outlineView.target = self
        _outlineView.action = #selector(didClick(_:))
    }

    func windowWillClose(_ notification: Notification) {
        restoreAlternateScreens(announce: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(_searchField)
    }

    /// Brings the global search panel to the front and focuses its search field.
    @objc func activate() {
        window?.makeKeyAndOrderFront(nil)
        _searchField.window?.makeFirstResponder(_searchField)
    }

    @IBAction func closeCurrentSession(_ sender: Any?) {
        close()
    }

    @objc func closeWindow(_ sender: Any?) {
        close()
    }

    @objc func autoHidesHotKeyWindow() -> Bool {
        return false
    }

    @IBAction func modeDidChange(_ sender: Any?) {
        search(nil)
        iTermUserDefaults.globalSearchMode = UInt(_findType.selectedTag())
    }

    private var mode: iTermFindMode {
        return iTermFindMode(rawValue: UInt(max(0, _findType.selectedTag()))) ?? .smartCaseSensitivity
    }

    @IBAction func search(_ sender: Any?) {
        engine?.stop()
        resultsBySessionGUID = [:]
        setFraction(0)
        _outlineView.reloadData()
        guard !_searchField.stringValue.isEmpty else {
            return
        }
        engine = GlobalSearchEngine(
            query: _searchField.stringValue,
            sessions: sessions,
            mode: mode) { [weak self] session, results, progress in
                self?.addResults(results ?? [], for: session, progress: progress)
        }
    }

    @objc func didClick(_ sender: Any?) {
        guard !ignoreClick else { return }
        revealSelection()
    }

    // MARK: - iTermFocusReportingSearchFieldDelegate

    func focusReportingSearchFieldWillBecomeFirstResponder(_ sender: iTermFocusReportingSearchField) {
    }

    func focusReportingSearchFieldNumber(ofResults sender: iTermFocusReportingSearchField) -> Int {
        guard let resultsBySessionGUID else { return 0 }
        return resultsBySessionGUID.values.reduce(0) { $0 + $1.count }
    }

    func focusReportingSearchFieldCurrentIndex(_ sender: iTermFocusReportingSearchField) -> Int {
        let row = _outlineView.selectedRow
        guard row >= 0,
              let item = _outlineView.item(atRow: row),
              let result = item as? GlobalSearchResultProtocol,
              let targetGUID = result.session?.guid,
              let resultsBySessionGUID else {
            return 0
        }
        var offset = 0
        for guid in sortedNonEmptyResultSessionGUIDs {
            let items = resultsBySessionGUID[guid] ?? []
            if guid != targetGUID {
                offset += items.count
            } else if let subindex = items.firstIndex(where: { ($0 as AnyObject) === (result as AnyObject) }) {
                return offset + subindex + 1
            } else {
                return 0
            }
        }
        return 0
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        if let guid = item as? String {
            return makeSessionCellView(in: outlineView, guid: guid)
        }
        if let foldGroup = item as? GlobalSearchFoldGroup {
            return makeFoldGroupCellView(in: outlineView, foldGroup: foldGroup)
        }
        guard let result = item as? GlobalSearchResultProtocol else {
            it_fatalError("Bad global search outline item \(item)")
        }
        return makeResultCellView(in: outlineView, result: result)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        ignoreClick = true
        DispatchQueue.main.async { [weak self] in
            self?.ignoreClick = false
        }
        revealSelection()
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nonEmptyResults.count
        }
        if let guid = item as? String {
            return resultsBySessionGUID?[guid]?.count ?? 0
        }
        if let group = item as? GlobalSearchFoldGroup {
            return group.results.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sortedNonEmptyResultSessionGUIDs[index] as NSString
        }
        if let guid = item as? String {
            let items = resultsBySessionGUID?[guid]
            it_assert(items != nil && index >= 0 && index < (items?.count ?? 0))
            return items![index]
        }
        if let group = item as? GlobalSearchFoldGroup {
            return group.results[index]
        }
        it_fatalError("Unexpected outline parent \(String(describing: item))")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is String || item is GlobalSearchFoldGroup
    }

    // MARK: - Private

    private var sessions: [PTYSession] {
        let terminals = iTermController.sharedInstance().terminals() ?? []
        return terminals.flatMap { terminal -> [PTYSession] in
            let tabs = terminal.tabs() ?? []
            return tabs.flatMap { $0.sessions() ?? [] }
        }
    }

    private var nonEmptyResults: [String: [GlobalSearchResultProtocol]] {
        return (resultsBySessionGUID ?? [:]).filter { !$0.value.isEmpty }
    }

    private var sortedNonEmptyResultSessionGUIDs: [String] {
        return nonEmptyResults.keys.sorted { $0.compare($1) == .orderedAscending }
    }

    private func setFraction(_ progress: Double) {
        guard let cell = _searchField.cell as? iTermSearchFieldCell else { return }
        if round(progress * 100) != round(Double(cell.fraction) * 100) {
            _searchField.needsDisplay = true
        }
        cell.fraction = CGFloat(progress)
        if cell.needsAnimation && animationTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.redrawSearchField()
            }
            timer.tolerance = 1.0 / 600.0
            animationTimer = timer
        }
    }

    private func redrawSearchField() {
        guard let cell = _searchField.cell as? iTermSearchFieldCell else { return }
        cell.willAnimate()
        if !cell.needsAnimation {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        _searchField.needsDisplay = true
    }

    private func addResults(_ results: [GlobalSearchResultProtocol],
                            for session: PTYSession?,
                            progress: Double) {
        guard let session else {
            // Finished searching.
            setFraction(1)
            return
        }
        setFraction(progress)
        guard !results.isEmpty else { return }

        if resultsBySessionGUID == nil {
            resultsBySessionGUID = [:]
        }
        let guid = session.guid
        let existing = resultsBySessionGUID?[guid]
        let isNew = (existing == nil)
        let startIndex = existing?.count ?? 0
        var updated = existing ?? []
        updated.append(contentsOf: results)

        _outlineView.beginUpdates()
        resultsBySessionGUID?[guid] = updated
        let indexes = IndexSet(integersIn: startIndex..<(startIndex + results.count))
        var expand = false
        let parentItem = guid as NSString
        if isNew, let sessionIndex = sortedNonEmptyResultSessionGUIDs.firstIndex(of: guid) {
            _outlineView.insertItems(at: IndexSet(integer: sessionIndex),
                                     inParent: nil,
                                     withAnimation: [])
            expand = true
        }
        _outlineView.insertItems(at: indexes, inParent: parentItem, withAnimation: [])
        if expand {
            _outlineView.expandItem(parentItem, expandChildren: true)
        }
        _outlineView.endUpdates()
        _searchField.needsDisplay = true
    }

    private func revealSelection() {
        _searchField.needsDisplay = true
        let row = _outlineView.selectedRow
        guard row >= 0, let item = _outlineView.item(atRow: row) else {
            restoreAlternateScreens(announce: true)
            return
        }
        if let guid = item as? String {
            let session = iTermController.sharedInstance().anySession(withGUID: guid)
            restoreAlternateScreens(announce: true)
            session?.reveal()
            return
        }
        guard let result = item as? GlobalSearchResultProtocol else {
            restoreAlternateScreens(announce: true)
            return
        }
        // Toggle expansion for fold groups instead of revealing/unfolding them.
        if item is GlobalSearchFoldGroup {
            if _outlineView.isItemExpanded(item) {
                _outlineView.collapseItem(item)
            } else {
                _outlineView.expandItem(item)
            }
            return
        }
        result.session?.reveal()
        result.reveal(withState: screenState) { [weak self] hull in
            if hull.width > 0 && hull.height > 0 {
                self?.movePanelAway(from: hull)
            }
        }
    }

    private func movePanelAway(from hull: NSRect) {
        let windowRect = _panel.frame
        guard windowRect.intersects(hull) else { return }

        let candidates = [
            NSRect(x: hull.minX - windowRect.width, y: windowRect.minY, width: windowRect.width, height: windowRect.height),
            NSRect(x: hull.maxX, y: windowRect.minY, width: windowRect.width, height: windowRect.height),
            NSRect(x: windowRect.minX, y: hull.maxY, width: windowRect.width, height: windowRect.height),
            NSRect(x: windowRect.minX, y: hull.minY - windowRect.height, width: windowRect.width, height: windowRect.height)
        ]
        let screenFrame = _panel.screen?.visibleFrame ?? .zero
        let totalArea = windowRect.width * windowRect.height
        var bestAreaOffScreen = CGFloat.infinity
        var bestDistance = CGFloat.infinity
        var bestRect: NSRect?

        for candidate in candidates {
            let onScreenRect = candidate.intersection(screenFrame)
            let onScreenArea = onScreenRect.isNull ? 0 : onScreenRect.width * onScreenRect.height
            let areaOffScreen = totalArea - onScreenArea
            let dx = windowRect.origin.x - candidate.origin.x
            let dy = windowRect.origin.y - candidate.origin.y
            let distance = hypot(dx, dy)
            if areaOffScreen < bestAreaOffScreen || (areaOffScreen == bestAreaOffScreen && distance < bestDistance) {
                bestAreaOffScreen = areaOffScreen
                bestDistance = distance
                bestRect = candidate
            }
        }
        if let bestRect {
            _panel.setFrame(bestRect, display: true, animate: true)
        }
    }

    private func restoreAlternateScreens(announce: Bool) {
        GlobalSearchResult.restoreAlternateScreens(withAnnouncement: announce, state: screenState)
    }

    private func makeSessionCellView(in outlineView: NSOutlineView, guid: String) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("GlobalSearchSessionIdentifier")
        let view: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            view = reused
        } else {
            view = NSTableCellView()
            let textField = NSTextField.it_textFieldForTableView(withIdentifier: identifier.rawValue)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            view.textField = textField
            view.addSubview(textField)
            view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[textField]-0-|",
                                                               options: [],
                                                               metrics: nil,
                                                               views: ["textField": textField]))
            view.addConstraint(NSLayoutConstraint(item: textField,
                                                  attribute: .centerY,
                                                  relatedBy: .equal,
                                                  toItem: view,
                                                  attribute: .centerY,
                                                  multiplier: 1,
                                                  constant: 0))
            textField.frame = view.bounds
            textField.autoresizingMask = [.width, .height]
        }
        let sessionName = iTermController.sharedInstance().session(withGUID: guid)?.name.removingHTMLFromTabTitleIfNeeded()
        view.textField?.stringValue = sessionName ?? "Session"
        return view
    }

    private func makeFoldGroupCellView(in outlineView: NSOutlineView, foldGroup: GlobalSearchFoldGroup) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("GlobalSearchFoldGroupIdentifier")
        let view: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            view = reused
        } else {
            view = NSTableCellView()
            let image = NSImage(systemSymbolName: SFSymbol.rectangleCompressVertical.rawValue,
                                accessibilityDescription: "Folded region")
            let imageView = NSImageView(image: image ?? NSImage())
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentTintColor = .secondaryLabelColor
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            view.imageView = imageView
            view.addSubview(imageView)

            let textField = NSTextField.it_textFieldForTableView(withIdentifier: identifier.rawValue)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            view.textField = textField
            view.addSubview(textField)

            let views: [String: Any] = ["icon": imageView, "textField": textField]
            view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[icon]-4-[textField]-0-|",
                                                               options: [],
                                                               metrics: nil,
                                                               views: views))
            view.addConstraint(NSLayoutConstraint(item: imageView,
                                                  attribute: .centerY,
                                                  relatedBy: .equal,
                                                  toItem: view,
                                                  attribute: .centerY,
                                                  multiplier: 1,
                                                  constant: 0))
            view.addConstraint(NSLayoutConstraint(item: textField,
                                                  attribute: .centerY,
                                                  relatedBy: .equal,
                                                  toItem: view,
                                                  attribute: .centerY,
                                                  multiplier: 1,
                                                  constant: 0))
        }
        view.textField?.attributedStringValue = foldGroup.snippet
        return view
    }

    private func makeResultCellView(in outlineView: NSOutlineView, result: GlobalSearchResultProtocol) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("GlobalSearchResultIdentifier")
        let view: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            view = reused
        } else {
            view = NSTableCellView()
            let textField = NSTextField.it_textFieldForTableView(withIdentifier: identifier.rawValue)
            textField.translatesAutoresizingMaskIntoConstraints = false
            view.textField = textField
            view.addSubview(textField)
            view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[textField]-0-|",
                                                               options: [],
                                                               metrics: nil,
                                                               views: ["textField": textField]))
            view.addConstraint(NSLayoutConstraint(item: textField,
                                                  attribute: .bottom,
                                                  relatedBy: .equal,
                                                  toItem: view,
                                                  attribute: .bottom,
                                                  multiplier: 1,
                                                  constant: 0))
            textField.frame = view.bounds
            textField.autoresizingMask = [.width, .height]
        }
        view.textField?.attributedStringValue = result.snippet
        return view
    }
}
