//
//  AppIconTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class AppIconTests: XCTestCase {
    func testCatalogHasAllFifteenNonSplitVariants() {
        let variants = AppIconVariant.allCases
        XCTAssertEqual(variants.count, 15)
        XCTAssertNil(AppIconVariant(rawValue: "split"))
        XCTAssertEqual(Set(variants.map(\.rawValue)).count, 15)
        XCTAssertEqual(AppIconVariant.defaultLight, .glyphHashPaper)
        XCTAssertEqual(AppIconVariant.defaultDark, .glyphHash)
        XCTAssertEqual(variants.filter { $0.group == .concept }.count, 6)
        XCTAssertEqual(variants.filter { $0.group == .promptGlyph }.count, 9)
    }

    func testChannelDetectionDistinguishesAlphaBetaAndStable() {
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: "iTerm2 App Icon for Release", isBetaOrAlphaFlag: false), .stable)
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: "iTerm2 App Icon for Nightly", isBetaOrAlphaFlag: true), .alpha)
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: "iTerm2 App Icon for Nightly", isBetaOrAlphaFlag: false), .alpha)
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: "iTerm2 App Icon for Beta", isBetaOrAlphaFlag: true), .beta)
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: nil, isBetaOrAlphaFlag: true), .alpha)
        XCTAssertEqual(AppIconChannel.detect(bundleIconName: nil, isBetaOrAlphaFlag: false), .stable)
    }

    @MainActor
    func testLightAndDarkVariantResolution() {
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: nil, darkRawValue: nil, isDarkAppearance: false),
            .glyphHashPaper
        )
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: nil, darkRawValue: nil, isDarkAppearance: true),
            .glyphHash
        )
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: "split", darkRawValue: "invalid", isDarkAppearance: false),
            .glyphHashPaper
        )
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: "split", darkRawValue: "invalid", isDarkAppearance: true),
            .glyphHash
        )
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: "cobalt", darkRawValue: "flame", isDarkAppearance: false),
            .cobalt
        )
        XCTAssertEqual(
            LattermAppIconController.resolvedVariant(lightRawValue: "cobalt", darkRawValue: "flame", isDarkAppearance: true),
            .flame
        )
    }

    func testAlphaMarkerPrecedesChevron() {
        for variant in [AppIconVariant.ink, .paper] {
            let image = LattermAppIconRenderer.makeIconImage(variant: variant, channel: .alpha,
                logicalSize: CGSize(width: 128, height: 128), pixelSizes: [128])
            guard let bitmap = image.representations.first as? NSBitmapImageRep else {
                XCTFail("Missing bitmap"); return
            }
            var leftOrange = 0
            var rightOrange = 0
            for y in 0..<128 {
                for x in 0..<128 {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.8 && color.greenComponent < 0.6 && color.blueComponent < 0.3 {
                        if x < 64 { leftOrange += 1 } else { rightOrange += 1 }
                    }
                }
            }
            XCTAssertGreaterThan(leftOrange, 50)
            XCTAssertEqual(rightOrange, 0)
        }
    }

    func testPreferenceDefaultsAreRegistered() {
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyLightAppIcon) as? String, "glyph-hash-paper")
        XCTAssertEqual(iTermPreferences.defaultObject(forKey: kPreferenceKeyDarkAppIcon) as? String, "glyph-hash")
    }

    func testAllVariantsRenderAndChannelCursorsDifferWithoutCornerBadge() {
        for variant in AppIconVariant.allCases {
            let image = LattermAppIconRenderer.makeIconImage(variant: variant,
                                                             channel: .stable,
                                                             logicalSize: CGSize(width: 64, height: 64),
                                                             pixelSizes: [64, 128])
            XCTAssertEqual(image.representations.count, 2, "Expected 64px and 128px representations for \(variant.rawValue)")

            let stableBytes = renderedPNGBytes(variant: variant, channel: .stable)
            let alphaBytes = renderedPNGBytes(variant: variant, channel: .alpha)
            let betaBytes = renderedPNGBytes(variant: variant, channel: .beta)

            XCTAssertNotNil(stableBytes, variant.rawValue)
            XCTAssertNotEqual(stableBytes, alphaBytes, "Alpha cursor should differ from stable for \(variant.rawValue)")
            XCTAssertNotEqual(stableBytes, betaBytes, "Beta cursor should differ from stable for \(variant.rawValue)")
            XCTAssertNotEqual(alphaBytes, betaBytes, "Alpha and Beta cursors should differ for \(variant.rawValue)")
        }

        // Top-right corner stays clean (identical between Stable and Alpha — no corner pill badge).
        let stableRep = LattermAppIconRenderer.makeIconImage(variant: .ink, channel: .stable, logicalSize: CGSize(width: 128, height: 128), pixelSizes: [128]).representations.first as? NSBitmapImageRep
        let alphaRep = LattermAppIconRenderer.makeIconImage(variant: .ink, channel: .alpha, logicalSize: CGSize(width: 128, height: 128), pixelSizes: [128]).representations.first as? NSBitmapImageRep
        XCTAssertNotNil(stableRep)
        XCTAssertNotNil(alphaRep)
        XCTAssertEqual(stableRep?.colorAt(x: 96, y: 24), alphaRep?.colorAt(x: 96, y: 24))
    }

    func testBundleArtworksRenderValidCGImages() {
        for artwork in [AppIconBundleArtwork.release, .nightly, .beta] {
            let foreground = LattermAppIconRenderer.makeIconComposerForegroundCGImage(artwork: artwork, pixelSize: 256)
            XCTAssertNotNil(foreground)
            XCTAssertEqual(foreground?.width, 256)
            XCTAssertEqual(foreground?.height, 256)
            let lightForeground = LattermAppIconRenderer.makeIconComposerForegroundCGImage(
                artwork: artwork, pixelSize: 256, variant: .glyphHashPaper)
            XCTAssertNotNil(lightForeground)
            let darkPNG = foreground.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            let lightPNG = lightForeground.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            XCTAssertNotEqual(darkPNG, lightPNG)

            let raster = LattermAppIconRenderer.makeBundleRasterCGImage(artwork: artwork, pixelSize: 256)
            XCTAssertNotNil(raster)
            XCTAssertEqual(raster?.width, 256)
            XCTAssertEqual(raster?.height, 256)
        }
    }

    @MainActor
    func testPreferencesViewPopulatesAllFifteenIconsWithoutSplit() {
        let view = AppIconPreferencesView(frame: .zero)
        XCTAssertLessThanOrEqual(view.preferredWidth, 512)
        XCTAssertLessThanOrEqual(view.frame.width, 512)

        for popup in [view.lightPopupButton, view.darkPopupButton] {
            let items = (popup.menu?.items ?? []).filter { !$0.isSeparatorItem && $0.isEnabled }
            let rawValues = items.compactMap { $0.representedObject as? String }
            XCTAssertEqual(rawValues, AppIconVariant.allCases.map(\.rawValue))
            XCTAssertFalse(rawValues.contains("split"))
            XCTAssertTrue(items.allSatisfy { $0.image != nil })
        }
    }

    func testHashGlyphStrokesAreBalanced() throws {
        let foreground = try XCTUnwrap(
            LattermAppIconRenderer.makeIconComposerForegroundCGImage(artwork: .release,
                                                                     pixelSize: 1024,
                                                                     variant: .glyphHash)
        )
        let rep = NSBitmapImageRep(cgImage: foreground)
        func opaqueSpan(atY y: Int) -> (minX: Int, maxX: Int)? {
            var minX: Int?
            var maxX: Int?
            for x in 0..<550 {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                    if minX == nil { minX = x }
                    maxX = x
                }
            }
            guard let minX, let maxX else { return nil }
            return (minX, maxX)
        }
        // Check vertical stem centers against the horizontal bar centers (scaled 0.92 around y=512).
        let topBar = try XCTUnwrap(opaqueSpan(atY: 426))
        let botBar = try XCTUnwrap(opaqueSpan(atY: 594))
        let midVerts = try XCTUnwrap(opaqueSpan(atY: 510))
        let barCenter = Double(topBar.minX + topBar.maxX + botBar.minX + botBar.maxX) / 4.0
        let vertCenter = Double(midVerts.minX + midVerts.maxX) / 2.0
        XCTAssertLessThanOrEqual(abs(barCenter - vertCenter), 4.0)
    }

    func testForegroundContentIsCenteredWithSymmetricPadding() throws {
        for artwork in [AppIconBundleArtwork.release, .nightly, .beta] {
            for variant in [AppIconVariant.glyphHash, .ink, .monogram, .glyphDollar, .glyphPercent, .glyphLambda, .glyphLt] {
                let cg = try XCTUnwrap(
                    LattermAppIconRenderer.makeIconComposerForegroundCGImage(artwork: artwork,
                                                                             pixelSize: 256,
                                                                             variant: variant)
                )
                let rep = NSBitmapImageRep(cgImage: cg)
                let data = try XCTUnwrap(rep.bitmapData)
                let bpr = rep.bytesPerRow
                var minX = 256, maxX = -1, minY = 256, maxY = -1
                for y in 0..<256 {
                    for x in 0..<256 {
                        if data[y * bpr + x * 4 + 3] > 16 {
                            if x < minX { minX = x }
                            if x > maxX { maxX = x }
                            if y < minY { minY = y }
                            if y > maxY { maxY = y }
                        }
                    }
                }
                let leftPad = minX - 25
                let rightPad = 230 - maxX
                let topPad = minY - 25
                let bottomPad = 230 - maxY
                XCTAssertLessThanOrEqual(abs(leftPad - rightPad), 1, "\(artwork) \(variant.rawValue) asymmetric horizontal padding: \(leftPad) vs \(rightPad)")
                XCTAssertLessThanOrEqual(abs(topPad - bottomPad), 1, "\(artwork) \(variant.rawValue) asymmetric vertical padding: \(topPad) vs \(bottomPad)")
                XCTAssertGreaterThanOrEqual(leftPad, 30, "\(artwork) \(variant.rawValue) should retain breathing room at 92% scale")
            }
        }
    }

    @MainActor
    func testBundleIconPersistenceLifecycle() throws {
        let suiteName = "com.latterm.tests.appicon.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var hasCustomIcon = false
        var writable = true
        var bundlePath = "/Applications/Latterm.app"
        var calls: [(hasImage: Bool, path: String)] = []

        func makePersistence(isRunningTests: Bool = false) -> AppIconBundlePersistence {
            AppIconBundlePersistence(
                bundlePath: bundlePath,
                isRunningTests: isRunningTests,
                isWritable: { _ in writable },
                hasCustomIconFile: { _ in hasCustomIcon },
                setIcon: { image, path in
                    calls.append((hasImage: image != nil, path: path))
                    hasCustomIcon = (image != nil)
                    return true
                }
            )
        }

        let sampleIcon = LattermAppIconRenderer.makeIconImage(variant: .cobalt,
                                                              channel: .stable,
                                                              logicalSize: CGSize(width: 64, height: 64),
                                                              pixelSizes: [64])

        // 1. Default Light + Dark with no Icon\r performs zero disk writes.
        XCTAssertFalse(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "glyph-hash|0",
            lightVariant: .defaultLight,
            darkVariant: .defaultDark,
            persistence: makePersistence(),
            defaults: defaults
        ))
        XCTAssertTrue(calls.isEmpty)

        // 2. Selecting a custom icon writes the icon and records the signature.
        XCTAssertTrue(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "cobalt|0",
            lightVariant: .cobalt,
            darkVariant: .defaultDark,
            persistence: makePersistence(),
            defaults: defaults
        ))
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].hasImage)
        XCTAssertEqual(defaults.string(forKey: LattermAppIconController.lastPersistedSignatureKey), "cobalt|0")
        XCTAssertEqual(defaults.string(forKey: LattermAppIconController.lastPersistedBundlePathKey), bundlePath)

        // 3. Re-applying the same custom icon when Icon\r exists does not rewrite.
        XCTAssertFalse(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "cobalt|0",
            lightVariant: .cobalt,
            darkVariant: .defaultDark,
            persistence: makePersistence(),
            defaults: defaults
        ))
        XCTAssertEqual(calls.count, 1)

        // 4. Re-applying after simulated app update (Icon\r missing) re-writes the icon.
        hasCustomIcon = false
        XCTAssertTrue(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "cobalt|0",
            lightVariant: .cobalt,
            darkVariant: .defaultDark,
            persistence: makePersistence(),
            defaults: defaults
        ))
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].hasImage)

        // 5. Switching back to default Light + Dark when Icon\r exists clears it.
        XCTAssertTrue(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "glyph-hash|0",
            lightVariant: .defaultLight,
            darkVariant: .defaultDark,
            persistence: makePersistence(),
            defaults: defaults
        ))
        XCTAssertEqual(calls.count, 3)
        XCTAssertFalse(calls[2].hasImage)
        XCTAssertNil(defaults.string(forKey: LattermAppIconController.lastPersistedSignatureKey))
        XCTAssertNil(defaults.string(forKey: LattermAppIconController.lastPersistedBundlePathKey))

        // 6. Non-writable, non-.app, or test-host paths skip safely.
        writable = false
        XCTAssertFalse(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "flame|0",
            lightVariant: .flame,
            darkVariant: .flame,
            persistence: makePersistence(),
            defaults: defaults
        ))
        writable = true
        bundlePath = "/tmp/NotAnApp"
        XCTAssertFalse(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "flame|0",
            lightVariant: .flame,
            darkVariant: .flame,
            persistence: makePersistence(),
            defaults: defaults
        ))
        bundlePath = "/Applications/Latterm.app"
        XCTAssertFalse(LattermAppIconController.persistBundleIconIfNeeded(
            icon: sampleIcon,
            signature: "flame|0",
            lightVariant: .flame,
            darkVariant: .flame,
            persistence: makePersistence(isRunningTests: true),
            defaults: defaults
        ))
        XCTAssertEqual(calls.count, 3)
    }

    private func renderedPNGBytes(variant: AppIconVariant, channel: AppIconChannel) -> Data? {
        let image = LattermAppIconRenderer.makeIconImage(variant: variant,
                                                         channel: channel,
                                                         logicalSize: CGSize(width: 128, height: 128),
                                                         pixelSizes: [128])
        guard let rep = image.representations.first as? NSBitmapImageRep else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
