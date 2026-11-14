//
//  LattermAppIconController.swift
//  Latterm
//

import Cocoa

@objc(iTermAppIconController)
@MainActor
public final class LattermAppIconController: NSObject {
    @objc public static let shared = LattermAppIconController()

    private var hasStarted = false
    private var appearanceObservation: NSKeyValueObservation?
    private var lastAppliedSignature: String?

    private override init() {
        super.init()
    }

    @objc public func start() {
        guard !hasStarted else {
            updateApplicationIcon()
            return
        }
        hasStarted = true

        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateApplicationIcon()
            }
        }

        let refresh: (Any?, Any?) -> Void = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateApplicationIcon()
            }
        }
        iTermPreferences.addObserver(forKey: kPreferenceKeyLightAppIcon, block: refresh)
        iTermPreferences.addObserver(forKey: kPreferenceKeyDarkAppIcon, block: refresh)
        iTermPreferences.addObserver(forKey: kPreferenceKeyTabStyle, block: refresh)

        updateApplicationIcon()
    }

    @objc public func updateApplicationIcon() {
        let isDark = NSApplication.shared.effectiveAppearance.it_isDark
        let lightRaw = iTermPreferences.string(forKey: kPreferenceKeyLightAppIcon)
        let darkRaw = iTermPreferences.string(forKey: kPreferenceKeyDarkAppIcon)
        let variant = Self.resolvedVariant(lightRawValue: lightRaw,
                                           darkRawValue: darkRaw,
                                           isDarkAppearance: isDark)
        let channel = Self.currentChannel()
        let signature = "\(variant.rawValue)|\(channel.rawValue)"
        guard signature != lastAppliedSignature else {
            return
        }
        lastAppliedSignature = signature
        let icon = LattermAppIconRenderer.makeIconImage(variant: variant, channel: channel)
        NSApplication.shared.applicationIconImage = icon
    }

    public static func currentChannel() -> AppIconChannel {
        let bundleIconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        return AppIconChannel.detect(bundleIconName: bundleIconName,
                                     isBetaOrAlphaFlag: iTermPreferences.isAlphaOrBetaBuild())
    }

    public static func resolvedVariant(lightRawValue: String?,
                                       darkRawValue: String?,
                                       isDarkAppearance: Bool) -> AppIconVariant {
        if isDarkAppearance {
            return AppIconVariant.resolve(darkRawValue, fallback: .defaultDark)
        }
        return AppIconVariant.resolve(lightRawValue, fallback: .defaultLight)
    }

    @objc public static func isEffectiveAppearanceDark() -> Bool {
        NSApplication.shared.effectiveAppearance.it_isDark
    }
}
