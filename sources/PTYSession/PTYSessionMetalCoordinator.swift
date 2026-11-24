//
//  PTYSessionMetalCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa
import Metal

enum PTYSessionMetalConstants {
    static let maximumMetalViewSize: CGFloat = 16384
}

struct PTYSessionMetalGlyphMetrics: Equatable {
    let singleWidthPixelSize: CGSize
    let doubleWidthPixelSize: CGSize

    static func compute(glyphSize: CGSize,
                        scale: CGFloat,
                        maxCharacterParts: Int32 = iTermTextureMapMaxCharacterParts) -> PTYSessionMetalGlyphMetrics? {
        guard scale > 0,
              glyphSize.width > 0,
              glyphSize.height > 0,
              maxCharacterParts > 0 else {
            return nil
        }
        let radius = CGFloat((Int(maxCharacterParts) / 2) * 2 + 1)
        let scaledSize = CGSize(width: glyphSize.width * scale * radius,
                                height: glyphSize.height * scale * radius)
        let dwMaxParts = CGFloat(Int(maxCharacterParts) * 2 + 1)
        let dwSize = CGSize(width: glyphSize.width * scale * dwMaxParts,
                            height: glyphSize.height * scale * dwMaxParts)
        guard Int(scaledSize.width) > 0,
              Int(scaledSize.height) > 0,
              Int(dwSize.width) > 0,
              Int(dwSize.height) > 0 else {
            return nil
        }
        return PTYSessionMetalGlyphMetrics(singleWidthPixelSize: scaledSize,
                                           doubleWidthPixelSize: dwSize)
    }

    static func asciiGlyphGeometry(cellSize: CGSize,
                                   boundingRect: CGRect,
                                   scale: CGFloat) -> (glyphSize: CGSize, asciiOffset: CGSize) {
        var asciiOffset = CGSize.zero
        var extraGlyphSize = CGSize.zero
        if boundingRect.origin.y < 0 {
            // Fonts that ride very low in their box need extra vertical margin in the texture.
            extraGlyphSize.height = -floor(boundingRect.origin.y * scale)
        }
        if boundingRect.origin.x < 0 {
            // Fonts with ink at negative X need a horizontal offset so glyphs stay left-aligned.
            asciiOffset.width = -floor(boundingRect.origin.x * scale)
            extraGlyphSize.width = abs(asciiOffset.width)
        }
        var glyphSize = CGSize(
            width: round(1 + max(cellSize.width, boundingRect.maxX)),
            height: round(1 + max(cellSize.height, boundingRect.maxY))
        )
        glyphSize.width += extraGlyphSize.width * 2
        glyphSize.height += extraGlyphSize.height * 2
        return (glyphSize, asciiOffset)
    }
}

struct PTYSessionMetalEligibilityInputs: Equatable {
    var disableInLowPowerMode: Bool
    var isLowPowerModeEnabled: Bool
    var machineSupportsMetal: Bool
    var useMetalPreference: Bool
    var hasWindow: Bool
    var hasOnePixelContext: Bool
    var metalDeviceChanging: Bool
    var metalViewSizeIsLegal: Bool
    var hasTextView: Bool
    var showDropTargets: Bool
    var usingIntegratedGPU: Bool
    var windowOccludedFraction: Double
}

enum PTYSessionMetalPolicy {
    static func isViewSizeLegal(_ size: CGSize,
                                maxScale: CGFloat = 2,
                                maxMetalViewSize: CGFloat = PTYSessionMetalConstants.maximumMetalViewSize) -> Bool {
        guard maxScale > 0 else {
            return false
        }
        let limit = maxMetalViewSize / maxScale
        return size.width > 0 && size.width < limit && size.height > 0 && size.height < limit
    }

    static func evaluate(_ inputs: PTYSessionMetalEligibilityInputs) -> iTermMetalUnavailableReason? {
        if inputs.disableInLowPowerMode && inputs.isLowPowerModeEnabled {
            return .lowerPowerMode
        }
        if !inputs.machineSupportsMetal {
            return .noGPU
        }
        if !inputs.useMetalPreference {
            return .disabled
        }
        if !inputs.hasWindow {
            return .sessionHasNoWindow
        }
        if !inputs.hasOnePixelContext {
            return .contextAllocationFailure
        }
        if inputs.metalDeviceChanging {
            return .initializing
        }
        if !inputs.metalViewSizeIsLegal {
            return .invalidSize
        }
        if !inputs.hasTextView {
            return .sessionInitializing
        }
        if inputs.showDropTargets {
            return .dropTargetsVisible
        }
        // Use window occlusion because of issue 9174, only for integrated GPUs because of issue 9044.
        if inputs.usingIntegratedGPU && inputs.windowOccludedFraction > 0.5 {
            return .windowObscured
        }
        return nil
    }
}

struct PTYSessionMetalDisablementTracker {
    private var nextToken: Int = 0
    private var tokens = Set<Int>()

    var activeCount: Int {
        return tokens.count
    }

    var isDisabled: Bool {
        return !tokens.isEmpty
    }

    var allTokensDescription: String {
        return tokens.sorted().description
    }

    mutating func acquireToken() -> NSNumber {
        let token = nextToken
        nextToken += 1
        tokens.insert(token)
        return NSNumber(value: token)
    }

    func contains(_ token: Any?) -> Bool {
        guard let number = token as? NSNumber else {
            return false
        }
        return tokens.contains(number.intValue)
    }

    var hasMultipleActiveTokens: Bool {
        return tokens.count > 1
    }

    @discardableResult
    mutating func release(_ token: Any?) -> Bool {
        guard let number = token as? NSNumber else {
            return false
        }
        return tokens.remove(number.intValue) != nil
    }

    mutating func clearAll() {
        tokens.removeAll()
    }
}

@objc
final class PTYSessionMetalCoordinator: NSObject, iTermMetalGlueDelegate {
    private weak var session: PTYSession?

    private var _useMetal = false
    @objc var useMetal: Bool {
        get { _useMetal }
        set { setUseMetalValue(newValue) }
    }
    private var metalContext: CGContext?
    private var metalContextDoubleWidth: CGContext?
    private var errorCreatingMetalContext = false
    private var metalFrameChangePending = false
    private var metalDeviceChanging = false
    private var disablementTracker = PTYSessionMetalDisablementTracker()

    private static var hostBitmapInfo: UInt32 {
        let byteOrder: UInt32 = CFByteOrderGetCurrent() == CFByteOrder(CFByteOrderBigEndian.rawValue)
            ? CGBitmapInfo.byteOrder32Big.rawValue
            : CGBitmapInfo.byteOrder32Little.rawValue
        return CGImageAlphaInfo.premultipliedFirst.rawValue | byteOrder
    }

    private static let metalColorSpace: CGColorSpace = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return colorSpace
    }()

    private static let onePixelContext: CGContext? = {
        return CGContext(data: nil,
                         width: 1,
                         height: 1,
                         bitsPerComponent: 8,
                         bytesPerRow: 4,
                         space: metalColorSpace,
                         bitmapInfo: hostBitmapInfo)
    }()

    private static let machineSupportsMetal: Bool = !MTLCopyAllDevices().isEmpty
    private static let systemHasIntegratedGPU: Bool = MTLCopyAllDevices().contains { $0.isLowPower }

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - iTermMetalGlueDelegate

    func metalGlueBackgroundImage() -> iTermImageWrapper? {
        guard let session else {
            return nil
        }
        if iTermPreferences.perPaneBackgroundImage() {
            return session.backgroundImage
        } else {
            return session.delegate?.sessionBackgroundImage()
        }
    }

    func metalGlueBackgroundImageMode() -> iTermBackgroundImageMode {
        guard let session else {
            return .stretch
        }
        if iTermPreferences.perPaneBackgroundImage() {
            return session.backgroundImageMode
        } else {
            return session.delegate?.sessionBackgroundImageMode() ?? .stretch
        }
    }

    func metalGlueBackgroundImageBlend() -> CGFloat {
        return session?.effectiveBlend ?? 0
    }

    func metalGlueDidDrawFrameAndNeedsRedraw(_ redrawAsap: Bool) {
        guard let session else {
            return
        }
        if session.view?.useMetal == true, redrawAsap {
            session.textview?.requestDelegateRedraw()
        }
    }

    func metalGlueContext() -> CGContext? {
        return metalContext
    }

    func metalGlueContextDoubleWidth() -> CGContext? {
        return metalContextDoubleWidth
    }

    // MARK: - Eligibility & State

    @objc
    func metalAllowed(_ reason: UnsafeMutablePointer<iTermMetalUnavailableReason>?) -> Bool {
        guard let session else {
            return false
        }
        let inputs = PTYSessionMetalEligibilityInputs(
            disableInLowPowerMode: iTermPreferences.bool(forKey: kPreferenceKeyDisableInLowPowerMode),
            isLowPowerModeEnabled: iTermPowerManager.sharedInstance()?.isLowPowerModeEnabled ?? false,
            machineSupportsMetal: Self.machineSupportsMetal,
            useMetalPreference: iTermPreferences.bool(forKey: kPreferenceKeyUseMetal),
            hasWindow: session.view?.window != nil,
            hasOnePixelContext: Self.onePixelContext != nil,
            metalDeviceChanging: metalDeviceChanging,
            metalViewSizeIsLegal: metalViewSizeIsLegal(),
            hasTextView: session.textview != nil,
            showDropTargets: session.textview?.drawingHelper.showDropTargets ?? false,
            usingIntegratedGPU: usingIntegratedGPU(),
            windowOccludedFraction: session.delegate?.realParentWindow()?.ptyWindow()?.approximateFractionOccluded() ?? 0
        )
        if let unavailableReason = PTYSessionMetalPolicy.evaluate(inputs) {
            if let reason {
                reason.pointee = unavailableReason
            }
            return false
        }
        return true
    }

    @objc
    func canProduceMetalFramecap() -> Bool {
        guard let session else {
            return false
        }
        let alphaIsOne = MainActor.assumeIsolated {
            session.view?.metalView?.alphaValue == 1
        }
        let wrapperUseMetal = session.textViewWrapperUseMetal
        let suppressDrawing = session.textview?.suppressDrawing ?? false
        DLog("useMetal=\(useMetal) view.metalView.alphaValue=\(alphaIsOne) wrapper.useMetal=\(wrapperUseMetal) textview.suppressDrawing=\(suppressDrawing)")
        return useMetal && alphaIsOne && wrapperUseMetal && suppressDrawing
    }

    @objc
    func idleForMetal() -> Bool {
        guard let session else {
            return false
        }
        return !session.cadenceController.isActive &&
               !(session.view?.verticalScroller?.userScroll ?? false) &&
               !session.overrideGlobalDisableMetalWhenIdleSetting &&
               !session.metalDriverCapturingDebugInfo
    }

    @objc
    func willEnableMetal() -> Bool {
        DLog("\(String(describing: session))")
        updateMetalDriver()
        return metalContext != nil
    }

    private func setUseMetalValue(_ useMetal: Bool) {
        if useMetal == _useMetal {
            return
        }
        guard let session else {
            return
        }
        DLog("setUseMetal:\(useMetal) \(session)")
        _useMetal = useMetal
        // The metalview's alpha will initially be 0. Once it has drawn a frame we'll swap what is visible.
        session.applyMetalEnabled(toView: useMetal)
        if useMetal {
            updateMetalDriver()
            // wrapper.useMetal becomes YES after the first frame is done drawing
        } else {
            session.textViewWrapperUseMetal = false
            disablementTracker.clearAll()
            if metalContext != nil {
                // If metal is re-enabled later, it must not use the same context.
                // It's possible that a metal driver thread has survived this point
                // and will continue to use the context.
                metalContext = nil
            }
        }
        session.textview?.requestDelegateRedraw()
        session.cadenceController.changeCadenceIfNeeded()

        if useMetal {
            renderTwoMetalFramesAndShowMetalView()
        } else {
            MainActor.assumeIsolated {
                session.view?.metalView?.enableSetNeedsDisplay = false
            }
        }
    }

    // MARK: - Driver & Context Setup

    @objc
    func updateMetalDriver() {
        guard let session, let textview = session.textview else {
            return
        }
        DLog("\(session)")
        let cellSize = CGSize(width: textview.charWidth, height: textview.lineHeight)
        let scale = session.view?.window?.backingScaleFactor ?? 1
        guard let onePixel = Self.onePixelContext else {
            return
        }
        let rect = session.asciiBoundingRect(forScale: scale, context: onePixel)
        DLog("Bounding rect for \(textview.fontTable.asciiFont) is \(NSStringFromRect(rect))")
        DLog("Increase glyph size for monochrome")
        let (glyphSize, asciiOffset) = PTYSessionMetalGlyphMetrics.asciiGlyphGeometry(
            cellSize: cellSize,
            boundingRect: rect,
            scale: scale
        )
        DLog("Ascii offset is \(NSStringFromSize(asciiOffset))")
        DLog("cellSize=\(NSStringFromSize(cellSize)) glyphSize=\(NSStringFromSize(glyphSize))")
        setMetalContextSize(glyphSize)
        guard let metalContext else {
            DLog("\(session) Failed to allocate metal context. Disable metal and try again in 1 second.")
            if errorCreatingMetalContext {
                DLog("Already have a retry queued.")
                return
            }
            errorCreatingMetalContext = true
            session.delegate?.sessionUpdateMetalAllowed()
            if !useMetal {
                DLog("Failed to create context for \(session) but metal is not allowed")
                return
            }
            DLog("Failed to create context for \(session). schedule retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.retryMetalAfterContextAllocationFailure()
            }
            return
        }
        session.configureMetalDriver(
            withCellSize: cellSize,
            cellSizeWithoutSpacing: CGSize(width: textview.charWidthWithoutSpacing,
                                           height: textview.charHeightWithoutSpacing),
            glyphSize: glyphSize,
            gridSize: session.screen.currentGrid().size,
            asciiOffset: asciiOffset,
            scale: session.view?.window?.screen?.backingScaleFactor ?? 0,
            context: metalContext,
            legacyScrollbarWidth: UInt32(max(0, Int(legacyScrollbarWidth()))),
            rightExtraPoints: session.view?.actualRightExtra ?? 0,
            panelReservationPoints: session.view?.actualPanelReservation ?? 0
        )
    }

    // MARK: - Window Changes, Disablement, and Recreation

    @objc
    func sessionViewDidChangeWindowAfterMetalDriverUpdate() {
        guard let session else {
            return
        }
        // After a peer swap, the view may have had outstanding temporarilyDisableMetal
        // tokens dropped while it had no window, leaving the metal view stuck at alpha=0.
        // Now that we have a window again, render frames and show it.
        let alphaIsZero = MainActor.assumeIsolated {
            session.view?.metalView?.alphaValue == 0
        }
        if session.view?.window != nil &&
            useMetal &&
            !disablementTracker.isDisabled &&
            alphaIsZero {
            DLog("sessionViewDidChangeWindow: metal view alpha is 0 with no pending tokens; re-showing \(session)")
            renderTwoMetalFramesAndShowMetalView()
        }
    }

    @objc
    func temporarilyDisableMetal() -> Any {
        it_assert(useMetal, "temporarilyDisableMetal called when useMetal is false")
        session?.textViewWrapperUseMetal = false
        session?.textview?.suppressDrawing = false
        session?.view?.setSuppressLegacyDrawing(false)
        session?.updateWrapperAlpha(forMetalEnabled: false)
        setMetalViewAlphaValue(0)
        let token = disablementTracker.acquireToken()
        DLog("temporarilyDisableMetal return new token=\(token) \(String(describing: session))")
        return token
    }

    @objc(drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:)
    func drawFrameAndRemoveTemporarilyDisablementOfMetal(forToken token: Any?) {
        DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal \(String(describing: token))")
        if !useMetal {
            DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal returning early because useMetal is off")
            return
        }
        if disablementTracker.contains(token) {
            DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Found token \(String(describing: token))")
            if disablementTracker.hasMultipleActiveTokens {
                disablementTracker.release(token)
                DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: There are still other tokens remaining: \(disablementTracker.allTokensDescription)")
                return
            }
        } else {
            DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Bogus token \(String(describing: token))")
            return
        }

        guard let session else {
            return
        }
        DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal beginning async draw")
        session.drawMetalFrameAsynchronously { [weak self] ok in
            guard let self, let session = self.session else {
                return
            }
            DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal drawAsynchronouslyInView finished with ok=\(ok)")
            if !self.disablementTracker.contains(token) {
                DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Token \(String(describing: token)) is gone, not proceeding.")
                return
            }
            if session.view?.window == nil {
                // Drop the token instead of leaking it. We can't draw without a window, but a later
                // sessionViewDidChangeWindow will re-show the metal view when it returns.
                self.disablementTracker.release(token)
                DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Returning because the view has no window. Tokens are now \(self.disablementTracker.allTokensDescription)")
                return
            }
            if !self.useMetal {
                DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Returning because useMetal is off")
                return
            }
            if !ok {
                DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Schedule drawFrameAndRemoveTemporarilyDisablementOfMetal to run after a spin of the mainloop")
                if session.delegate == nil {
                    self.useMetal = false
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    if !self.disablementTracker.contains(token) {
                        DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: [after a spin of the runloop] Token \(String(describing: token)) is gone, not proceeding.")
                        return
                    }
                    self.drawFrameAndRemoveTemporarilyDisablementOfMetal(forToken: token)
                }
                return
            }

            it_assert(self.disablementTracker.contains(token), "Expected active metal disablement token")
            self.disablementTracker.release(token)
            DLog("drawFrameAndRemoveTemporarilyDisablementOfMetal: Remove temporarily disablement. Tokens are now \(self.disablementTracker.allTokensDescription)")
            if !self.disablementTracker.isDisabled && self.useMetal {
                self.reallyShowMetalViewImmediately()
            }
        }
    }

    @objc
    func sessionViewNeedsMetalFrameUpdate() {
        guard let session else {
            return
        }
        DLog("sessionViewNeedsMetalFrameUpdate \(session)")
        if metalFrameChangePending {
            DLog("sessionViewNeedsMetalFrameUpdate frame change pending, return")
            return
        }

        metalFrameChangePending = true
        let token = temporarilyDisableMetal()
        session.textview?.requestDelegateRedraw()
        DispatchQueue.main.async { [weak self] in
            guard let self, let session = self.session else {
                return
            }
            DLog("sessionViewNeedsMetalFrameUpdate \(session) in dispatch_async")
            self.metalFrameChangePending = false
            session.view?.reallyUpdateMetalViewFrame()
            DLog("sessionViewNeedsMetalFrameUpdate will draw frame and remove disablement")
            self.drawFrameAndRemoveTemporarilyDisablementOfMetal(forToken: token)
        }
    }

    @objc
    func sessionViewRecreateMetalView() {
        if metalDeviceChanging {
            return
        }
        DLog("sessionViewRecreateMetalView metalDeviceChanging<-YES")
        metalDeviceChanging = true
        session?.textview?.requestDelegateRedraw()
        session?.delegate?.sessionUpdateMetalAllowed()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.metalDeviceChanging = false
            DLog("sessionViewRecreateMetalView metalDeviceChanging<-NO")
            self.session?.delegate?.sessionUpdateMetalAllowed()
        }
    }

    // MARK: - Private Helpers

    private func setMetalContextSize(_ size: CGSize) {
        DLog("\(String(describing: session))")
        guard let window = session?.textview?.window else {
            DLog("No window")
            metalContext = nil
            return
        }

        let scale = window.backingScaleFactor
        guard let metrics = PTYSessionMetalGlyphMetrics.compute(glyphSize: size, scale: scale) else {
            metalContext = nil
            metalContextDoubleWidth = nil
            return
        }
        let scaledSize = metrics.singleWidthPixelSize
        if let existing = metalContext,
           CGSize(width: existing.width, height: existing.height) == scaledSize {
            DLog("No size change")
            return
        }
        metalContext = nil
        metalContextDoubleWidth = nil

        DLog("allocate new metal context of size \(NSStringFromSize(scaledSize))")
        let bitmapInfo = Self.hostBitmapInfo
        let width = Int(scaledSize.width)
        let height = Int(scaledSize.height)
        if let context = CGContext(data: nil,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: width * 4,
                                   space: Self.metalColorSpace,
                                   bitmapInfo: bitmapInfo) {
            context.clear(CGRect(origin: .zero, size: scaledSize))
            metalContext = context
        }

        // Double-width context uses a larger radius for overflow room.
        let dwSize = metrics.doubleWidthPixelSize
        let dwWidth = Int(dwSize.width)
        let dwHeight = Int(dwSize.height)
        if let dwContext = CGContext(data: nil,
                                     width: dwWidth,
                                     height: dwHeight,
                                     bitsPerComponent: 8,
                                     bytesPerRow: dwWidth * 4,
                                     space: Self.metalColorSpace,
                                     bitmapInfo: bitmapInfo) {
            if let data = dwContext.data {
                memset(data, 0, dwContext.bytesPerRow * dwHeight)
            }
            metalContextDoubleWidth = dwContext
        }
    }

    private func usingIntegratedGPU() -> Bool {
        if let ownDevice = MainActor.assumeIsolated({ session?.view?.metalView?.device }) {
            let result = ownDevice.isLowPower
            DLog("usingIntegratedGPU=\(result)")
            return result
        }
        for otherSession in iTermController.sharedInstance()?.allSessions() ?? [] {
            if let otherDevice = MainActor.assumeIsolated({ otherSession.view?.metalView?.device }) {
                let result = otherDevice.isLowPower
                DLog("Found another session \(otherSession) with a metal device, usingIntegratedGPU=\(result)")
                return result
            }
        }
        DLog("Check if the system has an integrated GPU")
        let result = Self.systemHasIntegratedGPU
        DLog("No sessions using GPU. Return \(result).")
        return result
    }

    private func metalViewSizeIsLegal() -> Bool {
        guard let size = session?.view?.frame.size else {
            return false
        }
        return PTYSessionMetalPolicy.isViewSizeLegal(size)
    }

    private func renderTwoMetalFramesAndShowMetalView() {
        // The first frame will be slow to draw. The second frame will be very
        // recent to minimize jitter. For reasons I haven't understood yet it seems
        // the first frame is sometimes transparent. I haven't seen that issue with
        // the second frame yet.
        renderMetalFramesAndShowMetalView(count: 2)
    }

    private func renderMetalFramesAndShowMetalView(count: Int) {
        guard useMetal, let session else {
            return
        }
        DLog("Begin async draw \(count) for \(session)")
        session.drawMetalFrameAsynchronously { [weak self] ok in
            guard let self, let session = self.session else {
                return
            }
            if !self.useMetal || session.exited {
                DLog("Finished async draw but metal off/exited for \(session)")
                return
            }
            if !ok {
                DLog("Finished async draw NOT OK for \(session)")
                // Wait 10ms to avoid burning CPU if it failed because it's slow to draw the first frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.renderMetalFramesAndShowMetalView(count: count)
                }
                return
            }
            if count <= 1 {
                DLog("Finished async draw ok for \(session)")
                self.showMetalViewImmediately()
            } else {
                self.renderMetalFramesAndShowMetalView(count: count - 1)
            }
        }
    }

    private func showMetalViewImmediately() {
        guard let session else {
            return
        }
        if !useMetal {
            DLog("Declining to show metal view immediately in \(session) because useMetal is NO")
            return
        }
        let boundsSize = MainActor.assumeIsolated {
            session.view?.metalView?.bounds.size ?? .zero
        }
        if boundsSize.width == 0 || boundsSize.height == 0 {
            DLog("Declining to show metal view immediately in \(session) because the view's size is \(NSStringFromSize(boundsSize))")
            return
        }
        guard let textview = session.textview else {
            DLog("Declining to show metal view immediately in \(session) because the textview is nil")
            return
        }
        if textview.dataSource == nil {
            DLog("Declining to show metal view immediately in \(session) because the textview's datasource is nil")
            return
        }
        if session.screen.width() == 0 || session.screen.height() == 0 {
            DLog("Declining to show metal view immediately in \(session) because the screen's size is \(session.screen.width())x\(session.screen.height())")
            return
        }
        reallyShowMetalViewImmediately()
    }

    private func reallyShowMetalViewImmediately() {
        DLog("reallyShowMetalViewImmediately")
        session?.view?.needsDisplay = true
        showMetalAndStopDrawingTextView()
        MainActor.assumeIsolated {
            session?.view?.metalView?.enableSetNeedsDisplay = true
        }
    }

    private func showMetalAndStopDrawingTextView() {
        // If the legacy view had been visible, hide it. Hiding it before the
        // first frame is drawn causes a flash of gray.
        DLog("showMetalAndStopDrawingTextView")
        session?.textViewWrapperUseMetal = true
        session?.textview?.suppressDrawing = true
        session?.view?.setSuppressLegacyDrawing(true)
        session?.updateWrapperAlpha(forMetalEnabled: true)
        setMetalViewAlphaValue(1)
    }

    private func setMetalViewAlphaValue(_ alphaValue: CGFloat) {
        guard let session else {
            return
        }
        MainActor.assumeIsolated {
            session.view?.metalView?.alphaValue = alphaValue
        }
        session.view?.didChangeMetalViewAlpha()
        session.delegate?.sessionDidChangeMetalViewAlphaValue(session, to: alphaValue)
    }

    private func legacyScrollbarWidth() -> CGFloat {
        guard let scrollview = session?.view?.scrollview else {
            return 0
        }
        if scrollview.scrollerStyle != .legacy {
            return 0
        }
        return scrollview.bounds.width - scrollview.contentView.bounds.width
    }

    private func retryMetalAfterContextAllocationFailure() {
        guard let session else {
            return
        }
        DLog("\(session) It's been one second since trying to allocate a metal context failed. Try again.")
        if !errorCreatingMetalContext {
            DLog("Oddly, errorCreatingMetalContext is NO")
            return
        }
        DLog("\(session) reset error state")
        errorCreatingMetalContext = false
        updateMetalDriver()
        if metalContext != nil {
            DLog("A metal context was allocated. Try to turn metal on for this tab.")
            session.delegate?.sessionUpdateMetalAllowed()
        } else {
            DLog("Failed to allocate context again. A retry should have been scheduled.")
        }
    }
}
