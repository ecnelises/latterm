//
//  iTermUntitledWindowStateMachine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/20.
//

import Foundation

@objc(iTermUntitledWindowStateMachineDelegate)
protocol iTermUntitledWindowStateMachineDelegate: NSObjectProtocol {
    func untitledWindowStateMachineCreateNewWindow(_ sender: iTermUntitledWindowStateMachine)
}

// Coordinates untitled-window requests with initialization and restoration.
// Application-specific window creation policy belongs to the delegate.
@objc(iTermUntitledWindowStateMachine)
final class iTermUntitledWindowStateMachine: NSObject {
    @objc weak var delegate: iTermUntitledWindowStateMachineDelegate?

    private var windowRestorationComplete = false
    private var disableInitialWindow = false
    private var initializationComplete = false
    private var wantsWindow = false

    override var description: String {
        "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) " +
        "windowRestorationComplete=\(windowRestorationComplete) " +
        "disableInitialWindow=\(disableInitialWindow) " +
        "initializationComplete=\(initializationComplete) wantsWindow=\(wantsWindow)>"
    }

    @objc func maybeOpenUntitledFile() {
        DLog("untitled: maybeOpenUntitledFile \(self)\n\(Thread.callStackSymbols)")
        if disableInitialWindow && !initializationComplete {
            DLog("untitled: do nothing because this is the initial window.")
            return
        }
        if disableInitialWindow && !windowRestorationComplete {
            RLog("untitled: do nothing because window restoration is still in progress")
            return
        }
        wantsWindow = true
        openWindowIfWanted()
    }

    @objc func didRestoreSomeWindows() {
        DLog("untitled: didRestoreSomeWindows \(self)")
        disableInitialUntitledWindow()
    }

    @objc func disableInitialUntitledWindow() {
        DLog("untitled: disableInitialUntitledWindow \(self)")
        disableInitialWindow = true
        wantsWindow = false
    }

    @objc func didFinishRestoringWindows() {
        RLog("untitled: windowRestorationDidComplete \(self)")
        windowRestorationComplete = true
        openWindowIfWanted()
    }

    @objc func didFinishInitialization() {
        RLog("untitled: didFinishInitialization \(self)")
        initializationComplete = true
        openWindowIfWanted()
    }

    private func openWindowIfWanted() {
        DLog("untitled: openWindowIfWanted \(self)")
        guard windowRestorationComplete && initializationComplete else {
            DLog("untitled: not ready yet \(self)")
            return
        }
        guard wantsWindow else {
            DLog("untitled: doesn’t want window \(self)")
            return
        }
        // Keep the request latched, matching the existing launch callback behavior.
        delegate?.untitledWindowStateMachineCreateNewWindow(self)
    }
}
