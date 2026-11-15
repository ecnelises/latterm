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
