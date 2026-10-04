import AppKit

/// A persistent profile library beside the editor keeps selection, search,
/// and management actions in one place while the detail document scrolls.
@objc(iTermSettingsProfilesView)
final class SettingsProfilesView: NSView {
    private weak var profileList: NSView?
    private weak var details: NSView?
    private var actions: [(view: NSView, frame: NSRect)] = []
    private let title = NSTextField(labelWithString: "")
    private let explanation = NSTextField(labelWithString: NSLocalizedString("A profile saves the appearance, shell, and behavior of your terminals.", comment: "Profile explanation"))
    @objc var editingSession = false { didSet { needsLayout = true } }

    @objc func configure(profileList: NSView, details: NSView, actions: [NSView]) {
        self.profileList = profileList
        self.details = details
        self.actions = actions.map { view in
            var frame = view.frame
            if let menu = view as? NSPopUpButton {
                menu.toolTip = menu.title
                menu.setAccessibilityLabel(menu.title)
                menu.imagePosition = .imageOnly
                frame.size.width = 44
            }
            return (view, frame)
        }
        autoresizesSubviews = false
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityIdentifier("SettingsSelectedProfile")
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        explanation.lineBreakMode = .byTruncatingTail
        explanation.toolTip = explanation.stringValue
        [title, explanation].forEach { addSubview($0) }
        needsLayout = true
    }

    @objc func updateProfiles(names: [String], identifiers: [String], selectedIdentifier: String?) {
        it_assert(names.count == identifiers.count, "Profile names and identities must match")
        let selected = identifiers.firstIndex { $0 == selectedIdentifier }
        title.stringValue = selected.map { names[$0] } ?? ""
        title.toolTip = title.stringValue
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let profileList, let details else { return }
        [title, explanation].forEach { $0.isHidden = editingSession }
        profileList.isHidden = editingSession
        for action in actions { action.view.isHidden = editingSession }
        if editingSession { return }

        let listWidth: CGFloat = 184
        let detailX: CGFloat = 224
        profileList.frame = NSRect(x: 32, y: 52, width: listWidth, height: max(0, bounds.height - 68))
        // Keep the existing tag, add, remove, and actions controls together.
        let origin = actions.map { $0.frame.minX }.min() ?? 0
        for action in actions {
            let x = 32 + action.frame.minX - origin
            action.view.frame = NSRect(x: x, y: 16,
                                       width: min(action.frame.width, 32 + listWidth - x),
                                       height: action.frame.height)
        }
        title.frame = NSRect(x: detailX + 32, y: bounds.height - 36,
                             width: max(0, bounds.width - detailX - 64), height: 22)
        explanation.frame = NSRect(x: detailX + 32, y: bounds.height - 60,
                                   width: max(0, bounds.width - detailX - 64), height: 18)
        details.frame = NSRect(x: detailX, y: 8, width: max(0, bounds.width - detailX - 8),
                               height: max(0, bounds.height - 82))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !editingSession else { return }
        NSColor.separatorColor.setFill()
        NSRect(x: 223, y: 16, width: 1, height: max(0, bounds.height - 32)).fill()
    }
}
