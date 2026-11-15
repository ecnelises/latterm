import AppKit
import SwiftUI

/// Hosts one task-oriented SwiftUI workspace. The hidden NIB views retain the
/// existing profile controllers and actions while the workspace owns presentation.
@objc(iTermSettingsProfilesView)
final class SettingsProfilesView: NSView {
    override var isFlipped: Bool { true }
    @objc var editingSession = false { didSet { scheduleRefresh() } }
    @objc var isInSplitMode: Bool { false }

    private let state = ProfileWorkspaceModel()
    private lazy var host = NSHostingView(rootView: ProfileWorkspace(model: state))
    private let controllerStorage = NSView()
    private weak var profileList: ProfileListView?
    private weak var model: ProfileModel?
    private weak var tabs: NSTabView?
    private weak var addButton: NSButton?
    private weak var removeButton: NSButton?
    private weak var copyButton: NSButton?
    private weak var actions: NSPopUpButton?
    private var observers: [NSObjectProtocol] = []
    private var refreshScheduled = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        installWorkspace()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installWorkspace()
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    private func installWorkspace() {
        autoresizesSubviews = false
        controllerStorage.isHidden = true
        controllerStorage.setAccessibilityIdentifier("ProfileControllerStorage")
        addSubview(controllerStorage)
        host.setAccessibilityIdentifier("ProfileWorkspaceHost")
        addSubview(host)
        state.onSelect = { [weak self] guid in
            guard let self, guid != self.profileList?.selectedGuid else { return }
            if self.profileList?.searchFieldHasText() == true { self.profileList?.eraseQuery() }
            self.profileList?.selectRow(byGuid: guid)
            self.scheduleRefresh()
        }
        state.onAdd = { [weak self] in self?.sendButton(self?.addButton) }
        state.onRemove = { [weak self] in self?.sendButton(self?.removeButton) }
        state.onDuplicate = { [weak self] in self?.sendMenuAction("duplicateProfile:") }
        state.onDefault = { [weak self] in self?.sendMenuAction("setAsDefault:") }
        state.onCopy = { [weak self] in self?.sendButton(self?.copyButton) }
        for name in [Notification.Name.reloadAddressBook, Notification.Name(kReloadAllProfiles),
                     .profileWasDeleted, Notification.Name(kPreferencePanelDidUpdateProfileFields)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefresh()
            })
        }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard subview.accessibilityIdentifier() != "ProfileWorkspaceHost",
              subview.accessibilityIdentifier() != "ProfileControllerStorage" else { return }
        if let button = subview as? NSButton, button.action.map(NSStringFromSelector) == "copyToProfile:" {
            copyButton = button
        }
        store(subview)
    }
    private func store(_ view: NSView) {
        guard view !== controllerStorage, view.superview !== controllerStorage else { return }
        view.removeFromSuperview()
        controllerStorage.addSubview(view)
    }
    private func sendButton(_ button: NSButton?) {
        guard let button, button.isEnabled, let action = button.action else { return }
        NSApp.sendAction(action, to: button.target, from: button)
        scheduleRefresh()
    }
    private func sendMenuAction(_ selector: String) {
        guard let item = actions?.menu?.items.first(where: { $0.action.map(NSStringFromSelector) == selector }),
              let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        scheduleRefresh()
    }

    @objc func configureMasterDetail(profileList: ProfileListView, model: ProfileModel?,
                                     detailsWrapper: NSView, tabView: NSTabView,
                                     noProfileSelectedView: NSView, toggleTagsButton: NSButton,
                                     addButton: NSButton, removeButton: NSButton,
                                     actionsPopup: NSPopUpButton, copyToProfileButton: NSButton?) {
        self.profileList = profileList
        self.model = model
        tabs = tabView
        self.addButton = addButton
        self.removeButton = removeButton
        actions = actionsPopup
        copyButton = copyToProfileButton
        [profileList, detailsWrapper, tabView, noProfileSelectedView, toggleTagsButton,
         addButton, removeButton, actionsPopup].forEach(store)
        if let copyToProfileButton { store(copyToProfileButton) }
        refresh()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        needsLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.refreshScheduled else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }
    private func sourceIndex(_ item: NSTabViewItem) -> Int {
        let identifiers = ["1", "2", "Text", "Window", "Item 2", "Item 6", "Item 3", "Item 7"]
        return identifiers.firstIndex(of: item.identifier as? String ?? "") ?? 0
    }
    private func refresh() {
        guard let tabs else { return }
        let pages = tabs.tabViewItems.compactMap { item -> (Int, ProfileFormDocumentView)? in
            guard let page = item.view, let form = page.it_childProfileFormDocument() else { return nil }
            // Detached tab pages still need a window for their native sheets and popovers.
            store(page)
            form.onInvalidation = { [weak self] in self?.scheduleRefresh() }
            return (sourceIndex(item), form)
        }
        state.profiles = (model?.bookmarks() ?? []).compactMap { profile in
            guard let guid = profile[KEY_GUID] as? String else { return nil }
            return WorkspaceProfile(id: guid, name: profile[KEY_NAME] as? String ?? "")
        }
        state.selectedProfile = profileList?.selectedGuid ?? ""
        state.editingSession = editingSession
        state.isDefault = profileList?.selectedGuid == (model?.defaultProfile()?[KEY_GUID] as? String)
        state.moreActions = actions?.menu?.items.filter { item in
            guard let action = item.action else { return false }
            return !["setAsDefault:", "duplicateProfile:"].contains(NSStringFromSelector(action))
        } ?? []
        state.refresh(pages: pages)
        needsLayout = true
    }

    @objc var workspaceTaskCount: Int { ProfileTask.allCases.count }
    @objc var selectedProfileIdentifier: String { state.selectedProfile }
    @objc var selectedWorkspaceTask: String { state.task.rawValue }
    @objc func selectWorkspaceTask(_ identifier: String) {
        guard let task = ProfileTask(rawValue: identifier) else { return }
        state.task = task
        host.layoutSubtreeIfNeeded()
    }

    @objc func reloadProfilesSidebar() { scheduleRefresh() }
    @objc func setSelectedProfileTitle(_ title: String?) { scheduleRefresh() }
    @objc func syncCategories() { refresh() }
    @objc func invalidateUnifiedSectionsLayout() { scheduleRefresh() }
    @objc func syncSelectedCategory() {
        guard let item = tabs?.selectedTabViewItem else { return }
        if let record = state.sections.first(where: { $0.source == sourceIndex(item) }) { state.task = record.task }
    }
    @objc func selectCategory(at index: Int) {
        guard let tabs, tabs.tabViewItems.indices.contains(index) else { return }
        tabs.selectTabViewItem(at: index)
        syncSelectedCategory()
    }
    @objc func revealWorkspaceEditor(_ control: NSView) -> Bool {
        refresh()
        let result = state.reveal(control)
        host.layoutSubtreeIfNeeded()
        return result
    }
    override func layout() {
        super.layout()
        if refreshScheduled { refreshScheduled = false; refresh() }
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
    }
}
