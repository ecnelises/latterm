//
//  LattermAppIconController.swift
//  Latterm
//

import Cocoa

public struct AppIconBundlePersistence {
    public var bundlePath: String
    public var isRunningTests: Bool
    public var isWritable: (String) -> Bool
    public var hasCustomIconFile: (String) -> Bool
    public var setIcon: (NSImage?, String) -> Bool

    public init(bundlePath: String,
                isRunningTests: Bool,
                isWritable: @escaping (String) -> Bool,
                hasCustomIconFile: @escaping (String) -> Bool,
                setIcon: @escaping (NSImage?, String) -> Bool) {
        self.bundlePath = bundlePath
        self.isRunningTests = isRunningTests
        self.isWritable = isWritable
        self.hasCustomIconFile = hasCustomIconFile
        self.setIcon = setIcon
    }

    @MainActor
    public static var live: AppIconBundlePersistence {
        AppIconBundlePersistence(
            bundlePath: Bundle.main.bundlePath,
            isRunningTests: NSClassFromString("XCTestCase") != nil,
            isWritable: { FileManager.default.isWritableFile(atPath: $0) },
            hasCustomIconFile: { bundlePath in
                let iconFilePath = (bundlePath as NSString).appendingPathComponent("Icon\r")
                return FileManager.default.fileExists(atPath: iconFilePath)
            },
            setIcon: { image, path in
                let ok = NSWorkspace.shared.setIcon(image, forFile: path, options: [])
                if ok {
                    NSWorkspace.shared.noteFileSystemChanged(path)
                }
                return ok
            }
        )
    }
}

@objc(iTermAppIconController)
@MainActor
public final class LattermAppIconController: NSObject {
    @objc public static let shared = LattermAppIconController()

    static let lastPersistedSignatureKey = "NoSyncLastPersistedAppIconSignature"
    static let lastPersistedBundlePathKey = "NoSyncLastPersistedAppIconBundlePath"

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
        let lightVariant = AppIconVariant.resolve(lightRaw, fallback: .defaultLight)
        let darkVariant = AppIconVariant.resolve(darkRaw, fallback: .defaultDark)
        let variant = isDark ? darkVariant : lightVariant
        let channel = Self.currentChannel()
        let signature = "\(variant.rawValue)|\(channel.rawValue)"

        if signature != lastAppliedSignature {
            lastAppliedSignature = signature
            let icon = LattermAppIconRenderer.makeIconImage(variant: variant, channel: channel)
            NSApplication.shared.applicationIconImage = icon
            Self.persistBundleIconIfNeeded(icon: icon,
                                           signature: signature,
                                           lightVariant: lightVariant,
                                           darkVariant: darkVariant,
                                           persistence: .live,
                                           defaults: iTermUserDefaults.userDefaults())
        } else {
            Self.persistBundleIconIfNeeded(iconProvider: {
                LattermAppIconRenderer.makeIconImage(variant: variant, channel: channel)
            },
                                           signature: signature,
                                           lightVariant: lightVariant,
                                           darkVariant: darkVariant,
                                           persistence: .live,
                                           defaults: iTermUserDefaults.userDefaults())
        }
    }

    @discardableResult
    public static func persistBundleIconIfNeeded(icon: @autoclosure () -> NSImage,
                                                 signature: String,
                                                 lightVariant: AppIconVariant,
                                                 darkVariant: AppIconVariant,
                                                 persistence: AppIconBundlePersistence,
                                                 defaults: UserDefaults) -> Bool {
        return persistBundleIconIfNeeded(iconProvider: icon,
                                         signature: signature,
                                         lightVariant: lightVariant,
                                         darkVariant: darkVariant,
                                         persistence: persistence,
                                         defaults: defaults)
    }

    @discardableResult
    public static func persistBundleIconIfNeeded(iconProvider: () -> NSImage,
                                                 signature: String,
                                                 lightVariant: AppIconVariant,
                                                 darkVariant: AppIconVariant,
                                                 persistence: AppIconBundlePersistence,
                                                 defaults: UserDefaults) -> Bool {
        let bundlePath = persistence.bundlePath
        guard !persistence.isRunningTests,
              bundlePath.hasSuffix(".app"),
              persistence.isWritable(bundlePath) else {
            return false
        }

        let isUsingDefaultIcons = (lightVariant == .defaultLight && darkVariant == .defaultDark)
        let lastSignature = defaults.string(forKey: lastPersistedSignatureKey)
        let lastBundlePath = defaults.string(forKey: lastPersistedBundlePathKey)
        let hasCustomIcon = persistence.hasCustomIconFile(bundlePath)

        if isUsingDefaultIcons {
            guard hasCustomIcon || (lastSignature != nil && lastBundlePath == bundlePath) else {
                return false
            }
            let cleared = persistence.setIcon(nil, bundlePath)
            if cleared {
                defaults.removeObject(forKey: lastPersistedSignatureKey)
                defaults.removeObject(forKey: lastPersistedBundlePathKey)
            }
            return cleared
        }

        if lastSignature == signature && lastBundlePath == bundlePath && hasCustomIcon {
            return false
        }

        let applied = persistence.setIcon(iconProvider(), bundlePath)
        if applied {
            defaults.set(signature, forKey: lastPersistedSignatureKey)
            defaults.set(bundlePath, forKey: lastPersistedBundlePathKey)
        }
        return applied
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
