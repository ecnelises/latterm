import AppKit

/// Editing one profile is the primary task. The full searchable list and its
/// management actions are available on demand, without changing selection.
@objc(iTermSettingsProfilesView)
final class SettingsProfilesView: NSView {
    private weak var profileList: NSView?
    private weak var details: NSView?
    private var actions: [(view: NSView, frame: NSRect)] = []
    private let label = NSTextField(labelWithString: NSLocalizedString("Profile", comment: "Profile selector"))
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let manage = NSButton(title: NSLocalizedString("Manage Profiles", comment: "Profile management"), target: nil, action: nil)
    private let explanation = NSTextField(labelWithString: NSLocalizedString("A profile saves the appearance, shell, and behavior of your terminals.", comment: "Profile explanation"))
    @objc var onSelectProfile: ((String) -> Void)?
    @objc var managingProfiles = false { didSet { needsLayout = true } }
    @objc var editingSession = false { didSet { needsLayout = true } }

    @objc func configure(profileList: NSView, details: NSView, actions: [NSView]) {
        self.profileList = profileList
        self.details = details
        self.actions = actions.map { ($0, $0.frame) }
        autoresizesSubviews = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        picker.target = self
        picker.action = #selector(selectProfile(_:))
        picker.setAccessibilityLabel(label.stringValue)
        picker.setAccessibilityIdentifier("SettingsProfilePicker")
        manage.bezelStyle = .rounded
        manage.target = self
        manage.action = #selector(toggleManagement(_:))
        manage.setButtonType(.pushOnPushOff)
        manage.setAccessibilityIdentifier("SettingsManageProfiles")
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        explanation.lineBreakMode = .byTruncatingTail
        explanation.toolTip = explanation.stringValue
        [label, picker, manage, explanation].forEach { addSubview($0) }
        needsLayout = true
    }

    @objc func updateProfiles(names: [String], identifiers: [String], selectedIdentifier: String?) {
        it_assert(names.count == identifiers.count, "Profile names and identities must match")
        picker.removeAllItems()
        // Add NSMenuItems directly so equal names remain independently selectable.
        for (name, identifier) in zip(names, identifiers) {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = identifier
            picker.menu?.addItem(item)
        }
        picker.select(picker.itemArray.first { $0.representedObject as? String == selectedIdentifier })
        picker.isEnabled = !names.isEmpty
    }

    @objc private func selectProfile(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String else { return }
        onSelectProfile?(identifier)
    }

    @objc private func toggleManagement(_ sender: NSButton) {
        managingProfiles.toggle()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let profileList, let details else { return }
        [label, picker, manage, explanation].forEach { $0.isHidden = editingSession }
        profileList.isHidden = editingSession || !managingProfiles
        for action in actions { action.view.isHidden = editingSession || !managingProfiles }
        if editingSession { return }

        let labelWidth = ceil(label.intrinsicContentSize.width)
        let manageWidth = max(120, ceil(manage.intrinsicContentSize.width))
        label.frame = NSRect(x: 28, y: bounds.height - 35, width: labelWidth, height: 18)
        manage.frame = NSRect(x: bounds.width - 28 - manageWidth, y: bounds.height - 41, width: manageWidth, height: 30)
        manage.state = managingProfiles ? .on : .off
        let pickerX = label.frame.maxX + 12
        picker.frame = NSRect(x: pickerX, y: bounds.height - 40,
                              width: max(0, min(360, manage.frame.minX - pickerX - 20)), height: 28)
        explanation.frame = NSRect(x: 28, y: bounds.height - 65, width: max(0, bounds.width - 56), height: 18)

        let inset: CGFloat = 16
        let bodyTop = bounds.height - 82
        let compact = bounds.width < 960
        var detailX = inset
        var detailTop = bodyTop
        if managingProfiles {
            let listWidth = compact ? max(0, bounds.width - 56) : 224
            let listHeight = compact ? 100 : max(0, bodyTop - 76)
            profileList.frame = NSRect(x: 28, y: bodyTop - 12 - listHeight, width: listWidth, height: listHeight)
            let actionsY = compact ? profileList.frame.minY - 34 : 20
            for action in actions {
                action.view.frame = NSRect(x: action.frame.minX + 12, y: actionsY,
                                           width: action.frame.width, height: action.frame.height)
            }
            detailX = compact ? inset : 268
            detailTop = compact ? actionsY - 12 : bodyTop
        }
        details.frame = NSRect(x: detailX, y: 8, width: max(0, bounds.width - detailX - inset),
                               height: max(0, detailTop - 8))
    }
}
