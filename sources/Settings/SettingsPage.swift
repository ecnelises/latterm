import AppKit

enum SettingsGroup: CaseIterable {
    case application, terminal, input, advanced

    var title: String {
        switch self {
        case .application: return NSLocalizedString("App & Workspace", comment: "Settings navigation group")
        case .terminal: return NSLocalizedString("Your Terminals", comment: "Settings navigation group")
        case .input: return NSLocalizedString("Input & Automation", comment: "Settings navigation group")
        case .advanced: return NSLocalizedString("Advanced", comment: "Settings navigation group")
        }
    }
}

@objc(iTermSettingsCategory)
enum SettingsCategory: Int {
    case general
    case appearance
    case profiles
    case keys
    case arrangements
    case pointer
    case shortcuts
    case advanced
}

/// One navigation entry owns the metadata and tab mapping used by the sidebar,
/// page heading, search paths, and controller routing. Controllers remain owned
/// by PreferencePanel so this model cannot create a controller ownership cycle.
@objc(iTermSettingsPage)
final class SettingsPage: NSObject {
    @objc let identifier: String
    @objc let title: String
    @objc let subtitle: String
    @objc let image: NSImage?
    @objc let tabViewItem: NSTabViewItem
    @objc weak var controller: NSViewController?
    let group: SettingsGroup
    @objc let scope: String

    @objc init(category: SettingsCategory, tabViewItem: NSTabViewItem, controller: NSViewController) {
        switch category {
        case .general, .appearance, .arrangements: group = .application
        case .profiles: group = .terminal
        case .keys, .pointer, .shortcuts: group = .input
        case .advanced: group = .advanced
        }
        scope = category == .profiles ?
            NSLocalizedString("Selected profile", comment: "Settings scope") :
            NSLocalizedString("Application-wide", comment: "Settings scope")
        let metadata: (identifier: String, title: String, subtitle: String, symbol: SFSymbol)
        switch category {
        case .general:
            metadata = ("general", NSLocalizedString("App Behavior", comment: "Settings category"),
                        NSLocalizedString("Startup, windows, and everyday behavior", comment: "Settings category description"), .gearshape)
        case .appearance:
            metadata = ("appearance", NSLocalizedString("Appearance", comment: "Settings category"),
                        NSLocalizedString("Tabs, panes, and window appearance", comment: "Settings category description"), .eye)
        case .profiles:
            metadata = ("profiles", NSLocalizedString("Profiles", comment: "Settings category"),
                        NSLocalizedString("Appearance, shell, and behavior for each terminal profile", comment: "Settings category description"), .person)
        case .keys:
            metadata = ("keys", NSLocalizedString("Keyboard", comment: "Settings category"),
                        NSLocalizedString("Key bindings and keyboard behavior", comment: "Settings category description"), .keyboard)
        case .arrangements:
            metadata = ("arrangements", NSLocalizedString("Workspaces", comment: "Settings category"),
                        NSLocalizedString("Save and restore your workspace", comment: "Settings category description"), .macwindowOnRectangle)
        case .pointer:
            metadata = ("pointer", NSLocalizedString("Mouse & Trackpad", comment: "Settings category"),
                        NSLocalizedString("Mouse, trackpad, and selection gestures", comment: "Settings category description"), .cursorarrowMotionlines)
        case .shortcuts:
            metadata = ("shortcuts", NSLocalizedString("Actions & Snippets", comment: "Settings category"),
                        NSLocalizedString("Reusable actions and text snippets", comment: "Settings category description"), .boltCircle)
        case .advanced:
            metadata = ("advanced", NSLocalizedString("Expert Settings", comment: "Settings category"),
                        NSLocalizedString("Terminal compatibility, performance, and diagnostics", comment: "Settings category description"), .gearshape2)
        }
        identifier = metadata.identifier
        title = metadata.title
        subtitle = metadata.subtitle
        image = NSImage(systemSymbolName: metadata.symbol.rawValue, accessibilityDescription: nil)
        self.tabViewItem = tabViewItem
        self.controller = controller
        super.init()
    }
}
