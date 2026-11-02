//
//  AppSignatureValidator.swift
//  iTerm2
//
//  Created by George Nachman on 9/22/25.
//

import Foundation
import Security

@objc(iTermAppSignatureValidator)
class AppSignatureValidator: NSObject {
    /// Returns the Team Identifier of the current app if the code signature is valid.
    /// - Returns: The team ID string, or `nil` if the signature is invalid or missing.
    @objc
    static func currentAppTeamID() -> String? {
        let selfURL = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?

        let status = SecStaticCodeCreateWithPath(selfURL, [], &staticCode)
        if status != errSecSuccess {
            return nil
        }

        guard let code = staticCode else {
            return nil
        }

        let flags: SecCSFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let verifyStatus = SecStaticCodeCheckValidity(code, flags, nil)
        if verifyStatus != errSecSuccess {
            return nil
        }

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation|kSecCSRequirementInformation|kSecCSDynamicInformation), &info)
        if infoStatus != errSecSuccess {
            return nil
        }
        print(info as! [String:Any])
        guard let dict = info as? [String: Any],
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return nil
        }

        return teamID
    }

    @objc
    static func warn(reason: String) {
        let team = currentAppTeamID()
        let message = if team == nil {
            "A required file appears to be missing or corrupted and Latterm’s code signature could not be verified.\n\nYou should download a fresh copy of the app and reinstall it."
        } else if team != "R7ZJJDMW42" {
            "A required file appears to be missing or corrupted and Latterm’s code signature did not match that of the official distribution.\n\nYou should download a fresh copy of the app and reinstall it."
        } else {
            "A required file appears to be missing or corrupted, yet against all odds the code signature for Latterm is valid. Please file a bug at https://github.com/ecnelises/latterm/issues"
        }
        let alert = NSAlert()
        alert.messageText = "Application Corrupt"
        alert.informativeText = reason + ": " + message
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .critical
        alert.runModal()
    }
    // Do not continue with missing required resources or report installation damage as a crash.
    @objc static func warnAndExit(reason: String) -> Never {
        RLog("Exiting because the app is damaged: \(reason)")
        if Thread.isMainThread {
            warn(reason: reason)
            exit(1)
        }
        DispatchQueue.main.async {
            warn(reason: reason)
            exit(1)
        }
        let semaphore = DispatchSemaphore(value: 0)
        while true { semaphore.wait() }
    }

}
