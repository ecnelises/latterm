//
//  PTYSessionDisplayCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 3) to isolate display cadence,
//  background drawing, interval-tree minimap/porthole tracking, tail find,
//  async filter queueing, and composer color updates.
//

import Cocoa

enum PTYSessionCadencePolicy {
    static func useAdaptiveFrameRate(useMetal: Bool,
                                     maximizeThroughput: Bool,
                                     softAlternateScreenMode: Bool,
                                     disableAdaptiveInInteractiveApps: Bool,
                                     defaultUseAdaptiveFrameRate: Bool) -> Bool {
        if useMetal {
            return maximizeThroughput && !softAlternateScreenMode
        }
        if disableAdaptiveInInteractiveApps && softAlternateScreenMode {
            return false
        }
        return defaultUseAdaptiveFrameRate
    }

    static func slowFrameRate(useMetal: Bool,
                              metalSlowFrameRate: Double,
                              legacySlowFrameRate: Double) -> Double {
        return useMetal ? metalSlowFrameRate : legacySlowFrameRate
    }

    static func metalMaxFrameRate(lowPowerMode: Bool, lowPowerModeFrameRate: Int) -> Int {
        return lowPowerMode ? lowPowerModeFrameRate : 0
    }
}

enum PTYSessionMarksMinimapPolicy {
    static func tracksObjectType(_ type: iTermIntervalTreeObjectType) -> Bool {
        switch type {
        case .successMark,
             .otherMark,
             .errorMark,
             .manualMark,
             .annotation,
             .unknown:
            return true
        case .porthole:
            return false
        @unknown default:
            return false
        }
    }

    static func shouldUpdateMarks(showLocationsInScrollbar: Bool,
                                  showMarksInScrollbar: Bool) -> Bool {
        return showLocationsInScrollbar && showMarksInScrollbar
    }
}

struct PTYSessionFilterUpdateQueue {
    enum Item {
        case append(ScreenCharArray)
        case removeLastLine
    }

    private var items: [Item] = []

    var count: Int {
        return items.count
    }

    mutating func enqueueAppend(_ sca: ScreenCharArray) -> Bool {
        let wasEmpty = items.isEmpty
        items.append(.append(sca))
        return wasEmpty
    }

    mutating func enqueueRemoveLastLine() {
        items.append(.removeLastLine)
    }

    mutating func drain() -> [Item] {
        let drained = items
        items.removeAll(keepingCapacity: true)
        return drained
    }

    mutating func discardAll() {
        items.removeAll(keepingCapacity: false)
    }
}

@objc final class PTYSessionDisplayCoordinator: NSObject,
    iTermUpdateCadenceControllerDelegate,
    iTermBackgroundDrawingHelperDelegate,
    iTermIntervalTreeObserver,
    FilterDestination,
    TailFindControllerDelegate {

    private weak var session: PTYSession?
    private var filterUpdateQueue = PTYSessionFilterUpdateQueue()
    private var needsComposerColorUpdate = false

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - iTermUpdateCadenceControllerDelegate

    @objc(updateCadenceControllerUpdateDisplay:)
    func updateCadenceControllerUpdateDisplay(_ controller: iTermUpdateCadenceController?) {
        DLog("Cadence controller requests display")
        session?.updateDisplayBecause("Cadence controller update")
    }

    @objc func updateCadenceControllerState() -> iTermUpdateCadenceState {
        var state = iTermUpdateCadenceState()
        guard let session else {
            return state
        }
        state.active = ObjCBool(session.active)
        state.idle = ObjCBool(session.isIdle)
        let visibleTab = session.delegate?.sessionBelongsToVisibleTab() ?? false
        let miniaturized = session.view?.window?.isMiniaturized ?? false
        state.visible = ObjCBool(visibleTab && !miniaturized)

        let useMetal = session.useMetal
        state.useAdaptiveFrameRate = ObjCBool(PTYSessionCadencePolicy.useAdaptiveFrameRate(
            useMetal: useMetal,
            maximizeThroughput: iTermPreferences.maximizeThroughput(),
            softAlternateScreenMode: session.screen.terminalSoftAlternateScreenMode,
            disableAdaptiveInInteractiveApps: iTermAdvancedSettingsModel.disableAdaptiveFrameRateInInteractiveApps(),
            defaultUseAdaptiveFrameRate: session.useAdaptiveFrameRateSetting
        ))
        state.adaptiveFrameRateThroughputThreshold = session.adaptiveFrameRateThroughputThreshold
        state.slowFrameRate = PTYSessionCadencePolicy.slowFrameRate(
            useMetal: useMetal,
            metalSlowFrameRate: iTermAdvancedSettingsModel.metalSlowFrameRate(),
            legacySlowFrameRate: iTermAdvancedSettingsModel.slowFrameRate()
        )
        state.liveResizing = ObjCBool(session.inLiveResize)
        let supportsHighFrameRate = session.textview?.window?.screen?.it_supportsHighFrameRates() ?? false
        state.proMotion = ObjCBool(ProcessInfo.it_hasARMProcessor && supportsHighFrameRate)
        state.estimatedThroughput = session.estimatedThroughput
        state.lowPowerMode = ObjCBool(iTermPowerManager.sharedInstance().isLowPowerModeEnabled)
        return state
    }

    @objc(cadenceControllerActiveStateDidChange:)
    func cadenceControllerActiveStateDidChange(_ active: Bool) {
        session?.delegate?.sessionUpdateMetalAllowed()
    }

    @objc(cadenceController:didChangeCadence:)
    func cadenceController(_ controller: iTermUpdateCadenceController?,
                           didChangeCadence state: iTermUpdateCadenceState) {
        guard let session else { return }
        let frameRate = PTYSessionCadencePolicy.metalMaxFrameRate(
            lowPowerMode: state.lowPowerMode.boolValue,
            lowPowerModeFrameRate: Int(iTermAdvancedSettingsModel.lowPowerModeFrameRate())
        )
        MainActor.assumeIsolated {
            session.view?.metalView?.maxFrameRate = frameRate
        }
    }

    @objc func updateCadenceControllerWindowHasSheet() -> Bool {
        return !(session?.view?.window?.sheets.isEmpty ?? true)
    }

    // MARK: - iTermBackgroundDrawingHelperDelegate

    @objc func backgroundDrawingHelperView() -> SessionView? {
        return session?.view
    }

    @objc func backgroundDrawingHelperImage() -> iTermImageWrapper? {
        return session?.effectiveBackgroundImage
    }

    @objc func backgroundDrawingHelperUseTransparency() -> Bool {
        return session?.textview?.useTransparency ?? false
    }

    @objc func backgroundDrawingHelperTransparency() -> CGFloat {
        return session?.textview?.transparency ?? 0
    }

    @objc func backgroundDrawingHelperBackgroundImageMode() -> iTermBackgroundImageMode {
        return session?.effectiveBackgroundImageMode ?? .stretch
    }

    @objc func backgroundDrawingHelperDefaultBackgroundColor() -> NSColor? {
        return session?.processedBackgroundColor
    }

    @objc func backgroundDrawingHelperBlending() -> CGFloat {
        return session?.effectiveBlend ?? 0
    }

    // MARK: - iTermIntervalTreeObserver

    @objc func intervalTreeDidReset() {
        iTermGCD.assertMainQueueSafe()
        guard PTYSessionMarksMinimapPolicy.shouldUpdateMarks(
            showLocationsInScrollbar: iTermAdvancedSettingsModel.showLocationsInScrollbar(),
            showMarksInScrollbar: iTermAdvancedSettingsModel.showMarksInScrollbar()
        ) else {
            return
        }
        initializeMarksMinimap()
    }

    @objc func initializeMarksMinimap() {
        guard let session,
              let marksMinimap = session.view?.marksMinimap else {
            return
        }
        marksMinimap.removeAllObjects()
        let count = Int(iTermIntervalTreeObjectType.unknown.rawValue)
        var sets = [Int: NSMutableIndexSet]()
        session.screen.enumerateObservableMarks { type, line, _ in
            let key = Int(type.rawValue)
            let set = sets[key] ?? NSMutableIndexSet()
            sets[key] = set
            set.add(line)
        }
        for index in 0..<count {
            marksMinimap.setLines(sets[index] ?? NSMutableIndexSet(), forType: index)
        }
    }

    @objc(intervalTreeDidAddObjectOfType:onLine:)
    func intervalTreeDidAddObject(of type: iTermIntervalTreeObjectType, onLine line: Int) {
        addMarkToMinimap(ofType: type, onLine: line)
    }

    private func addMarkToMinimap(ofType type: iTermIntervalTreeObjectType, onLine line: Int) {
        DLog("Add at \(line)")
        iTermGCD.assertMainQueueSafe()
        guard PTYSessionMarksMinimapPolicy.shouldUpdateMarks(
            showLocationsInScrollbar: iTermAdvancedSettingsModel.showLocationsInScrollbar(),
            showMarksInScrollbar: iTermAdvancedSettingsModel.showMarksInScrollbar()
        ) else {
            return
        }
        if PTYSessionMarksMinimapPolicy.tracksObjectType(type) {
            session?.view?.marksMinimap?.addObject(ofType: Int(type.rawValue), onLine: line)
        }
    }

    @objc(intervalTreeDidHideObject:ofType:onLine:)
    func intervalTreeDidHide(_ object: IntervalTreeImmutableObject,
                             of type: iTermIntervalTreeObjectType,
                             onLine line: Int) {
        DLog("Hide \(object)")
        if let portholeMark = PortholeMark.cast(from: object),
           let porthole = PortholeRegistry.instance[portholeMark.uniqueIdentifier] {
            session?.textview?.hidePorthole(porthole)
        }
        removeMarkFromMinimap(ofType: type, onLine: line)
    }

    @objc(intervalTreeDidUnhideObject:ofType:onLine:)
    func intervalTreeDidUnhideObject(_ object: IntervalTreeImmutableObject,
                                     of type: iTermIntervalTreeObjectType,
                                     onLine line: Int) {
        DLog("Unhide \(object)")
        if let portholeMark = PortholeMark.cast(from: object),
           let porthole = PortholeRegistry.instance[portholeMark.uniqueIdentifier] {
            session?.textview?.unhidePorthole(porthole)
        }
        addMarkToMinimap(ofType: type, onLine: line)
    }

    @objc(intervalTreeDidPermanentlyRemoveHiddenObject:ofType:)
    func intervalTreeDidPermanentlyRemoveHiddenObject(_ object: IntervalTreeImmutableObject,
                                                      of type: iTermIntervalTreeObjectType) {
        DLog("Permanently remove hidden \(object)")
        if type == .porthole, let portholeMark = PortholeMark.cast(from: object) {
            session?.textview?.forciblyRemovePorthole(uniqueIdentifier: portholeMark.uniqueIdentifier)
        }
    }

    @objc(intervalTreeDidRemoveObjectOfType:onLine:)
    func intervalTreeDidRemoveObject(of type: iTermIntervalTreeObjectType, onLine line: Int) {
        DLog("Remove at \(line)")
        if type == .porthole {
            session?.textview?.setNeedsPrunePortholes(true)
        }
        removeMarkFromMinimap(ofType: type, onLine: line)
    }

    private func removeMarkFromMinimap(ofType type: iTermIntervalTreeObjectType, onLine line: Int) {
        guard PTYSessionMarksMinimapPolicy.shouldUpdateMarks(
            showLocationsInScrollbar: iTermAdvancedSettingsModel.showLocationsInScrollbar(),
            showMarksInScrollbar: iTermAdvancedSettingsModel.showMarksInScrollbar()
        ) else {
            return
        }
        if PTYSessionMarksMinimapPolicy.tracksObjectType(type) {
            session?.view?.marksMinimap?.removeObject(ofType: Int(type.rawValue), fromLine: line)
        }
    }

    @objc func intervalTreeVisibleRangeDidChange() {
        iTermGCD.assertMainQueueSafe()
        updateMarksMinimapRangeOfVisibleLines()
    }

    @objc(intervalTreeDidMoveObjects:)
    func intervalTreeDidMove(_ objects: [IntervalTreeImmutableObject]) {
        session?.textview?.updatePortholeFrames()
    }

    @objc func updateMarksMinimapRangeOfVisibleLines() {
        guard let session,
              iTermAdvancedSettingsModel.showLocationsInScrollbar() else {
            return
        }
        session.view?.marksMinimap?.setFirstVisibleLine(
            Int(session.screen.totalScrollbackOverflow()),
            numberOfVisibleLines: Int(session.screen.numberOfLines())
        )
    }

    // MARK: - FilterDestination

    @objc func discardPendingFilterUpdates() {
        DLog("\(String(describing: session)): Discarding \(filterUpdateQueue.count) pending filter updates")
        filterUpdateQueue.discardAll()
    }

    @objc(filterDestinationAppendScreenCharArray:)
    func append(_ sca: ScreenCharArray) {
        let wasEmpty = filterUpdateQueue.enqueueAppend(sca)
        DLog("\(String(describing: session)): filterDestinationAppendScreenCharArray: Add <\(sca)> to pending filter update which now has \(filterUpdateQueue.count) entries")
        if wasEmpty {
            scheduleFilterUpdate()
        }
    }

    private func scheduleFilterUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let session = self.session else { return }
            DLog("\(session): scheduleFilterUpdate: Draining \(self.filterUpdateQueue.count) pending filter updates")
            session.screen.performBlock(joinedThreads: { _, mutableState, _ in
                let items = self.filterUpdateQueue.drain()
                for item in items {
                    switch item {
                    case .append(let sca):
                        DLog("\(session): Appending filter result line: \(sca)")
                        mutableState.appendScreenChars(
                            sca.line,
                            length: sca.length,
                            externalAttributeIndex: sca.eaIndex,
                            continuation: sca.continuation,
                            rtlFound: sca.metadata.rtlFound.boolValue,
                            lineAttribute: sca.metadata.lineAttribute
                        )
                    case .removeLastLine:
                        DLog("\(session): Removing last line from filter results")
                        mutableState.removeLastLine()
                    }
                }
            })
        }
    }

    @objc(filterDestinationRemoveLastLine)
    func removeLastLine() {
        DLog("\(String(describing: session)): filterDestinationRemoveLastLine")
        filterUpdateQueue.enqueueRemoveLastLine()
        scheduleFilterUpdate()
    }

    // MARK: - TailFindControllerDelegate

    func tailFindControllerBelongsToVisibleTab() -> Bool {
        return session?.delegate?.sessionBelongsToVisibleTab() ?? false
    }

    func tailFindControllerFindOnPageHelper() -> iTermFindOnPageHelper {
        it_assert(session?.textview?.findOnPageHelper != nil, "findOnPageHelper required for tail find")
        return session!.textview!.findOnPageHelper
    }

    func tailFindControllerRemoveSearchResults(inRange rangeSearched: VT100GridAbsCoordRange) {
        session?.textview?.removeSearchResults(in: rangeSearched)
    }

    func tailFindControllerAdd(searchResult: SearchResult) {
        session?.textview?.add(searchResult)
    }

    func tailFindControllerDoesNeedDisplay() {
        session?.textview?.requestDelegateRedraw()
    }

    func tailFindControllerDidFinish(atLocation location: LineBufferPosition?) {
        guard let session else { return }
        if let searchEngine = session.screen.searchEngine() {
            searchEngine.lastStartPosition = location ?? searchEngine.lastEndOfBufferPosition
        }
        session.view?.findDriver?.viewController?.countDidChange()
    }

    func tailFindControllerMainSearchEngine() -> iTermSearchEngine {
        it_assert(session?.screen.searchEngine() != nil, "searchEngine required for tail find")
        return session!.screen.searchEngine()!
    }

    func tailFindControllerPositionForTailSearchOfMainSearchEngine() -> LineBufferPosition {
        it_assert(session?.screen != nil, "screen required for tail find")
        return session!.screen.positionForTailSearchOfScreen()
    }

    func tailFindControllerDidBecomeIdle() {
        session?.clearTailFindController()
    }

    // MARK: - Composer Color Updates

    @objc(setNeedsComposerColorUpdate:)
    func setNeedsComposerColorUpdate(_ needed: Bool) {
        if needsComposerColorUpdate && needed {
            return
        }
        needsComposerColorUpdate = needed
        if needed {
            DispatchQueue.main.async { [weak self] in
                self?.updateComposerColors()
            }
        }
    }

    private func updateComposerColors() {
        guard let session, session.textview != nil else {
            return
        }
        setNeedsComposerColorUpdate(false)
        guard session.haveAutoComposer(),
              let userData = session.composerManager.prefixUserData as? [AnyHashable: Any],
              let promptText = userData[PTYSessionComposerPrefixUserDataKeyPrompt] as? [ScreenCharArray] else {
            return
        }
        let prompt = session.kernedAttributedString(forScreenChars: promptText,
                                                    elideDefaultBackgroundColor: true)
        session.composerManager.setPrefix(prompt, userData: session.composerManager.prefixUserData)
    }
}
