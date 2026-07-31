//
//  CompanionAlertBridge.swift
//  iTerm2
//
//  Compatibility facade for legacy terminal-alert call sites. Companion now
//  exposes remote terminal control only; chat-backed notification delivery is
//  intentionally unavailable.
//

import Foundation

@MainActor
@objc(iTermCompanionAlertBridge)
final class CompanionAlertBridge: NSObject {
    @objc static var canEnableAlertsToPhone: Bool { false }

    @objc static var sendToPhoneStatusMessage: String {
        "Phone alerts are unavailable in this terminal-focused build."
    }

    @objc static func userEnabledAlertsToPhone() {}

    @objc static func postTerminalAlert(title: String, body: String, threadKey: String) {}
}
