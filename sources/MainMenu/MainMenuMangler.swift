//
//  MainMenuMangler.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Cocoa

@objc(iTermMainMenuMangler)
class MainMenuMangler: NSObject {
    @objc static let instance = MainMenuMangler()
    private let defaultsObserver = iTermUserDefaultsObserver()

    @objc static var menuActionImagesEnabled: Bool {
        iTermPreferences.bool(forKey: kPreferenceKeyMenuActionImages)
    }

    private let iconMap = [
        // iTerm2 menu
        "Show Tip of the Day": "lightbulb",
        "Check For Updates…": "arrow.triangle.2.circlepath",
        "Toggle Debug Logging": "ladybug",
        "Copy Performance Stats": "hare",
        "Capture Metal Frame": "camera",
        "Preferences...": "gear",
        // "Services" menu item has no identifier in XIB
        "Hide iTerm2": "eye.slash",
        "Hide Others": "eye.slash.fill",
        "Show All": "eye",
        "Secure Keyboard Entry": "lock.badge.checkmark",
        "Make iTerm2 Default Term": "star.fill",
        "Make Terminal Default Term": "star",
        "Remove Recent Profiles from Dock Menu": "person.fill.xmark",
        "About iTerm2": "info.circle.fill",
        "Quit iTerm2": "power",

        // Shell menu
        "New Window": "plus",
        "New Window with Current Profile": "plus.app",
        "New Tab": "plus.rectangle.on.folder",
        "New Tab Next to Current Tab": "arrow.forward.folder.fill",
        "New Tab with Current Profile": "plus.rectangle.on.folder.fill",
        "Duplicate Tab": "document.on.document",
        "Duplicate Window": "document.on.document.fill",
        "Duplicate Session": "rectangle.on.rectangle",
        "Press Option for New Window": "option",
        "Split Horizontally with Current Profile": "square.split.1x2.fill",
        "Split Vertically with Current Profile": "square.split.2x1.fill",
        "Split Horizontally…": "square.split.1x2",
        "Split Vertically…": "square.split.2x1",
        "Log.SaveContents": "square.and.arrow.down",
        "Log.Toggle": "record.circle",
        // Log.Start and Log.Stop removed - no identifiers in XIB
        "Log.ImportRecording": "square.and.arrow.down",
        "Log.ExportRecording": "square.and.arrow.up",
        // Log.ExportCommandHistory removed - no identifier in XIB
        "Close": "xmark",
        "Close Terminal Window": "xmark.circle.fill",
        "Close All Panes in Tab": "xmark.circle",
        "Exit Workgroup": "arrow.right.square",
        "Undo Close": "arrow.uturn.backward",
        "Broadcast Input.Send Input to Current Session Only": "person",
        "Broadcast Input.Broadcast Input to All Panes in All Tabs": "dot.radiowaves.right",
        "Broadcast Input.Broadcast Input to All Panes in Current Tab": "dot.radiowaves.right",
        "Broadcast Input.Toggle Broadcast Input to Current Session": "dot.radiowaves.right",
        "Broadcast Input.Show Background Pattern Indicator": "dot.radiowaves.up.forward",
        "Broadcast Input.Current Session is Broadcast Source": "dot.radiowaves.left.and.right",
        "Toggle Buffer Input": "pause.circle",
        "tmux.Dashboard": "rectangle.grid.2x2",
        "tmux.Detach": "arrow.up.right.square",
        "tmux.Force Detach": "bolt.slash",
        "tmux.New Tmux Window": "plus.rectangle.on.rectangle",
        "tmux.New Tmux Tab": "plus.square.on.square",
        "trmux.Pause Pane": "pause.circle",
        // tmux.Pause Pane removed - no identifier in XIB
        // ssh menu items have individual identifiers, not a general one
        "ssh.Download Files": "arrow.down.doc",
        "ssh.Disconnect": "network.badge.xmark",
        // Print submenu items removed - no identifiers in XIB
        "Print.Selection": "printer",
        "Print.Buffer": "printer",
        "Print.Screen": "printer",
        "Page Setup...": "doc.text",

        // Edit menu
        "Undo": "arrow.uturn.backward",
        "Redo": "arrow.uturn.forward",
        "Cut": "scissors",
        "Copy": "document.on.document",
        "Copy with Styles": "document.on.document.fill",
        "Copy with Control Sequences": "document.on.document",
        "Copy Mode": "document.badge.plus",
        "Paste": "document.on.clipboard",
        "Paste Special.Advanced Paste…": "document.on.clipboard",
        "Paste Special.Paste Selection": "document.badge.plus",
        "Paste Special.Paste File Base64-Encoded": "document.badge.plus.fill",
        "Paste Special.Paste Faster": "hare",
        "Paste Special.Paste Slowly Faster": "hare.circle",
        "Paste Special.Paste Slower": "tortoise",
        "Paste Special.Paste Slowly Slower": "tortoise.circle",
        "Paste Special.Warn Before Multi-Line Paste": "exclamationmark.triangle",
        "Paste Special.Limit Multi-Line Paste Warning to Shell Prompt": "bolt.trianglebadge.exclamationmark.fill",
        "Paste Special.Prompt to Convert Tabs to Spaces when Pasting": "convertible.side",
        "Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt": "exclamationmark.triangle.text.page",
        "Paste Special.Paste Slowly": "tortoise.fill",
        "Open Selection": "arrow.up.right",
        "Find.Jump to Selection": "arrow.turn.up.right",
        "Find.Find...": "magnifyingglass",
        "Find.Find Next": "arrow.down",
        "Find.Find Previous": "arrow.up",
        "Find.Use Selection for Find": "lasso.badge.sparkles",
        // Find.Jump Again removed - no identifier in XIB
        "Find.Find Globally...": "globe",
        "Find.Find URLs": "network",
        "Find.Pick Result To Open": "hand.tap",
        "Find.Filter": "line.3.horizontal.decrease.circle",
        "Find.Find All Smart Selection  Matches": "sparkle.magnifyingglass",
        "Find.ConvertMatchesToSelections": "checkmark.rectangle.stack",
        "Find.Clear Find": "xmark.circle",
        "Select All": "a.circle",
        "Selection Respects Soft Boundaries": "text.justify.leading",
        "Select Current Command": "text.cursor",
        "Select Output of Last Command": "text.line.last.and.arrowtriangle.forward",
        "Save Selected Text…": "square.and.arrow.down.on.square",
        "Open Autocomplete…": "text.badge.xmark",
        "Marks and Annotations.Set Mark": "bookmark",
        "Marks and Annotations.Add Annotation at Cursor": "pencil",
        "Marks and Annotations.Annotate Selection": "square.and.pencil",
        "Marks and Annotations.Alerts.Alert on Next Mark": "bolt.badge.clock",
        "Marks and Annotations.Next Mark": "arrow.down",
        "Marks and Annotations.Previous Mark": "arrow.up",
        "Marks and Annotations.Next  Annotation": "arrow.down.circle",
        "Marks and Annotations.Previous  Annotation": "arrow.up.circle",
        "Marks and Annotations.Jump to Mark": "location",
        "Set Named Mark": "bookmark.fill",
        "Marks and Annotations.Alerts.Show Modal Alert Box": "exclamationmark.square",
        "Marks and Annotations.Alerts.Post Notification": "bell",
        "Marks and Notes.Alerts.Play a Sound": "speaker.wave.2",
        "Marks and Alerts.Alerts.Alert on Marks in Offscreen Sessions": "bell.badge",
        // Annotations navigation removed - no identifiers in XIB
        // Clear Transcript removed - no identifier in XIB
        "Clear Buffer": "xmark.rectangle",
        "Clear to Start of Selection": "arrow.up.left.and.arrow.down.right",
        "Clear to Last Mark": "bookmark",
        "Clear Scrollback Buffer": "xmark.diamond",
        "Fold Selected Lines": "text.line.first.and.arrowtriangle.forward",
        "Fold All Above Cursor": "text.line.first.and.arrowtriangle.forward",

        // View menu
        "Show Tabs in Fullscreen": "macwindow",
        "Toggle Full Screen": "arrow.up.left.and.arrow.down.right",
        "Use Transparency": "cube.transparent",
        "Zoom In on Selection": "rectangle.expand.diagonal",
        "Zoom Out": "arrow.down.left.and.arrow.up.right",
        "Find Cursor": "viewfinder",
        "Show Cursor Guide": "text.aligncenter",
        "Show Timestamps": "clock",
        "Show Annotations": "text.bubble",
        "Edit Session Note": "text.pad.header",
        "Open Quickly": "magnifyingglass",
        "Maximize Active Pane": "rectangle.compress.vertical",
        "Make Text Bigger": "textformat.size.larger",
        "Make Text Smaller": "textformat.size.smaller",
        "Make Text Normal Size": "textformat.size",
        "Start Instant Replay": "restart.circle",
        "Clear Instant Replay": "xmark.circle",
        "Always Show Alerts with Remembered Selections": "bell.badge",
        "Pin Hotkey Window": "pin.fill",
        "Render Selection Natively": "square.dashed",
        "Replace Selection.Replace with Pretty-Printed JSON": "curlybraces.square",
        "Replace Selection.Replace with Base 64-Encoded Value": "arrow.up.to.line.compact",
        "Replace Selection.Replace with Base 64-Decoded Value": "arrow.down.to.line.compact",
        "Disable Transparency for Active Window": "cube.fill",
        // Pin Broadcast Input removed - no identifier in XIB

        // Session menu
        "Edit Session…": "wrench.and.screwdriver",
        "Run Coprocess…": "figure.run.square.stack",
        "Stop Coprocess": "figure.run",
        "Restart Session": "arrow.clockwise",
        "Open Paste History…": "book.pages",
        // Open Trigger removed - no identifier in XIB
        "Reset": "restart",
        "Reset Character Set": "restart",
        // Log.Save Contents removed - no identifier in XIB
        // Log.Append to File removed - no identifier in XIB
        "Bury Session": "memories.badge.xmark",
        "Reset Terminal State": "arrow.clockwise",
        "Restore Text and Session Size": "arrow.counterclockwise",
        "Terminal State.Literal Mode": "textformat.abc",
        "Terminal State.Emulation Level.VT100": "display",
        "Terminal State.Emulation Level.VT200": "display",
        "Terminal State.Emulation Level.VT300": "display",
        "Terminal State.Emulation Level.VT400": "display",
        "Terminal State.Emulation Level.VT500": "display",
        "Terminal State.Raw Key Reporting": "keyboard.badge.ellipsis",
        "Terminal State.Standard Key Reporting": "keyboard",
        "Terminal State.Disambiguate Escape": "escape",
        "Terminal State.Report Modifiers like xterm 1": "keyboard.badge.1",
        "Terminal State.Report Modifiers like xterm 2": "keyboard.badge.2",
        "Terminal State.Report Modifiers with CSI u": "keyboard.badge.ellipsis",
        "Terminal State.Report All Event Types": "list.bullet.rectangle",
        "Terminal State.Report Alternate Keys": "keyboard.chevron.compact.left",
        "Terminal State.Report Associated Text": "text.badge.plus",
        "Terminal State.Report All Keys as Escape Codes": "keyboard.fill",
        "Application Keypad": "keyboard",
        "Application Cursor": "cursorarrow",
        "Mouse Reporting": "computermouse",
        "Focus Reporting": "target",
        "Paste Bracketing": "brackets",
        "Alternate Screen": "rectangle.badge.arrow.up.right",
        "Move Session to Window": "macwindow.badge.plus",
        "Move Session to Tab": "plus.rectangle.on.folder",
        "Move Session to Split Pane": "rectangle.split.2x1",
        "Lock Split Pane Width": "lock.rectangle",
        "Triggers.Enable All": "checkmark.circle",
        "Triggers.Disable All": "xmark.circle",
        "Edit Triggers": "pencil.circle",
        "Add Trigger": "plus.diamond",
        "Enable Triggers in Interactive Apps": "play.circle",
        "Auto Composer": "wand.and.stars",
        "Open Interactive Window": "terminal",
        "Make Screenshot": "camera",
        "Show Clippings": "square.stack",
        "Show Inline Chat": "bubble.left",

        // Scripts menu
        // Manage removed - no identifier in XIB
        "New Python Script": "plus",
        // Open Python REPL removed - no identifier in XIB
        "Import Script": "square.and.arrow.down",
        "Export Script": "square.and.arrow.up",
        "Script Console": "greaterthan.square",
        "Reveal in Finder": "folder.circle",
        "Install Python Runtime": "arrow.down.circle",
        "Install Already-Downloaded Python Runtime": "arrow.down.circle.fill",
        "Manage Dependencies": "gearshape.2",
        // Reveal Scripts in Finder removed - no identifier in XIB

        // Profiles menu
        "Open Profiles…": "person",
        // Press Option to Show Alternate Profiles removed - no identifier in XIB
        "Open In New Window": "macwindow",
        "Change Profile in Arrangement…": "person.crop.rectangle",

        // Toolbelt menu
        "Show Toolbelt": "wrench.and.screwdriver",
        "Set Default Width": "guidepoint.horizontal",

        // Window menu
        "Minimize": "arrow.down.left.and.arrow.up.right",
        "Zoom": "arrow.up.left.and.arrow.down.right",
        "Edit Tab Title": "pencil",
        "Edit Window Title": "pencil",
        // Window Style removed - no identifier in XIB
        "Move Tab to New Window": "arrow.forward.folder.fill",
        "Merge All Windows": "macwindow.stack",
        "Arrange Split Panes Evenly": "rectangle.split.2x1",
        "Arrange Windows Horizontally": "square.split.2x1",
        "Bring All To Front": "macwindow",
        "Move Tab Left": "arrow.left.square",
        "Move Tab Right": "arrow.right.square",
        "Size Changes Update Profile": "arrow.up.and.down.and.arrow.left.and.right",
        "Window Style.FullHeight Right of Screen": "rectangle.righthalf.inset.filled",
        "Window Style..FullHeight Left of Screen": "rectangle.lefthalf.inset.filled",
        "Window Style.Right of Screen": "rectangle.righthalf.inset.filled",
        "Window Style.Left of Screen": "rectangle.lefthalf.inset.filled",
        "Window Style.Top of Screen": "rectangle.tophalf.inset.filled",
        "Window Style.Bottom of Screen": "rectangle.bottomhalf.inset.filled",
        "Window Style.FullWidth Bottom of Screen": "rectangle.bottomhalf.filled",
        "Window Style.FullWidth Top of Screen": "rectangle.tophalf.filled",
        "Window Style.Normal": "rectangle",
        "Window Style.Maximized": "rectangle.fill",
        "Window Style.Full Screen": "arrow.up.left.and.arrow.down.right",
        "Window Style.No Title Bar": "rectangle.dashed",
        "Window Style.Centered": "inset.filled.center.rectangle",
        "Lock Size": "lock",
        "Lock Layout": "lock.rectangle.on.rectangle",
        "Notify on Status Change": "bell",
        "Save Window Arrangement": "square.and.arrow.down",
        "Save Current Window as Arrangement": "square.and.arrow.down",
        "Load Arrangement from File…": "doc.badge.arrow.up",
        "changeTabColorToMenuAction:": "paintpalette",
        // Arrangement as Tabs items removed - no identifiers in XIB
        // Name Window removed - no identifier in XIB
        "Select Split Pane.Select Pane Above": "arrow.up",
        "Select Split Pane.Select Pane Below": "arrow.down",
        "Select Split Pane.Select Pane Left": "arrow.left",
        "Select Split Pane.Select Pane Right": "arrow.right",
        "Select Split Pane.Next Pane": "arrow.right",
        "Select Split Pane.Previous Pane": "arrow.left",
        "Select Split Pane.Next Peer": "arrow.right",
        "Select Split Pane.Previous Peer": "arrow.left",
        "Resize Split Pane.Move Divider Up": "arrow.up",
        "Resize Split Pane.Move Divider Down": "arrow.down",
        "Resize Split Pane.Move Divider Left": "arrow.left",
        "Resize Split Pane.Move Divider Right": "arrow.right",
        "Select Next Tab": "arrow.right",
        "Select Previous Tab": "arrow.left",
        "Resize Window.Decrease Height": "arrow.down.and.line.horizontal.and.arrow.up",
        "Resize Window.Increase Height": "arrow.up.and.line.horizontal.and.arrow.down",
        "Resize Window.Decrease Width": "arrow.right.and.line.vertical.and.arrow.left",
        "Resize Window.Increase Width": "arrow.left.and.line.vertical.and.arrow.right",
        "Password Manager": "lock",
        // Notifications removed - no identifier in XIB
        "Composer": "music.note.list",
        "GPU Renderer Availability": "cpu",

        // Help menu
        "iTerm2 Help": "questionmark.circle",
        "Copy Mode Shortcuts": "questionmark.circle",
        "Open Source Licenses": "info.circle"]

    @available(macOS 26, *)
    @objc func setIcons() {
        defaultsObserver.observeKey(kPreferenceKeyMenuActionImages) { [weak self] in
            self?.updateIcons()
        }
        updateIcons()
    }

    @available(macOS 26, *)
    private func updateIcons() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if MainMenuMangler.menuActionImagesEnabled {
            setIcons(map: iconMap, in: mainMenu)
        } else {
            removeIcons(in: mainMenu)
        }
    }

    private func setIcons(map iconMap: [String: String], in menu: NSMenu) {
        for item in menu.items {
            if let identifier = item.identifier?.rawValue,
               let iconName = iconMap[identifier] {
                #if(DEBUG)
                if item.hasSubmenu {
                    it_fatalError("Submenus should not have icons: \(identifier)")
                }
                #endif
                item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            }
            if item.hasSubmenu, let submenu = item.submenu {
                setIcons(map: iconMap, in: submenu)
            }
        }
    }

    private func removeIcons(in menu: NSMenu) {
        for item in menu.items {
            if !item.isSeparatorItem {
                item.image = nil
            }
            if item.hasSubmenu, let submenu = item.submenu {
                removeIcons(in: submenu)
            }
        }
    }

}
