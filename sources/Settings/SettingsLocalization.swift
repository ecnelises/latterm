import Foundation

/// Resolve language-specific NIBs explicitly; the legacy resource at the bundle
/// root otherwise shadows them. Keep the original NIB as the fallback.
@objc(iTermSettingsLocalization)
final class SettingsLocalization: NSObject {
    @objc static func nibPath(_ name: String) -> String? {
        let bundle = Bundle.main
        for language in bundle.preferredLocalizations {
            if let path = bundle.path(forResource: name, ofType: "nib", inDirectory: "\(language).lproj") {
                return path
            }
        }
        return bundle.path(forResource: name, ofType: "nib")
    }
}
