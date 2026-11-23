//  MetalCaptureRestoration.swift
//  Latterm

import Foundation

@objc final class MetalCaptureRestoration: NSObject {
    /// The run loop owns the timer. Its callbacks hold the capture session and
    /// tokens until the driver consumes the request or the session exits.
    @objc(whileCaptureIsPending:restoreSessionsWithTokens:)
    static func afterCapture(isPending: @escaping () -> Bool, restoreSessionsWith tokens: [String: Any]) {
        let timer = restorationTimer(isPending: isPending, restore: {
            for (guid, token) in tokens {
                iTermController.sharedInstance().session(withGUID: guid)?
                    .drawFrameAndRemoveTemporarilyDisablementOfMetal(forToken: token)
            }
        })
        RunLoop.main.add(timer, forMode: .default)
    }

    static func restorationTimer(isPending: @escaping () -> Bool, restore: @escaping () -> Void) -> Timer {
        Timer(timeInterval: 1, repeats: true) { timer in
            guard !isPending() else { return }
            timer.invalidate()
            restore()
        }
    }
}
