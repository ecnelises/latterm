//
//  GlobalSearchOutlineView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

import Cocoa

/// Outline view for global search results that activates on the first mouse click.
@objc(iTermGlobalSearchOutlineView)
class GlobalSearchOutlineView: NSOutlineView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
