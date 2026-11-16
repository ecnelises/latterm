//
//  SessionModeHandler.swift
//  iTerm2SharedARC
//
//  Migrated from iTermCopyModeHandler.{h,m}.
//

import Cocoa

/// Delegate supporting keyboard-driven shortcut navigation overlays.
@objc(iTermShortcutNavigationModeHandlerDelegate)
protocol iTermShortcutNavigationModeHandlerDelegate: NSObjectProtocol {
    @objc(shortcutNavigationActionForKeyEquivalent:)
    func shortcutNavigationAction(forKeyEquivalent characters: String) -> ((NSEvent) -> Void)?

    @objc func shortcutNavigationDidComplete()
    @objc func shortcutNavigationDidBegin()

    @objc(shortcutNavigationCharactersAreCommandPrefix:)
    func shortcutNavigationCharactersAreCommandPrefix(_ characters: String) -> Bool

    @objc(shortcutNavigationDidSetPrefix:)
    func shortcutNavigationDidSetPrefix(_ prefix: String?)
}

/// Active interaction mode for a terminal session.
@objc(iTermSessionMode)
enum iTermSessionMode: UInt {
    case `default` = 0
    case copy = 1
    case shortcutNavigation = 2
}

/// Matches multi-keystroke shortcut navigation sequences against registered actions.
@objc(iTermShortcutNavigationModeHandler)
final class iTermShortcutNavigationModeHandler: NSObject {
    @objc weak var delegate: iTermShortcutNavigationModeHandlerDelegate?
    private var prefix: String?

    fileprivate enum HandleResult {
        case unhandled
        case handled
        case partial
    }

    private enum KeyEquivalentMatch {
        case unmatched
        case prefixOnly
        case matched(String)
    }

    private func updatePrefix(_ newPrefix: String?) {
        delegate?.shortcutNavigationDidSetPrefix(newPrefix)
        prefix = newPrefix
    }

    private func matchKeyEquivalent(for event: NSEvent) -> KeyEquivalentMatch {
        let disallowed: NSEvent.ModifierFlags = [.command, .control]
        if !event.modifierFlags.intersection(disallowed).isEmpty {
            return .unmatched
        }
        guard let characters = event.characters, let first = characters.utf16.first else {
            return .unmatched
        }
        if first == 27 {
            return .matched(characters)
        }
        let unmod = event.charactersIgnoringModifiers ?? ""
        let candidate = (prefix ?? "") + unmod
        if delegate?.shortcutNavigationAction(forKeyEquivalent: candidate) != nil {
            updatePrefix(candidate)
            return .matched(candidate)
        }
        if delegate?.shortcutNavigationAction(forKeyEquivalent: unmod) != nil {
            updatePrefix(nil)
            return .matched(unmod)
        }
        if delegate?.shortcutNavigationCharactersAreCommandPrefix(candidate) == true {
            updatePrefix(candidate)
            return .prefixOnly
        }
        return .unmatched
    }

    fileprivate func canMatchKeyEquivalent(for event: NSEvent) -> Bool {
        switch matchKeyEquivalent(for: event) {
        case .unmatched:
            return false
        case .prefixOnly, .matched:
            return true
        }
    }

    fileprivate func handleEvent(_ event: NSEvent) -> HandleResult {
        switch matchKeyEquivalent(for: event) {
        case .unmatched:
            return .unhandled
        case .prefixOnly:
            return .partial
        case .matched(let keyEquivalent):
            updatePrefix(nil)
            if event.characters?.utf16.first == 27 {
                return .handled
            }
            guard let action = delegate?.shortcutNavigationAction(forKeyEquivalent: keyEquivalent) else {
                return .unhandled
            }
            action(event)
            return .handled
        }
    }
}

/// Coordinates switching and event routing across default, Copy, and Shortcut Navigation modes.
@objc(iTermSessionModeHandler)
final class iTermSessionModeHandler: NSObject {
    @objc weak var delegate: (iTermCopyModeHandlerDelegate & iTermShortcutNavigationModeHandlerDelegate)? {
        didSet {
            copyModeHandler.delegate = delegate
            shortcutNavigationModeHandler.delegate = delegate
        }
    }

    private var _mode: iTermSessionMode = .default

    @objc var mode: iTermSessionMode {
        get { _mode }
        set {
            if newValue == _mode {
                return
            }
            let original = _mode
            _mode = newValue
            if newValue == .copy {
                copyModeHandler.enabled = true
            } else if original == .copy {
                copyModeHandler.enabled = false
            }
            if newValue == .shortcutNavigation {
                delegate?.shortcutNavigationDidBegin()
            } else if original == .shortcutNavigation {
                delegate?.shortcutNavigationDidComplete()
            }
        }
    }

    @objc let copyModeHandler = iTermCopyModeHandler()
    @objc let shortcutNavigationModeHandler = iTermShortcutNavigationModeHandler()
    @objc var clearSelectionsOnExit = false

    @objc(wouldHandleEvent:)
    func wouldHandleEvent(_ event: NSEvent) -> Bool {
        switch _mode {
        case .default:
            return false
        case .shortcutNavigation:
            return shortcutNavigationModeHandler.canMatchKeyEquivalent(for: event)
        case .copy:
            return copyModeHandler.wouldHandleEvent(event)
        }
    }

    @objc func enterCopyModeWithoutCleverness() {
        _mode = .copy
        copyModeHandler.setEnabledWithoutCleverness(true)
    }

    @discardableResult
    @objc(handleEvent:)
    func handle(_ event: NSEvent) -> Bool {
        switch _mode {
        case .default:
            return false
        case .shortcutNavigation:
            switch shortcutNavigationModeHandler.handleEvent(event) {
            case .unhandled:
                return false
            case .partial:
                return true
            case .handled:
                mode = .default
                return true
            }
        case .copy:
            let handled = copyModeHandler.handleEvent(event)
            if !copyModeHandler.enabled {
                mode = .default
            }
            return handled
        }
    }

    @objc(shouldAutoEnterWithEvent:)
    func shouldAutoEnter(with event: NSEvent) -> Bool {
        switch _mode {
        case .default:
            return copyModeHandler.shouldAutoEnter(with: event)
        case .shortcutNavigation, .copy:
            return false
        }
    }

    @objc func previousMark() -> Bool {
        switch _mode {
        case .default, .shortcutNavigation:
            return false
        case .copy:
            return copyModeHandler.state?.previousMark() ?? false
        }
    }

    @objc func nextMark() -> Bool {
        switch _mode {
        case .default, .shortcutNavigation:
            return false
        case .copy:
            return copyModeHandler.state?.nextMark() ?? false
        }
    }
}
