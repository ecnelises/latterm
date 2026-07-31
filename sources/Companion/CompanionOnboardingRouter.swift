//
//  CompanionOnboardingRouter.swift
//  iTerm2
//
//  Routes every Companion settings entry point to the terminal-focused pairing
//  window. Pairing no longer depends on an AI plugin, model, or API key.
//

import AppKit

@MainActor
@objc(iTermCompanionOnboardingRouter)
final class CompanionOnboardingRouter: NSObject {
    @objc static func openSettingsOrWizard() {
        CompanionPairingWindowController.shared.showAndBeginPairing()
    }
}
