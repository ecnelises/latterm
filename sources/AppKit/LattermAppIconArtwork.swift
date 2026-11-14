//
//  LattermAppIconArtwork.swift
//  Latterm
//

import Cocoa
import CoreGraphics

@objc(iTermAppIconChannel)
public enum AppIconChannel: Int {
    case stable = 0
    case alpha = 1
    case beta = 2

    public static func detect(bundleIconName: String?, isBetaOrAlphaFlag: Bool) -> AppIconChannel {
        if let name = bundleIconName {
            if name.localizedCaseInsensitiveContains("Beta") {
                return .beta
            }
            if name.localizedCaseInsensitiveContains("Nightly") {
                return .alpha
            }
            if name.localizedCaseInsensitiveContains("Release") {
                return isBetaOrAlphaFlag ? .alpha : .stable
            }
        }
        return isBetaOrAlphaFlag ? .alpha : .stable
    }

    public var badgeSuffixKey: String? {
        switch self {
        case .stable:
            return nil
        case .alpha:
            return "α"
        case .beta:
            return "β"
        }
    }
}

public enum AppIconGroup: CaseIterable {
    case concept
    case promptGlyph

    public var localizedTitle: String {
        switch self {
        case .concept:
            return NSLocalizedString("Concepts", comment: "Settings section group for primary Latterm icon concepts")
        case .promptGlyph:
            return NSLocalizedString("Prompt Glyphs", comment: "Settings section group for prompt glyph Latterm icons")
        }
    }
}

/// All 15 non-split icon designs from the Latterm icon catalog.
public enum AppIconVariant: String, CaseIterable, Identifiable {
    // Primary concepts (excluding split)
    case ink = "ink"
    case paper = "paper"
    case flame = "flame"
    case cobalt = "cobalt"
    case block = "block"
    case monogram = "monogram"

    // Prompt glyphs
    case glyphDollar = "glyph-dollar"
    case glyphDollarPaper = "glyph-dollar-paper"
    case glyphHash = "glyph-hash"
    case glyphHashPaper = "glyph-hash-paper"
    case glyphPercent = "glyph-percent"
    case glyphPercentPaper = "glyph-percent-paper"
    case glyphLambda = "glyph-lambda"
    case glyphLambdaPaper = "glyph-lambda-paper"
    case glyphLt = "glyph-lt"

    public var id: String { rawValue }

    public static var defaultLight: AppIconVariant { .paper }
    public static var defaultDark: AppIconVariant { .ink }

    public var group: AppIconGroup {
        switch self {
        case .ink, .paper, .flame, .cobalt, .block, .monogram:
            return .concept
        case .glyphDollar, .glyphDollarPaper,
             .glyphHash, .glyphHashPaper,
             .glyphPercent, .glyphPercentPaper,
             .glyphLambda, .glyphLambdaPaper,
             .glyphLt:
            return .promptGlyph
        }
    }

    public var localizedTitle: String {
        switch self {
        case .ink:
            return NSLocalizedString("Ink (>_)", comment: "App icon option: Ink dark chevron colorway")
        case .paper:
            return NSLocalizedString("Paper (>_)", comment: "App icon option: Paper light chevron colorway")
        case .flame:
            return NSLocalizedString("Flame (>_)", comment: "App icon option: Flame orange chevron colorway")
        case .cobalt:
            return NSLocalizedString("Cobalt (>_)", comment: "App icon option: Cobalt blue chevron colorway")
        case .block:
            return NSLocalizedString("Block Cursor", comment: "App icon option: Solid orange block cursor")
        case .monogram:
            return NSLocalizedString("Monogram (L_)", comment: "App icon option: L monogram with orange cursor")
        case .glyphDollar:
            return NSLocalizedString("Dollar — Ink ($_)", comment: "App icon option: Dollar prompt glyph on ink")
        case .glyphDollarPaper:
            return NSLocalizedString("Dollar — Paper ($_)", comment: "App icon option: Dollar prompt glyph on paper")
        case .glyphHash:
            return NSLocalizedString("Hash — Ink (#_)", comment: "App icon option: Hash prompt glyph on ink")
        case .glyphHashPaper:
            return NSLocalizedString("Hash — Paper (#_)", comment: "App icon option: Hash prompt glyph on paper")
        case .glyphPercent:
            return NSLocalizedString("Percent — Ink (%_)", comment: "App icon option: Percent prompt glyph on ink")
        case .glyphPercentPaper:
            return NSLocalizedString("Percent — Paper (%_)", comment: "App icon option: Percent prompt glyph on paper")
        case .glyphLambda:
            return NSLocalizedString("Lambda — Ink (λ_)", comment: "App icon option: Lambda prompt glyph on ink")
        case .glyphLambdaPaper:
            return NSLocalizedString("Lambda — Paper (λ_)", comment: "App icon option: Lambda prompt glyph on paper")
        case .glyphLt:
            return NSLocalizedString("Less Than (<_)", comment: "App icon option: Reverse chevron glyph on ink")
        }
    }

    public static func resolve(_ rawValue: String?, fallback: AppIconVariant) -> AppIconVariant {
        guard let rawValue, let matched = AppIconVariant(rawValue: rawValue) else {
            return fallback
        }
        return matched
    }
}

public enum AppIconBundleArtwork {
    case release
    case nightly
    case beta
}

public enum LattermAppIconRenderer {
    public enum Palette {
        static let ink = CGColor(srgbRed: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1)
        static let paper = CGColor(srgbRed: 0xf5 / 255.0, green: 0xf2 / 255.0, blue: 0xec / 255.0, alpha: 1)
        static let flame = CGColor(srgbRed: 0xff / 255.0, green: 0x6a / 255.0, blue: 0x1a / 255.0, alpha: 1)
        static let cobalt = CGColor(srgbRed: 0x1f / 255.0, green: 0x3c / 255.0, blue: 0xff / 255.0, alpha: 1)
        static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    private static let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private struct VariantColors {
        let body: CGColor
        let glyph: CGColor
        let cursor: CGColor
    }

    private static func colors(for variant: AppIconVariant) -> VariantColors {
        switch variant {
        case .ink, .block, .monogram, .glyphLt,
             .glyphDollar, .glyphHash, .glyphPercent, .glyphLambda:
            return VariantColors(
                body: Palette.ink,
                glyph: Palette.paper,
                cursor: Palette.flame
            )
        case .paper,
             .glyphDollarPaper, .glyphHashPaper, .glyphPercentPaper, .glyphLambdaPaper:
            return VariantColors(
                body: Palette.paper,
                glyph: Palette.ink,
                cursor: Palette.flame
            )
        case .flame:
            return VariantColors(
                body: Palette.flame,
                glyph: Palette.ink,
                cursor: Palette.ink
            )
        case .cobalt:
            return VariantColors(
                body: Palette.cobalt,
                glyph: Palette.white,
                cursor: Palette.white
            )
        }
    }

    /// Creates a multi-representation NSImage suitable for NSApp.applicationIconImage or UI previews.
    public static func makeIconImage(variant: AppIconVariant,
                                     channel: AppIconChannel,
                                     logicalSize: CGSize = CGSize(width: 512, height: 512),
                                     pixelSizes: [Int] = [64, 128, 256, 512, 1024]) -> NSImage {
        let image = NSImage(size: logicalSize)
        for pixelSize in pixelSizes {
            if let rep = makeBitmapRep(pixelSize: pixelSize, draw: { ctx in
                drawVariantIcon(in: ctx, size: CGFloat(pixelSize), variant: variant, channel: channel)
            }) {
                rep.size = logicalSize
                image.addRepresentation(rep)
            }
        }
        return image
    }

    /// Creates a crisp transparent foreground CGImage mapped to Icon Composer's `[100..924]` interior
    /// (`bodySize = 824` within `1024` canvas -> scaled to full-bleed `pixelSize` with `scale = 1.2427`).
    public static func makeIconComposerForegroundCGImage(artwork: AppIconBundleArtwork,
                                                         pixelSize: Int = 1024) -> CGImage? {
        guard let rep = makeBitmapRep(pixelSize: pixelSize, draw: { ctx in
            let scale = CGFloat(pixelSize) / 1024.0
            ctx.saveGState()
            // Flip into SVG top-left y-down coordinate system.
            ctx.translateBy(x: 0, y: CGFloat(pixelSize))
            ctx.scaleBy(x: scale, y: -scale)
            drawBundleForeground(in: ctx, artwork: artwork)
            ctx.restoreGState()
        }) else {
            return nil
        }
        return rep.cgImage
    }

    /// Creates a standalone 1024x1024 rasterized icon PNG CGImage (e.g., for legacy AppIcon.png).
    public static func makeBundleRasterCGImage(artwork: AppIconBundleArtwork,
                                               pixelSize: Int = 1024) -> CGImage? {
        guard let rep = makeBitmapRep(pixelSize: pixelSize, draw: { ctx in
            if artwork == .release {
                drawVariantIcon(in: ctx, size: CGFloat(pixelSize), variant: .ink, channel: .stable)
            } else {
                drawStyledBody(in: ctx, size: CGFloat(pixelSize), bodyColor: Palette.ink) { svgCtx in
                    drawBundleForeground(in: svgCtx, artwork: artwork)
                }
            }
        }) else {
            return nil
        }
        return rep.cgImage
    }

    // MARK: - Core Drawing

    private static func makeBitmapRep(pixelSize: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep? {
        guard pixelSize > 0 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }
        let ctx = graphicsContext.cgContext
        ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        draw(ctx)
        return rep
    }

    private static func drawVariantIcon(in ctx: CGContext,
                                        size: CGFloat,
                                        variant: AppIconVariant,
                                        channel: AppIconChannel) {
        let palette = colors(for: variant)
        drawStyledBody(in: ctx, size: size, bodyColor: palette.body) { svgCtx in
            drawVariantForeground(in: svgCtx, variant: variant, channel: channel, palette: palette)
        }
    }

    private static func drawStyledBody(in ctx: CGContext,
                                       size: CGFloat,
                                       bodyColor: CGColor,
                                       drawForegroundInSVGCoords: (CGContext) -> Void) {
        let scale = size / 1024.0
        let bodyRect = CGRect(x: 100.0 * scale, y: 100.0 * scale, width: 824.0 * scale, height: 824.0 * scale)
        let cornerRadius = 180.0 * scale
        let bodyPath = CGPath(roundedRect: bodyRect,
                              cornerWidth: cornerRadius,
                              cornerHeight: cornerRadius,
                              transform: nil)

        // 1. Outer drop shadow in unflipped CG coordinates (negative Y offset = downward shadow).
        ctx.saveGState()
        let shadowColor = CGColor(colorSpace: srgbColorSpace, components: [0, 0, 0, 0.30])
            ?? CGColor(gray: 0, alpha: 0.30)
        ctx.setShadow(offset: CGSize(width: 0, height: -10.0 * scale),
                      blur: 24.0 * scale,
                      color: shadowColor)
        ctx.addPath(bodyPath)
        ctx.setFillColor(bodyColor)
        ctx.fillPath()
        ctx.restoreGState()

        // 2. Clipped interior: solid body + vertical sheen gradient + SVG-space foreground.
        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()

        ctx.setFillColor(bodyColor)
        ctx.fill(bodyRect)

        drawSheenGradient(in: ctx, rect: bodyRect)

        ctx.saveGState()
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: scale, y: -scale)
        drawForegroundInSVGCoords(ctx)
        ctx.restoreGState()

        ctx.restoreGState()
    }

    private static func drawSheenGradient(in ctx: CGContext, rect: CGRect) {
        let locations: [CGFloat] = [0.0, 0.5, 0.5, 1.0]
        let colors = [
            CGColor(colorSpace: srgbColorSpace, components: [1, 1, 1, 0.10]),
            CGColor(colorSpace: srgbColorSpace, components: [1, 1, 1, 0.00]),
            CGColor(colorSpace: srgbColorSpace, components: [0, 0, 0, 0.00]),
            CGColor(colorSpace: srgbColorSpace, components: [0, 0, 0, 0.10])
        ].compactMap { $0 } as CFArray
        guard let gradient = CGGradient(colorsSpace: srgbColorSpace, colors: colors, locations: locations) else {
            return
        }
        // In unflipped CG coords, rect.maxY is the top edge and rect.minY is the bottom edge.
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.minX, y: rect.minY),
                               options: [])
    }

    // MARK: - Foreground Artwork (1024x1024 SVG Y-Down Coordinate Space)

    private static func drawBundleForeground(in ctx: CGContext, artwork: AppIconBundleArtwork) {
        let inkPalette = colors(for: .ink)
        switch artwork {
        case .release:
            drawVariantForeground(in: ctx, variant: .ink, channel: .stable, palette: inkPalette)
        case .nightly:
            drawVariantForeground(in: ctx, variant: .ink, channel: .alpha, palette: inkPalette)
        case .beta:
            drawVariantForeground(in: ctx, variant: .ink, channel: .beta, palette: inkPalette)
        }
    }

    private static func drawVariantForeground(in ctx: CGContext,
                                              variant: AppIconVariant,
                                              channel: AppIconChannel,
                                              palette: VariantColors) {
        switch variant {
        case .ink, .paper, .flame, .cobalt:
            drawChevronRight(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 584, baselineY: 740, color: palette.cursor)

        case .block:
            ctx.setFillColor(palette.cursor)
            ctx.fill(CGRect(x: 352, y: 232, width: 320, height: 560))
            switch channel {
            case .stable:
                break
            case .alpha:
                drawAlphaGlyph(in: ctx,
                               inRect: CGRect(x: 396, y: 400, width: 232, height: 224),
                               strokeWidth: 46,
                               color: palette.body)
            case .beta:
                drawBetaGlyph(in: ctx,
                              inRect: CGRect(x: 420, y: 356, width: 184, height: 312),
                              strokeWidth: 42,
                              color: palette.body)
            }

        case .monogram:
            switch channel {
            case .stable:
                ctx.setFillColor(palette.glyph)
                ctx.fill(CGRect(x: 300, y: 232, width: 140, height: 400))
                ctx.setFillColor(palette.cursor)
                ctx.fill(CGRect(x: 300, y: 672, width: 424, height: 140))
            case .alpha, .beta:
                ctx.setFillColor(palette.glyph)
                ctx.fill(CGRect(x: 244, y: 232, width: 132, height: 540))
                ctx.fill(CGRect(x: 244, y: 644, width: 242, height: 128))
                drawCursor(in: ctx, channel: channel, cursorX: 540, glyphCursorX: 548, baselineY: 772, color: palette.cursor)
            }

        case .glyphLt:
            drawChevronLeft(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 590, baselineY: 740, color: palette.cursor)

        case .glyphDollar, .glyphDollarPaper:
            drawDollarGlyph(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 566, baselineY: 756, color: palette.cursor)

        case .glyphHash, .glyphHashPaper:
            drawHashGlyph(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 566, baselineY: 756, color: palette.cursor)

        case .glyphPercent, .glyphPercentPaper:
            drawPercentGlyph(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 572, baselineY: 756, color: palette.cursor)

        case .glyphLambda, .glyphLambdaPaper:
            drawLambdaGlyph(in: ctx, color: palette.glyph)
            drawCursor(in: ctx, channel: channel, cursorX: 556, glyphCursorX: 566, baselineY: 756, color: palette.cursor)
        }
    }

    private static func drawChevronRight(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(120)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(4)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 290, y: 330))
        ctx.addLine(to: CGPoint(x: 480, y: 512))
        ctx.addLine(to: CGPoint(x: 290, y: 694))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawChevronLeft(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(120)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(4)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 480, y: 330))
        ctx.addLine(to: CGPoint(x: 290, y: 512))
        ctx.addLine(to: CGPoint(x: 480, y: 694))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawDollarGlyph(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.miter)

        // Exact SVG path: "M442,377 A95,95 0 1 0 360,520 A95,95 0 1 1 278,662"
        // Top-down CG coords (already Y-down), convert endpoint-parameterized SVG arcs via unit circle.
        ctx.setLineWidth(92)
        let sPath = CGMutablePath()
        sPath.move(to: CGPoint(x: 442, y: 377))
        addSVGArc(to: sPath,
                  from: CGPoint(x: 442, y: 377),
                  to: CGPoint(x: 360, y: 520),
                  radius: 95,
                  largeArc: true,
                  sweep: false)
        addSVGArc(to: sPath,
                  from: CGPoint(x: 360, y: 520),
                  to: CGPoint(x: 278, y: 662),
                  radius: 95,
                  largeArc: true,
                  sweep: true)
        ctx.addPath(sPath)
        ctx.strokePath()

        // Vertical bar: line (360, 236) -> (360, 804)
        ctx.setLineWidth(56)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 360, y: 236))
        ctx.addLine(to: CGPoint(x: 360, y: 804))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func addSVGArc(to path: CGMutablePath,
                                  from p1: CGPoint,
                                  to p2: CGPoint,
                                  radius r: CGFloat,
                                  largeArc: Bool,
                                  sweep: Bool) {
        // Exact SVG F.6.5 endpoint-to-center arc parameterization in Y-down user space.
        let x1p = (p1.x - p2.x) * 0.5
        let y1p = (p1.y - p2.y) * 0.5
        let dSq = x1p * x1p + y1p * y1p
        let rSq = r * r
        let factor = sqrt(max(0.0, (rSq - dSq) / max(dSq, 1e-6)))
        let sign: CGFloat = (largeArc == sweep) ? -1.0 : 1.0
        let cx = (p1.x + p2.x) * 0.5 + sign * factor * y1p
        let cy = (p1.y + p2.y) * 0.5 - sign * factor * x1p
        let startAngle = atan2(p1.y - cy, p1.x - cx)
        let endAngle = atan2(p2.y - cy, p2.x - cx)
        // CGPath interprets angles without CTM knowledge; in Y-down user space, increasing angle (+delta)
        // draws clockwise on screen (sweep == true -> CG clockwise == false).
        path.addArc(center: CGPoint(x: cx, y: cy),
                    radius: r,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: !sweep)
    }

    private static func drawHashGlyph(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(84)
        ctx.setLineCap(.butt)
        let segments: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 330, y: 290), CGPoint(x: 290, y: 756)),
            (CGPoint(x: 460, y: 290), CGPoint(x: 420, y: 756)),
            (CGPoint(x: 212, y: 430), CGPoint(x: 512, y: 430)),
            (CGPoint(x: 200, y: 612), CGPoint(x: 500, y: 612))
        ]
        for (start, end) in segments {
            ctx.beginPath()
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawPercentGlyph(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(84)
        ctx.setLineCap(.butt)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 480, y: 290))
        ctx.addLine(to: CGPoint(x: 240, y: 756))
        ctx.strokePath()

        ctx.fillEllipse(in: CGRect(x: 268 - 58, y: 364 - 58, width: 116, height: 116))
        ctx.fillEllipse(in: CGRect(x: 452 - 58, y: 682 - 58, width: 116, height: 116))
        ctx.restoreGState()
    }

    private static func drawLambdaGlyph(in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.beginPath()
        let points: [CGPoint] = [
            CGPoint(x: 250, y: 290),
            CGPoint(x: 352, y: 290),
            CGPoint(x: 512, y: 756),
            CGPoint(x: 410, y: 756),
            CGPoint(x: 360.5, y: 611.9),
            CGPoint(x: 300, y: 756),
            CGPoint(x: 190, y: 756),
            CGPoint(x: 311.0, y: 467.8)
        ]
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - Geometric Cursor (`_` / `α` / `β`)

    private static func drawCursor(in ctx: CGContext,
                                   channel: AppIconChannel,
                                   cursorX: CGFloat,
                                   glyphCursorX: CGFloat,
                                   baselineY: CGFloat,
                                   color: CGColor) {
        switch channel {
        case .stable:
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: cursorX, y: baselineY - 120, width: 230, height: 120))
        case .alpha:
            drawAlphaGlyph(in: ctx,
                           inRect: CGRect(x: glyphCursorX, y: baselineY - 244, width: 248, height: 250),
                           strokeWidth: 56,
                           color: color)
        case .beta:
            drawBetaGlyph(in: ctx,
                          inRect: CGRect(x: glyphCursorX + 8, y: baselineY - 332, width: 214, height: 344),
                          strokeWidth: 50,
                          color: color)
        }
    }

    /// Clean C1-continuous geometric lowercase alpha (`α`) mapped into `rect` (SVG Y-down coords).
    private static func drawAlphaGlyph(in ctx: CGContext,
                                       inRect rect: CGRect,
                                       strokeWidth: CGFloat,
                                       color: CGColor) {
        let halfStroke = strokeWidth * 0.5
        let x0 = rect.minX + halfStroke
        let y0 = rect.minY + halfStroke
        let w = max(1, rect.width - strokeWidth)
        let h = max(1, rect.height - strokeWidth)
        func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * w, y: y0 + ny * h)
        }

        // Smooth oval left bowl + distinct crossing diagonal legs so both branches separate rapidly below y=0.50.
        let path = CGMutablePath()
        // Enter from upper-right steeply down-left across the waist to the bottom of the bowl.
        path.move(to: p(0.92, 0.08))
        path.addCurve(to: p(0.35, 0.95),
                      control1: p(0.68, 0.36),
                      control2: p(0.50, 0.92))
        // Left side of bowl: vertical tangent at (0.04, 0.50) up to horizontal tangent at top.
        path.addCurve(to: p(0.04, 0.50),
                      control1: p(0.15, 0.95),
                      control2: p(0.04, 0.76))
        path.addCurve(to: p(0.36, 0.05),
                      control1: p(0.04, 0.24),
                      control2: p(0.16, 0.05))
        // Cross top-left -> bottom-right decisively out to the right foot.
        path.addCurve(to: p(0.94, 0.92),
                      control1: p(0.62, 0.05),
                      control2: p(0.76, 0.74))

        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Clean geometric lowercase beta (`β`) mapped into `rect` (SVG Y-down coords).
    private static func drawBetaGlyph(in ctx: CGContext,
                                      inRect rect: CGRect,
                                      strokeWidth: CGFloat,
                                      color: CGColor) {
        let halfStroke = strokeWidth * 0.5
        let x0 = rect.minX + halfStroke
        let y0 = rect.minY + halfStroke
        let w = max(1, rect.width - strokeWidth)
        let h = max(1, rect.height - strokeWidth)
        func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: x0 + nx * w, y: y0 + ny * h)
        }

        let path = CGMutablePath()
        // Descender stem up the left, arcing into upper bowl and then slightly fuller lower bowl.
        path.move(to: p(0.12, 0.99))
        path.addLine(to: p(0.12, 0.24))
        path.addCurve(to: p(0.50, 0.02),
                      control1: p(0.12, 0.09),
                      control2: p(0.28, 0.02))
        path.addCurve(to: p(0.84, 0.22),
                      control1: p(0.72, 0.02),
                      control2: p(0.84, 0.10))
        path.addCurve(to: p(0.42, 0.41),
                      control1: p(0.84, 0.34),
                      control2: p(0.68, 0.41))
        path.addLine(to: p(0.30, 0.41))
        path.move(to: p(0.42, 0.41))
        path.addCurve(to: p(0.92, 0.62),
                      control1: p(0.72, 0.41),
                      control2: p(0.92, 0.49))
        path.addCurve(to: p(0.48, 0.83),
                      control1: p(0.92, 0.75),
                      control2: p(0.74, 0.83))
        path.addLine(to: p(0.14, 0.83))

        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
