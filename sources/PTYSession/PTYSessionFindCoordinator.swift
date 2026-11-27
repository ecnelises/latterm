//
//  PTYSessionFindCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m (Wave 5) to isolate iTermFindDriverDelegate
//  search/filter orchestration and async filter lifecycle management.
//

import Cocoa

enum PTYSessionFilterPolicy {
    static func shouldSkipUpdate(newFilter: String?,
                                 currentFilter: String?,
                                 currentMode: iTermFindMode,
                                 requestedMode: iTermFindMode,
                                 hasActiveAsyncFilter: Bool) -> Bool {
        guard let newFilter, let currentFilter, hasActiveAsyncFilter else {
            return false
        }
        return newFilter == currentFilter && currentMode == requestedMode
    }

    static func shouldRefine(existingMode: iTermFindMode,
                             requestedMode: iTermFindMode,
                             isRegex: Bool) -> Bool {
        return existingMode == requestedMode && !isRegex
    }
}

@objc final class PTYSessionFindCoordinator: NSObject, iTermFindDriverDelegate {
    private weak var session: PTYSession?
    @objc private(set) var currentFilter: String?
    @objc var asyncFilter: AsyncFilter?

    @objc var hasActiveAsyncFilter: Bool {
        return asyncFilter != nil
    }

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    @objc func cancelAsyncFilter() {
        asyncFilter?.cancel()
    }

    @objc func clearAsyncFilterSubscription() {
        guard let filterToClear = asyncFilter else {
            return
        }
        session?.live?.removeContentSubscriber(filterToClear)
        filterToClear.cancel()
        asyncFilter = nil
    }

    @objc func searchNext() {
        guard let session else { return }
        session.view?.createFindDriverIfNeeded()
        session.view?.findDriver?.searchNext()
        session.tailFindController().beginOneShotTailFind()
    }

    @objc func searchPrevious() {
        guard let session else { return }
        session.view?.createFindDriverIfNeeded()
        session.view?.findDriver?.searchPrevious()
        session.tailFindController().beginOneShotTailFind()
    }

    @objc(setFilter:)
    func setFilter(_ newFilter: String?) {
        guard let session else { return }
        session.resetMode()
        DLog("\(session): setFilter:\(newFilter ?? "nil")")

        session.view?.updateFindDriver()
        session.view?.createFindDriverIfNeeded()
        guard let findDriver = session.view?.findDriver else {
            DLog("\(session): ERROR: No find driver available for filtering.")
            return
        }

        if let existingAsyncFilter = asyncFilter,
           PTYSessionFilterPolicy.shouldSkipUpdate(newFilter: newFilter,
                                                   currentFilter: currentFilter,
                                                   currentMode: existingAsyncFilter.mode,
                                                   requestedMode: findDriver.filterMode,
                                                   hasActiveAsyncFilter: true) {
            DLog("\(session): Filter unchanged, returning early")
            return
        }

        guard let newFilter else {
            if let existingAsyncFilter = asyncFilter {
                DLog("Nuke existing filter \(existingAsyncFilter)")
                existingAsyncFilter.cancel()
                session.live?.removeContentSubscriber(existingAsyncFilter)
                currentFilter = nil
                asyncFilter = nil
            }
            return
        }

        guard let sourceSession = session.live else {
            it_assert(false, "Expected liveSession when applying filter")
            return
        }
        let source = sourceSession.screen

        if let previous = asyncFilter {
            previous.cancel()
            sourceSession.removeContentSubscriber(previous)
        }
        let replacingFilter = (currentFilter != nil)
        currentFilter = newFilter

        var refining = asyncFilter
        let isRegex = iTermFilterModeIsRegularExpression(findDriver.filterMode)
        if let existing = refining,
           !PTYSessionFilterPolicy.shouldRefine(existingMode: existing.mode,
                                                requestedMode: findDriver.filterMode,
                                                isRegex: isRegex) {
            refining = nil
        }

        let absLineRange = sourceSession.textview?.findOnPageHelper.absLineRange ?? NSRange(location: 0, length: 0)
        let newAsyncFilter = source.newAsyncFilter(
            with: session.swiftState.displayCoordinator,
            query: newFilter,
            mode: findDriver.filterMode,
            refining: refining,
            absLineRange: absLineRange,
            progress: { [weak self] progress in
                self?.setFilterProgress(progress)
            }
        )
        asyncFilter = newAsyncFilter
        sourceSession.addContentSubscriber(newAsyncFilter)

        if replacingFilter {
            session.swiftState.displayCoordinator.discardPendingFilterUpdates()
            session.screen.performBlock(joinedThreads: { _, mutableState, _ in
                mutableState.clearBufferWithoutTriggersSavingPrompt(false)
            })
        }
        newAsyncFilter.start()
    }

    @objc(setFilterProgress:)
    func setFilterProgress(_ progress: Double) {
        session?.view?.findDriver?.setFilterProgress(progress)
        session?.statusBarViewController?.filterViewController.setFilterProgress(progress)
    }

    @objc func stopFiltering() {
        setFilterProgress(0)
        clearAsyncFilterSubscription()
        if session?.statusBarViewController?.temporaryRightComponent is StatusBarFilterComponent {
            session?.statusBarViewController?.temporaryRightComponent = nil
        }
        guard let session else { return }
        session.delegate?.session(session, setFilter: nil)
        if let responder = session.mainResponder {
            session.textview?.window?.makeFirstResponder(responder)
        }
    }

    // MARK: - iTermFindDriverDelegate

    @objc func canSearch() -> Bool {
        guard let session else { return false }
        return session.textview != nil && session.delegate?.realParentWindow() != nil
    }

    @objc func resetFindCursor() {
        session?.textview?.resetFindCursor()
    }

    @objc func findInProgress() -> Bool {
        return session?.textview?.findInProgress ?? false
    }

    @objc(continueFind:range:)
    func continueFind(_ progress: UnsafeMutablePointer<Double>?,
                      range rangePtr: NSRangePointer?) -> Bool {
        return session?.textview?.continueFind(progress, range: rangePtr) ?? false
    }

    @objc func growSelectionLeft() -> Bool {
        return session?.textview?.growSelectionLeft() ?? false
    }

    @objc func growSelectionRight() {
        session?.textview?.growSelectionRight()
    }

    @objc func selectedText() -> String? {
        return session?.textview?.selectedText
    }

    @objc func unpaddedSelectedText() -> String? {
        return session?.textview?.selectedText
    }

    @objc func copySelection() {
        session?.textview?.copySelectionAccordingToUserPreferences()
    }

    @objc(pasteString:)
    func paste(_ string: String) {
        session?.paste(string, flags: PTYSessionPasteFlags(rawValue: 0))
    }

    @objc func findViewControllerMakeDocumentFirstResponder() {
        guard let session, let responder = session.mainResponder else { return }
        session.delegate?.realParentWindow()?.window?.makeFirstResponder(responder)
    }

    @objc func findViewControllerClearSearch() {
        session?.textview?.clearHighlights(true)
    }

    @objc(findString:forwardDirection:mode:withOffset:scrollToFirstResult:force:extendResultsAcrossSoftBoundaries:)
    func find(_ aString: String,
              forwardDirection direction: Bool,
              mode: iTermFindMode,
              withOffset offset: Int32,
              scrollToFirstResult: Bool,
              force: Bool,
              extendResultsAcrossSoftBoundaries: Bool) {
        session?.textview?.find(
            aString,
            forwardDirection: direction,
            mode: mode,
            withOffset: offset,
            scrollToFirstResult: scrollToFirstResult,
            force: force,
            extendResultsAcrossSoftBoundaries: extendResultsAcrossSoftBoundaries
        )
    }

    @objc(findViewControllerVisibilityDidChange:)
    func findViewControllerVisibilityDidChange(_ sender: iTermFindViewController) {
        session?.delegate?.sessionUpdateMetalAllowed()
        if sender.driver.isVisible {
            return
        }
        if session?.view?.findViewHasKeyboardFocus == true {
            session?.view?.findDidHide()
        }
    }

    @objc(findViewControllerDidCeaseToBeMandatory:)
    func findViewControllerDidCease(toBeMandatory sender: iTermFindViewController) {
        session?.view?.findDidHide()
    }

    @objc func findDriverBottomUpPerformFindPanelAction(_ sender: Any) {
        session?.textview?.performFindPanelAction(sender)
    }

    @objc(findDriverBottomUpValidateMenuItem:)
    func findDriverBottomUpValidate(_ menuItem: NSMenuItem) -> Bool {
        return session?.textview?.validateMenuItem(menuItem) ?? false
    }

    @objc func findDriverSearchEngine() -> iTermSearchEngine? {
        return session?.screen.searchEngine()
    }

    @objc(findDriverFilterVisibilityDidChange:)
    func findDriverFilterVisibilityDidChange(_ visible: Bool) {
        guard !visible, let session else { return }
        clearAsyncFilterSubscription()
        let liveSession = session.live
        session.delegate?.session(session, setFilter: nil)
        liveSession?.view?.findDriver?.close()
    }

    @objc(findDriverSetFilter:withSideEffects:)
    func findDriverSetFilter(_ filter: String?, withSideEffects: Bool) {
        guard withSideEffects, let session else { return }
        session.delegate?.session(session, setFilter: filter)
    }

    @objc func findDriverInvalidateFrame() {
        session?.view?.findDriverInvalidateFrame()
    }

    @objc func findDriverNumberOfSearchResults() -> Int {
        return session?.textview?.findOnPageHelper.numberOfSearchResults ?? 0
    }

    @objc func findDriverCurrentIndex() -> Int {
        return session?.textview?.findOnPageHelper.currentIndex ?? 0
    }
}
