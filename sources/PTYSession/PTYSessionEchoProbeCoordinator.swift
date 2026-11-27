//
//  PTYSessionEchoProbeCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 4) to isolate password echo-probe
//  delegate callbacks and user confirmation handling.
//

import Cocoa

enum PTYSessionEchoProbePolicy {
    static func passwordSentMessage(sendReturnAfterPassword: Bool) -> String {
        if sendReturnAfterPassword {
            return "Password sent."
        }
        return "Password sent (press Return)."
    }

    static func shouldSuppressWrite(tmuxMode: PTYSessionTmuxMode) -> Bool {
        return tmuxMode == TMUX_GATEWAY
    }
}

@objc protocol PTYSessionEchoProbeHost: AnyObject {
    var tmuxMode: PTYSessionTmuxMode { get }
    var echoProbeWindow: NSWindow? { get }
    func echoProbeNoteUserInput()
    func echoProbeWriteString(_ string: String)
    func echoProbeWriteLatin1Data(_ data: Data)
    func echoProbeShowUnobtrusiveMessage(_ message: String, duration: TimeInterval)
    func echoProbeIncrementDisableFocusReporting(_ delta: Int)
    func echoProbeSendPassword()
    func echoProbeReset()
}

@objc final class PTYSessionEchoProbeCoordinator: NSObject, iTermEchoProbeDelegate {
    private weak var host: PTYSessionEchoProbeHost?
    private let shouldSendReturnAfterPassword: () -> Bool
    private let confirmEchoedPassword: (NSWindow?) -> Bool

    @objc(initWithSession:)
    convenience init(session: PTYSession) {
        self.init(
            host: session,
            shouldSendReturnAfterPassword: { iTermUserDefaults.shouldSendReturnAfterPassword },
            confirmEchoedPassword: { window in
                let selection = iTermWarning.show(
                    withTitle: "Are you really at a password prompt? It looks like what you’re typing is echoed to the screen.",
                    actions: ["Cancel", "Enter Password"],
                    identifier: nil,
                    silenceable: .kiTermWarningTypePersistent,
                    window: window
                )
                return selection == .kiTermWarningSelection1
            }
        )
    }

    init(host: PTYSessionEchoProbeHost,
         shouldSendReturnAfterPassword: @escaping () -> Bool,
         confirmEchoedPassword: @escaping (NSWindow?) -> Bool) {
        self.host = host
        self.shouldSendReturnAfterPassword = shouldSendReturnAfterPassword
        self.confirmEchoedPassword = confirmEchoedPassword
        super.init()
    }

    // MARK: - iTermEchoProbeDelegate

    @objc(echoProbe:writeString:)
    func echoProbe(_ echoProbe: iTermEchoProbe?, write string: String) {
        guard let host else { return }
        host.echoProbeNoteUserInput()
        if PTYSessionEchoProbePolicy.shouldSuppressWrite(tmuxMode: host.tmuxMode) {
            return
        }
        host.echoProbeWriteString(string)
        let message = PTYSessionEchoProbePolicy.passwordSentMessage(
            sendReturnAfterPassword: shouldSendReturnAfterPassword()
        )
        host.echoProbeShowUnobtrusiveMessage(message, duration: 3)
    }

    @objc(echoProbe:writeData:)
    func echoProbe(_ echoProbe: iTermEchoProbe, write data: Data) {
        guard let host else { return }
        host.echoProbeNoteUserInput()
        if PTYSessionEchoProbePolicy.shouldSuppressWrite(tmuxMode: host.tmuxMode) {
            return
        }
        host.echoProbeWriteLatin1Data(data)
    }

    @objc(echoProbeDidFail:)
    func echoProbeDidFail(_ echoProbe: iTermEchoProbe) {
        // Not allowed to use a runloop in a side-effect.
        DispatchQueue.main.async { [weak self] in
            self?.sendPasswordAfterGettingPermission()
        }
    }

    @objc func sendPasswordAfterGettingPermission() {
        guard let host else { return }
        if confirmEchoedPassword(host.echoProbeWindow) {
            host.echoProbeSendPassword()
        } else {
            host.echoProbeIncrementDisableFocusReporting(-1)
            host.echoProbeReset()
        }
    }

    @objc(echoProbeDidSucceed:)
    func echoProbeDidSucceed(_ echoProbe: iTermEchoProbe) {
        host?.echoProbeIncrementDisableFocusReporting(-1)
    }

    @objc(echoProbeShouldSendPassword:)
    func echoProbeShouldSendPassword(_ echoProbe: iTermEchoProbe) -> Bool {
        return true
    }

    @objc(echoProbeDelegateWillChange:)
    func echoProbeDelegateWillChange(_ echoProbe: iTermEchoProbe) {
    }
}
