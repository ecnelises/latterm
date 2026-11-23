// Window restoration from AppKit archives and Latterm's state database.
import AppKit

@objc(PseudoTerminalState)
final class PseudoTerminalState: NSObject {
    @objc let arrangement: [AnyHashable: Any]?
    @objc let coder: NSCoder?
    @objc private(set) weak var largeContentProvider: iTermLargeContentProvider?

    @objc(initWithCoder:)
    init(coder: NSCoder) {
        arrangement = coder.decodeObject(forKey: kTerminalWindowStateRestorationWindowArrangementKey) as? [AnyHashable: Any]
        self.coder = coder
    }

    @objc(initWithDictionary:)
    convenience init(dictionary: [AnyHashable: Any]) {
        self.init(dictionary: dictionary, largeContentProvider: nil)
    }

    @objc(initWithDictionary:largeContentProvider:)
    init(dictionary: [AnyHashable: Any], largeContentProvider: iTermLargeContentProvider?) {
        arrangement = dictionary
        coder = nil
        self.largeContentProvider = largeContentProvider
    }
}

/// The startup queue pauses while AppKit animates a full-screen window. After both the
/// database and the window queue finish, deliver post-restoration callbacks in registration order.
@MainActor
final class WindowRestorationQueue {
    private var windows: [() -> Void] = []
    private var postRestoration: [() -> Void] = []
    private var drained = false
    private var databaseFinished = false
    private var draining = false
    private var deliveringCompletions = false
    private var waitingForFullscreen = false

    var hasQueuedWindows: Bool { !windows.isEmpty }
    private var ready: Bool { drained && databaseFinished }

    func enqueue(_ block: @escaping () -> Void) {
        drained = false
        windows.append(block)
    }

    func afterWindows(_ block: @escaping () -> Void) {
        if hasQueuedWindows || draining || waitingForFullscreen { enqueue(block) } else { block() }
    }

    func drain() {
        guard !draining, !waitingForFullscreen else { return }
        draining = true
        while !windows.isEmpty && !waitingForFullscreen {
            let next = windows.removeFirst()
            next()
        }
        draining = false
        drained = windows.isEmpty && !waitingForFullscreen
        deliverCompletions()
    }

    func pauseForFullscreen() { waitingForFullscreen = true }

    func fullscreenFinished() {
        waitingForFullscreen = false
        drain()
    }

    func externalRestorationFinished() {
        databaseFinished = true
        deliverCompletions()
    }

    func afterRestoration(_ completion: @escaping () -> Void) {
        postRestoration.append(completion)
        deliverCompletions()
    }

    private func deliverCompletions() {
        guard !deliveringCompletions else { return }
        deliveringCompletions = true
        while ready && !postRestoration.isEmpty {
            let next = postRestoration.removeFirst()
            next()
        }
        deliveringCompletions = false
    }
}

@MainActor
@objc(PseudoTerminalRestorer)
final class PseudoTerminalRestorer: NSObject, NSWindowRestoration {
    private static let queue = WindowRestorationQueue()
    // The controller is registered with iTermController after the fullscreen transition completes.
    private static var enteringFullscreen: PseudoTerminal?

    @objc static func willOpenWindows() -> Bool { queue.hasQueuedWindows }
    @objc static func runQueuedBlocks() { queue.drain() }
    @objc static func externalRestorationDidComplete() { queue.externalRestorationFinished() }

    @objc(setRestorationCompletionBlock:)
    static func afterWindows(_ completion: @escaping () -> Void) { queue.afterWindows(completion) }

    @objc(setPostRestorationCompletionBlock:)
    static func afterRestoration(_ completion: @escaping () -> Void) { queue.afterRestoration(completion) }

    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
                              completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        guard !iTermApplicationDelegate.isCompareRenderingMode() else {
            completionHandler(nil, nil)
            return
        }
        restore(identifier.rawValue, state: PseudoTerminalState(coder: state), system: true, completion: completionHandler)
    }

    @objc(restoreWindowWithIdentifier:pseudoTerminalState:system:completionHandler:)
    static func restore(_ identifier: String, state: PseudoTerminalState, system: Bool,
                        completion: @escaping (NSWindow?, Error?) -> Void) {
        if system && iTermUserDefaults.ignoreSystemWindowRestoration {
            if let guid = state.coder?.decodeObject(forKey: iTermWindowStateKeyGUID) as? String {
                iTermRestorableStateController.sharedInstance().setSystemRestorationCallback(completion, windowIdentifier: guid)
            } else {
                let previous = iTermRestorableStateController.shouldIgnoreOpenUntitledFile
                iTermRestorableStateController.shouldIgnoreOpenUntitledFile = true
                completion(nil, nil)
                iTermRestorableStateController.shouldIgnoreOpenUntitledFile = previous
            }
            return
        }
        guard !NSApp.isRunningUnitTests() else {
            completion(nil, nil)
            return
        }
        if iTermAdvancedSettingsModel.startDebugLoggingAutomatically() { TurnOnDebugLoggingAutomatically() }
        (NSApp.delegate as? iTermApplicationDelegate)?.willRestoreWindow()
        if iTermPreferences.bool(forKey: kPreferenceKeyOpenArrangementAtStartup) {
            if let arrangement = state.arrangement { PseudoTerminal.registerSessions(inArrangement: arrangement) }
            completion(nil, nil)
            return
        }
        guard !iTermPreferences.bool(forKey: kPreferenceKeyOpenNoWindowsAtStartup), let arrangement = state.arrangement else {
            completion(nil, nil)
            return
        }
        queue.enqueue {
            DLog("Restoring window \(identifier)")
            guard let terminal = PseudoTerminal.bareTerminal(arrangement: arrangement,
                                                             forceOpeningHotKeyWindow: false, restoring: true) else {
                RLog("Failed to create terminal for \(identifier)")
                completion(nil, nil)
                return
            }
            switch terminal.windowType() {
            case .WINDOW_TYPE_TRADITIONAL_FULL_SCREEN, .WINDOW_TYPE_TOP_PERCENTAGE, .WINDOW_TYPE_TOP_CELLS,
                 .WINDOW_TYPE_CENTERED, .WINDOW_TYPE_BOTTOM_PERCENTAGE, .WINDOW_TYPE_BOTTOM_CELLS,
                 .WINDOW_TYPE_MAXIMIZED, .WINDOW_TYPE_COMPACT_MAXIMIZED:
                terminal.perform(#selector(PseudoTerminal.canonicalizeWindowFrame), with: nil, afterDelay: 0)
            default: break
            }
            @MainActor func register(_ terminal: PseudoTerminal) {
                terminal.restoringWindow = true
                completion(terminal.window, nil)
                terminal.restoringWindow = false
                iTermController.sharedInstance().addTerminalWindow(terminal)
            }
            if terminal.togglingLionFullScreen() {
                enteringFullscreen = terminal
                queue.pauseForFullscreen()
                terminal.didEnterLionFullscreen = { restored in
                    guard let restored, enteringFullscreen === restored else { return }
                    enteringFullscreen = nil
                    register(restored)
                    queue.fullscreenFinished()
                }
            } else {
                register(terminal)
            }
        }
    }
}
