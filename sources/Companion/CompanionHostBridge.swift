//
//  CompanionHostBridge.swift
//  iTerm2
//
//  The server end of the companion protocol. Given an established (Noise-
//  encrypted) transport, it serves terminal session discovery, rendering,
//  streaming, keyboard, touch, selection, and resize requests.
//
//  Everything here runs on the main actor because iTermController and terminal
//  views require it. All outbound traffic is enqueued
//  synchronously (in main-actor order) onto a single outbox stream drained by
//  one task, so frames reach the transport in exactly the order they were
//  produced: replies never interleave with each other, and streamed .append
//  deltas cannot arrive scrambled.
//

import Foundation
import QuartzCore
import CompanionProtocol
import CompanionNoise

@MainActor
final class CompanionHostBridge {
    let link: CompanionLink
    private var receiveTask: Task<Void, Never>?
    private var outbox: CompanionPriorityOutbox<HostEnvelope>?

    /// One live video stream and the main-thread timer driving it.
    private final class StreamContext {
        let streamer: CompanionSessionStreamer
        let guid: String
        let timer: Timer
        var lastChange: TimeInterval
        /// Last selection pushed to the phone, to detect changes (mac-side or phone)
        /// and push a selectionRange so it can reload affected history tiles.
        var lastSentSelectionRange: CompanionSelectionRange?
        /// The stream generation last observed while driving. A genuine generation
        /// bump (resize/reflow/font change) makes the phone discard its selection, so
        /// when this advances the selection is re-pushed even if its value is unchanged.
        var lastConfigGeneration: UInt32 = 0
        /// The fixed endpoint of an in-progress character-mode drag (raw, inclusive),
        /// set at .begin and used to rebuild the range by document order on each move.
        var selectionAnchor: VT100GridAbsCoord?
        /// The half-open range last applied for the drag, so an unchanged move is a
        /// no-op (no re-begin, no selectionRange flood).
        var lastAppliedCharRange: (start: VT100GridAbsCoord, end: VT100GridAbsCoord)?
        init(streamer: CompanionSessionStreamer, guid: String, timer: Timer, lastChange: TimeInterval) {
            self.streamer = streamer
            self.guid = guid
            self.timer = timer
            self.lastChange = lastChange
        }
    }
    private var streams: [UInt32: StreamContext] = [:]
    private var streamIDForGuid: [String: UInt32] = [:]
    private var nextStreamID: UInt32 = 1

    /// Called once the transport closes remotely, so the owner can drop this
    /// bridge. A user-initiated stop() does not fire it. Carries the terminating
    /// transport error (e.g. `.quotaExceeded`) so the owner can distinguish a relay
    /// quota teardown from ordinary loss and back off; nil when unavailable.
    var onClose: (@MainActor (Error?) -> Void)?

    /// Called when the phone announces it is unpairing.
    var onPeerUnpaired: (@MainActor () -> Void)?

    /// Called when the peer's `.hello` shows the apps are version-incompatible, so
    /// the mac can show an upgrade alert. The verdict is from the MAC's side:
    /// .peerMustUpgrade -> upgrade the phone app; .selfMustUpgrade -> upgrade
    /// iTerm2. Not called when compatible.
    var onVersionIncompatible: (@MainActor (_ verdict: CompanionProtocolVersion.Compatibility) -> Void)?
    init(link: CompanionLink) {
        self.link = link
    }

    convenience init(transport: MessageTransport) {
        self.init(link: CompanionLink.makeForProduction(transport: transport))
    }

    func start() {
        outbox = link.outbox
        receiveTask = Task { [weak self, link] in
            for await event in link.events {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .envelope(let envelope, let handledByLink):
                    if !handledByLink { self.handle(envelope) }
                case .helloCompleted:
                    break
                case .versionIncompatible(let verdict):
                    self.onVersionIncompatible?(verdict)
                case .closed(let error):
                    self.teardownStreams()
                    self.onClose?(error)
                }
            }
        }
        link.start()
    }

    func announceUnpairedAndStop() async {
        onClose = nil
        link.stopStoringRoomSecret()
        endAllStreams(reason: .sessionClosed)
        outbox = nil
        await link.sendFarewellAndClose()
        receiveTask?.cancel()
        receiveTask = nil
    }

    func stop() {
        onClose = nil
        receiveTask?.cancel()
        receiveTask = nil
        teardownStreams()
        link.close()
    }

    private func teardownStreams() {
        endAllStreams(reason: .sessionClosed)
        outbox = nil
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        switch envelope.payload {
        case .unsupported:
            send(.error(CompanionError(code: .badRequest,
                                       message: "Unsupported request; app upgrade required")),
                 requestID: requestID)
        case .hello, .ping, .relayRoomSecret, .streamAck:
            break
        case .listSessions:
            send(.sessions(CompanionSessionLister.sessions()), requestID: requestID)
        case .fetchSessionScreenInfo(let sessionGuid):
            handleFetchSessionScreenInfo(guid: sessionGuid, requestID: requestID)
        case .fetchSessionContent(let sessionGuid, let firstLine, let lineCount):
            handleFetchSessionContent(guid: sessionGuid,
                                      firstLine: firstLine,
                                      lineCount: lineCount,
                                      requestID: requestID)
        case .fetchHistoryTile(let streamID, let firstAbsLine, let lineCount, let generationId):
            handleFetchHistoryTile(streamID: streamID,
                                   firstAbsLine: firstAbsLine,
                                   lineCount: lineCount,
                                   generationId: generationId,
                                   requestID: requestID)
        case .fetchSessionTree:
            send(.sessionTree(CompanionSessionLister.tree()), requestID: requestID)
        case .unpairing:
            onPeerUnpaired?()
        case .startSessionStream(let sessionGuid, let params):
            handleStartSessionStream(guid: sessionGuid, params: params, requestID: requestID)
        case .stopSessionStream(let streamID):
            endStream(streamID, reason: .stoppedByClient)
        case .requestKeyframe(let streamID):
            streams[streamID]?.streamer.requestKeyframe()
        case .updateStreamParams(let streamID, let params):
            streams[streamID]?.streamer.updateFrameRateCap(params.maxFrameRate)
        case .reportScrollWheel(let streamID, let up, let lines):
            handleReportScrollWheel(streamID: streamID, up: up, lines: lines)
        case .selectionGesture(let streamID, let phase, let mode, let point):
            handleSelectionGesture(streamID: streamID, phase: phase, mode: mode, point: point)
        case .clearSelection(let streamID):
            handleClearSelection(streamID: streamID)
        case .copySelection(let sessionGuid):
            handleCopySelection(guid: sessionGuid, requestID: requestID)
        case .selectAllInStream(let streamID):
            handleSelectAll(streamID: streamID)
        case .pasteText(let sessionGuid, let text):
            iTermController.sharedInstance().anySession(forReference: sessionGuid)?.paste(text, flags: [])
        case .sendKey(let sessionGuid, let event):
            handleSendKey(guid: sessionGuid, event: event)
        case .resizeSession(let sessionGuid, let columns, let rows):
            handleResizeSession(guid: sessionGuid, columns: columns, rows: rows)
        }
    }

    /// Resize a session's grid on behalf of the phone.
    private func handleResizeSession(guid: String, columns: Int, rows: Int) {
        guard let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            return
        }
        // Re-validate server-side rather than trusting the phone's (advisory, and
        // possibly stale) UI gate: reallySetCellSize: applies none of the guards
        // screenSetSize: does, and the delegate only re-checks full screen -- not the
        // width lock. This single check covers full screen, width-locked, and
        // non-resizable window types authoritatively, so a width-locked session
        // cannot be resized from the phone even if its button was left enabled.
        guard session.companionSessionCanResizeWindow() else {
            return
        }
        let clampedColumns = Int32(min(max(columns, 1), 4096))
        let clampedRows = Int32(min(max(rows, 1), 4096))
        // reallySetCellSize: reads proposedSize.width as the row count and
        // proposedSize.height as the column count (see PTYSession.h).
        session.reallySetCellSize(VT100GridSize(width: clampedRows, height: clampedColumns))
    }

    /// Inject one key press from the phone's on-screen keyboard. Ordinary typed text
    /// (no modifier) is written as literal input; a single modified character or a
    /// named special key is synthesized into a key event and run through the
    /// session's own key mapper so control/option encodings honor the profile and
    /// special keys honor the terminal's cursor/keypad/key-reporting modes.
    private func handleSendKey(guid: String, event: CompanionKeyEvent) {
        guard let session = iTermController.sharedInstance().anySession(forReference: guid) else {
            DLog("sendKey: no session for guid \(guid); dropping key \(event.key)")
            return
        }
        // Route every key - including ordinary typed text, one event per character -
        // through the session's key mapper rather than writing text literally. The
        // mapper is the only thing that knows the current key-reporting mode, so a
        // full-screen app that turned on a CSI-u mode (report all keys as escape
        // codes, disambiguate escape, ...) sees correctly-encoded keys.
        //
        // Exception: a character with no single-keystroke mapping on the mac's layout
        // (accented letter, emoji, dead-key result) synthesizes to a key code the CSI-u
        // mapper would mis-derive; those are passed as literalText so the mac writes the
        // correct character verbatim - but still behind the same accept-gate and
        // broadcast suppression as the mapped keys (see CompanionKeyEvent.literalFallback).
        for keyEvent in event.makeKeyDownEvents() {
            session.injectSynthesizedKeyEvent(keyEvent,
                                              literalText: CompanionKeyEvent.literalFallback(for: keyEvent))
        }
    }

    // MARK: Live streaming

    /// Drive the session's real iTermSelection from a phone gesture. The resulting
    /// highlight is rendered into the stream (we mark the stream dirty so a frame
    /// goes out promptly). Runs on the main actor, where PTYTextView is safe.
    private func handleSelectionGesture(streamID: UInt32,
                                        phase: CompanionSelectionPhase,
                                        mode: CompanionSelectionMode,
                                        point: CompanionSelectionPoint) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        // Clamp the absolute line to the available buffer so a hostile or stale peer
        // cannot point iTermSelection at a line outside [firstAbs, firstAbs+lines).
        // The column is clamped downstream (inclusiveCharacterRange / iTermSelection).
        let clampedAbsLine = Self.clampAbsLine(point.absLine,
                                               firstAbs: session.screen.totalScrollbackOverflow(),
                                               lineCount: Int64(session.screen.numberOfLines()))
        let coord = VT100GridAbsCoordMake(Int32(clamping: point.column), clampedAbsLine)
        // Word/line/smart snapping queries the data source, which a buried session
        // detaches; re-attach for the operation, mirroring the frame source.
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }

        let changed: Bool
        if mode == .character {
            let gridWidth = Int(textview.dataSource?.width() ?? 0)
            changed = applyCharacterSelection(context: context, textview: textview,
                                              phase: phase, coord: coord, gridWidth: gridWidth)
        } else {
            // Word/line/smart selections snap to whole-token boundaries, so there is
            // no single-cell exclusivity to reconcile: drive iTermSelection's live
            // selection directly. But the phone's column is VISUAL, and these modes
            // interpret the coordinate as LOGICAL (unlike character mode, whose live
            // range is visual), so convert first (a no-op unless the line is
            // bidi-reordered), matching the Mac mouse handler. Without this, a
            // double-tap or smart select on a right-to-left line snaps to the wrong
            // token.
            let relLine = clampedAbsLine - session.screen.totalScrollbackOverflow()
            let bidi = (relLine >= 0 && relLine < Int64(session.screen.numberOfLines()))
                ? textview.dataSource?.bidiInfo(forLine: Int32(clamping: relLine)) : nil
            let logicalCoord = VT100GridAbsCoordMake(Self.logicalColumn(forVisualColumn: coord.x, bidi: bidi),
                                                     clampedAbsLine)
            var moved = true
            switch phase {
            case .begin:
                textview.selection?.begin(at: logicalCoord, mode: mode.iTermSelectionMode,
                                          resume: false, append: false)
            case .move:
                moved = textview.selection?.moveEndpoint(to: logicalCoord) ?? false
            case .end:
                moved = textview.selection?.moveEndpoint(to: logicalCoord) ?? false
                textview.selection?.endLive()
            }
            changed = (phase != .move) || moved
        }
        // Only react when the selection actually changed: a no-op move neither
        // alters the rendered frame nor needs a selectionRange reply, and emitting
        // either just adds to the flood that backs up the link.
        if changed {
            context.streamer.screenDidChange()
            sendSelectionRange(streamID: streamID, textview: textview)
        }
    }

    /// Apply a character-mode selection from the phone. The phone sends raw inclusive
    /// coordinates (the anchor at .begin, the live point on move/end); the range is
    /// rebuilt by document order so exclusivity is correct in every drag direction.
    /// Returns whether the applied range changed (so a no-op move is dropped).
    private func applyCharacterSelection(context: StreamContext, textview: PTYTextView,
                                         phase: CompanionSelectionPhase,
                                         coord: VT100GridAbsCoord, gridWidth: Int) -> Bool {
        let anchor: VT100GridAbsCoord
        switch phase {
        case .begin:
            context.selectionAnchor = coord
            context.lastAppliedCharRange = nil
            anchor = coord
        case .move, .end:
            anchor = context.selectionAnchor ?? coord
        }
        let range = Self.inclusiveCharacterRange(anchor: anchor, live: coord, gridWidth: gridWidth)
        var changed = true
        if let last = context.lastAppliedCharRange,
           last.start.x == range.start.x, last.start.y == range.start.y,
           last.end.x == range.end.x, last.end.y == range.end.y {
            changed = false
        } else {
            textview.selection?.begin(at: range.start, mode: .kiTermSelectionModeCharacter,
                                      resume: false, append: false)
            _ = textview.selection?.moveEndpoint(to: range.end)
            context.lastAppliedCharRange = range
        }
        if phase == .end {
            textview.selection?.endLive()
            context.selectionAnchor = nil
            context.lastAppliedCharRange = nil
            changed = true   // always broadcast the finalized selection
        } else if phase == .begin {
            changed = true   // a fresh begin always establishes a selection
        }
        return changed
    }

    /// Forget an in-progress character-drag's anchor and last-applied range. Call
    /// whenever the selection is cleared or replaced OUTSIDE the gesture path, so a
    /// later phone .move that happens to recompute the same range is not dropped as a
    /// no-op (which would make the drag look dead until the finger crosses a cell).
    private func resetSelectionDragState(_ context: StreamContext) {
        context.selectionAnchor = nil
        context.lastAppliedCharRange = nil
    }

    private func handleSelectAll(streamID: UInt32) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }
        textview.selectAll(nil)
        resetSelectionDragState(context)
        context.streamer.screenDidChange()
        sendSelectionRange(streamID: streamID, textview: textview)
    }

    private func handleClearSelection(streamID: UInt32) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            return
        }
        textview.selection?.clear()
        resetSelectionDragState(context)
        context.streamer.screenDidChange()
        sendSelectionRange(streamID: streamID, textview: textview)
    }

    /// Report the session's current selection span (or nil) so the phone can draw
    /// and move handles.
    /// The phone works entirely in VISUAL columns (it renders a streamed image and
    /// touches at pixel positions), but iTermSelection is LOGICAL. These convert a
    /// single column for one line. Identity when there is no bidi info or the column
    /// is outside the mapped cells, so left-to-right text is untouched.
    nonisolated static func logicalColumn(forVisualColumn visualX: Int32,
                                          bidi: BidiDisplayInfoObjc?) -> Int32 {
        return BidiDisplayInfoObjc.logicalColumn(forVisualColumn: visualX, info: bidi)
    }

    nonisolated static func visualColumn(forLogicalColumn logicalX: Int32,
                                         bidi: BidiDisplayInfoObjc?) -> Int32 {
        return BidiDisplayInfoObjc.visualColumn(forLogicalColumn: logicalX, info: bidi)
    }

    /// Visual [min, max] columns for the cells that `subs` select on `line`. iTermSelection
    /// stores a selection running through the end of a line as (startX, line, 0, line+1),
    /// so a sub whose end wrapped to the next line must sweep to the grid width, not to its
    /// raw exclusive end.x (which is 0 and would make the loop select nothing and the phone
    /// show no selection). Returns nil only when no cell on the line is selected.
    nonisolated static func visualColumnSpan(forSelectedSubs subs: [iTermSubSelection],
                                             onLine line: Int64,
                                             gridWidth: Int32,
                                             bidi: BidiDisplayInfoObjc?) -> (min: Int32, max: Int32)? {
        var vmin = Int32.max
        var vmax = Int32.min
        for sub in subs where sub.absRange.coordRange.start.y == line {
            let cr = sub.absRange.coordRange
            let rawStop = (cr.end.y == line) ? cr.end.x : gridWidth
            // On a reordered line, logical columns >= numberOfCells (the trailing
            // padding of a select-through-EOL range) are not in the LUT and map to
            // identity (large) visual columns, which would inflate the max even
            // though they render on the visual left. Bound the sweep to the reordered
            // cells for the bidi case.
            let stop = bidi.map { min(rawStop, $0.numberOfCells) } ?? rawStop
            var logical = cr.start.x
            while logical < stop {
                let v = visualColumn(forLogicalColumn: logical, bidi: bidi)
                vmin = min(vmin, v)
                vmax = max(vmax, v)
                logical += 1
            }
        }
        return vmin <= vmax ? (min: vmin, max: vmax) : nil
    }

    /// iTermSelection's end x is EXCLUSIVE (one past the last selected cell; select
    /// all yields end.x == gridWidth). The phone treats the wire end as the
    /// inclusive last cell, so convert here. An exclusive end at column 0 means the
    /// previous line is selected through its last cell.
    nonisolated static func inclusiveSelectionEnd(exclusiveColumn column: Int, absLine: Int64,
                                                  gridWidth: Int) -> (column: Int, absLine: Int64) {
        if column > 0 { return (column - 1, absLine) }
        return (max(0, gridWidth - 1), absLine - 1)
    }

    /// Clamp an absolute line to the buffer's available range [firstAbs,
    /// firstAbs+lineCount). An empty buffer (lineCount <= 0) clamps to firstAbs.
    nonisolated static func clampAbsLine(_ absLine: Int64, firstAbs: Int64, lineCount: Int64) -> Int64 {
        guard lineCount > 0 else { return firstAbs }
        return min(max(absLine, firstAbs), firstAbs + lineCount - 1)
    }

    struct SelectionPushDecision: Equatable {
        /// The selection changed from a non-gesture source, so an in-progress drag's
        /// state is stale and must be forgotten.
        var resetDragState: Bool
        /// The current selection should be (re)sent to the phone.
        var push: Bool
    }

    /// Decide how driveStream reacts to the current selection. A value change means it
    /// came from elsewhere (a phone gesture pushes inline and updates lastSent), so
    /// reset the drag and push. A generation bump forces a re-push of the SAME value
    /// (the phone discarded it) but must NOT reset the drag, so a resize mid-drag
    /// keeps the anchor.
    nonisolated static func selectionPushDecision(current: CompanionSelectionRange?,
                                                  lastSent: CompanionSelectionRange?,
                                                  generationBumped: Bool) -> SelectionPushDecision {
        let valueChanged = (current != lastSent)
        return SelectionPushDecision(resetDragState: valueChanged,
                                     push: valueChanged || generationBumped)
    }

    /// Given the two inclusive endpoints of a character-mode selection (the fixed
    /// anchor and the live point, in either order), return the half-open range
    /// iTermSelection needs: start at the earlier cell (inclusive), end one past the
    /// later cell (exclusive). Ordering the coordinates HERE, before iTermSelection's
    /// own unflip, is what makes the exclusive +1 land on the endpoint that actually
    /// ends up in the END role, so backward and endpoint-crossing drags include the
    /// cell under the finger instead of dropping or collapsing it.
    nonisolated static func inclusiveCharacterRange(anchor: VT100GridAbsCoord,
                                                    live: VT100GridAbsCoord,
                                                    gridWidth: Int)
    -> (start: VT100GridAbsCoord, end: VT100GridAbsCoord) {
        // Clamp columns before the exclusive +1 so a hostile peer sending a column
        // near Int32.max cannot wrap to Int32.min and hand iTermSelection a nonsense
        // coordinate. With a known width the last valid inclusive column is width-1
        // (so the exclusive end is at most width); without one, cap short of the
        // Int32 max headroom for the +1.
        let maxColumn: Int32 = gridWidth > 0 ? Int32(clamping: gridWidth - 1) : Int32.max - 1
        func clampColumn(_ c: VT100GridAbsCoord) -> VT100GridAbsCoord {
            VT100GridAbsCoordMake(min(max(c.x, 0), maxColumn), c.y)
        }
        let a = clampColumn(anchor)
        let l = clampColumn(live)
        let anchorFirst = a.y < l.y || (a.y == l.y && a.x <= l.x)
        let lo = anchorFirst ? a : l
        let hi = anchorFirst ? l : a
        return (lo, VT100GridAbsCoordMake(hi.x &+ 1, hi.y))
    }

    private func currentSelectionRange(_ textview: PTYTextView) -> CompanionSelectionRange? {
        guard let selection = textview.selection, selection.hasSelection else { return nil }
        // logicalSubSelections (not spanningAbsRange, which folds in the raw live
        // range via allSubSelections) so an in-progress bidi character drag is
        // decomposed to LOGICAL runs before we convert to visual. Otherwise mid-drag
        // the live range already holds visual columns and we would map it a second
        // time, so the handles land on the mirror side until finger-lift.
        let subs = selection.logicalSubSelections
        guard !subs.isEmpty else { return nil }
        let gridWidth = Int(textview.dataSource?.width() ?? 0)
        let overflow = textview.dataSource?.totalScrollbackOverflow() ?? 0
        let numLines = Int64(textview.dataSource?.numberOfLines() ?? 0)
        let bidiFor: (Int64) -> BidiDisplayInfoObjc? = { absLine in
            let rel = absLine - overflow
            guard rel >= 0, rel < numLines else { return nil }
            return textview.dataSource?.bidiInfo(forLine: Int32(clamping: rel))
        }

        // Document-order bounding endpoints over the logical subselections.
        var startCoord = subs[0].absRange.coordRange.start
        var endCoord = subs[0].absRange.coordRange.end
        for sub in subs {
            let cr = sub.absRange.coordRange
            if cr.start.y < startCoord.y || (cr.start.y == startCoord.y && cr.start.x < startCoord.x) {
                startCoord = cr.start
            }
            if cr.end.y > endCoord.y || (cr.end.y == endCoord.y && cr.end.x > endCoord.x) {
                endCoord = cr.end
            }
        }
        let end = Self.inclusiveSelectionEnd(exclusiveColumn: Int(endCoord.x), absLine: endCoord.y,
                                             gridWidth: gridWidth)

        if startCoord.y == end.absLine {
            // Single line: take the visual min/max over the ACTUALLY-selected logical
            // cells. One visual sweep is contiguous in visual space, so this is exact.
            // Using the bounding [start, end] would include unselected cells sitting
            // between the logical runs of one sweep (RTL text with an embedded LTR
            // number), and converting only the two endpoints would emit a backwards
            // pair on an RTL line, where visualForLogical is monotonically decreasing.
            guard let span = Self.visualColumnSpan(forSelectedSubs: subs,
                                                   onLine: startCoord.y,
                                                   gridWidth: Int32(clamping: gridWidth),
                                                   bidi: bidiFor(startCoord.y)) else {
                return nil
            }
            return CompanionSelectionRange(
                start: CompanionSelectionPoint(absLine: startCoord.y, column: Int(span.min)),
                end: CompanionSelectionPoint(absLine: end.absLine, column: Int(span.max)))
        }
        // Multi-line: a two-point range cannot bound bidi-reordered cells across
        // lines (same limitation as accessibility bounds-for-range), so convert each
        // endpoint on its own line as a best effort.
        let startVisual = Self.visualColumn(forLogicalColumn: startCoord.x, bidi: bidiFor(startCoord.y))
        let endVisual = Self.visualColumn(forLogicalColumn: Int32(clamping: end.column),
                                          bidi: bidiFor(end.absLine))
        return CompanionSelectionRange(
            start: CompanionSelectionPoint(absLine: startCoord.y, column: Int(startVisual)),
            end: CompanionSelectionPoint(absLine: end.absLine, column: Int(endVisual)))
    }

    private func sendSelectionRange(streamID: UInt32, textview: PTYTextView) {
        let range = currentSelectionRange(textview)
        streams[streamID]?.lastSentSelectionRange = range
        RLog("Companion selectionRange push stream=\(streamID) range=\(range.map { "(\($0.start.column),\($0.start.absLine))..(\($0.end.column),\($0.end.absLine))" } ?? "none")")
        // Latest-wins state: ride the coalescing lane so a fast drag's updates
        // collapse to the newest and never starve the media frame that actually
        // shows the selection. Keyed per stream.
        outbox?.enqueueCoalescingControl(HostEnvelope(requestID: nil, payload: .selectionRange(streamID: streamID, range: range)),
                                         key: "selectionRange.\(streamID)")
    }

    private func handleCopySelection(guid: String, requestID: UInt64?) {
        let text = iTermController.sharedInstance().anySession(forReference: guid)?.textview?.selectedText
        send(.selectionText(text: text ?? ""), requestID: requestID)
    }

    /// Translate a phone scroll gesture (over an alt-screen app with mouse reporting)
    /// into terminal mouse-wheel reports. Resolves the session from the stream and
    /// drives the existing PTYSession primitive, which re-checks that reporting is
    /// enabled and caps the notch count, so a stale peer cannot inject bytes when the
    /// user has reporting off.
    private func handleReportScrollWheel(streamID: UInt32, up: Bool, lines: Int) {
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid) else {
            return
        }
        _ = session.reportScrollWheelForOrchestrator(up: up, lines: lines)
    }

    private func handleStartSessionStream(guid: String,
                                          params: CompanionStreamParams,
                                          requestID: UInt64?) {
        guard params.supportedCodecs.contains(.hevc) else {
            send(.error(CompanionError(code: .badRequest,
                                       message: "No supported video codec (HEVC required)")),
                 requestID: requestID)
            return
        }
        guard let session = contentSession(guid: guid, requestID: requestID) else {
            return  // contentSession already replied with an error
        }
        // One stream per session: replace any existing one.
        if let existing = streamIDForGuid[guid] {
            endStream(existing, reason: .superseded)
        }

        let streamID = nextStreamID
        nextStreamID &+= 1
        let frameRate = params.maxFrameRate > 0 ? min(params.maxFrameRate, 60) : 30
        // The phone may cap the bitrate; otherwise the streamer scales it to the
        // rendered resolution (a fixed rate collapses quality as the window grows).
        // A phone-supplied cap is only an upper bound: the resolution-aware target
        // still applies below it.
        let bitrateCeiling = params.maxBitrate.map { max(100_000, min($0, 40_000_000)) }
            ?? CompanionSessionStreamer.defaultBitrateCeiling
        // Emit the highest media-frame version both sides understand: a phone that
        // advertises nothing predates versioned frames and only decodes version 1
        // (no per-frame geometry), while a current phone gets version 2.
        let mediaVersion = UInt8(clamping: min(Int(CompanionMediaFrame.version),
                                               max(1, params.maxMediaFrameVersion ?? 1)))

        // Capture the Sendable outbox continuation, not self: the encoder's
        // callbacks fire on a VideoToolbox thread, and yielding to the stream is
        // thread-safe whereas touching the main-actor bridge would not be.
        let outboxRef = outbox
        let streamer = CompanionSessionStreamer(
            streamID: streamID,
            source: CompanionTerminalFrameSource(session: session),
            maxFrameRate: frameRate,
            bitrateCeiling: bitrateCeiling,
            onConfig: { config in
                outboxRef?.enqueueControl(HostEnvelope(requestID: nil, payload: .streamConfig(config)))
            },
            onMedia: { frame in
                outboxRef?.enqueueMedia(frame.encoded(version: mediaVersion))
            },
            onExtentChanged: { firstAbsLine, totalLines in
                // Latest-wins on the coalescing lane: only the newest window matters.
                outboxRef?.enqueueCoalescingControl(
                    HostEnvelope(requestID: nil,
                                 payload: .streamExtent(streamID: streamID, firstAbsLine: firstAbsLine, totalLines: totalLines)),
                    key: "streamExtent.\(streamID)")
            },
            onDataLimitReached: { [weak self] in
                // Called on the main thread from the streamer's tick.
                self?.endStream(streamID, reason: .dataLimitReached)
            })
        streamer.start()

        // A main-thread timer at the frame-rate cap drives the stream: mark dirty
        // only when the session's content-change timestamp advanced, then tick.
        // The pacer coalesces and enforces the cap, so a static screen emits nothing.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.driveStream(streamID)
            }
        }
        link.streamAcks.register(streamID: streamID) { [weak streamer] pts, depth in
            streamer?.noteAck(ptsMilliseconds: pts, queueDepth: depth)
        }
        streams[streamID] = StreamContext(streamer: streamer, guid: guid, timer: timer,
                                          lastChange: max(session.screenContentsLastChangedAt,
                                                          session.view?.lastRedrawRequestedAt ?? 0))
        streamIDForGuid[guid] = streamID
        RLog("stream \(streamID) START guid=\(guid) fps=\(frameRate)")
        send(.streamStarted(CompanionStreamStarted(streamID: streamID, codec: .hevc)),
             requestID: requestID)
        // Tell the phone about any pre-existing selection on subscribe: the history
        // tiles are rendered with it, so the phone must know which tiles carry the
        // highlight to invalidate them correctly when the selection later changes.
        if let textview = session.textview {
            sendSelectionRange(streamID: streamID, textview: textview)
        }
    }

    private func driveStream(_ streamID: UInt32) {
        guard let context = streams[streamID] else { return }
        guard let session = iTermController.sharedInstance().anySession(forReference: context.guid) else {
            endStream(streamID, reason: .sessionClosed)
            return
        }
        // Emit on any visual change: grid content (screenContentsLastChangedAt,
        // bumped under every renderer) OR a redraw request that does not change
        // content, such as a selection or cursor change (lastRedrawRequestedAt).
        let changedAt = max(session.screenContentsLastChangedAt,
                            session.view?.lastRedrawRequestedAt ?? 0)
        if changedAt > context.lastChange {
            context.lastChange = changedAt
            context.streamer.screenDidChange()
        }
        // A genuine generation bump (resize/reflow/font change) makes the phone
        // discard its selection, so the current range must be re-pushed even if its
        // value is unchanged, to restore the handles the phone dropped.
        let generation = context.streamer.currentGenerationId
        let generationBumped = generation != context.lastConfigGeneration
        context.lastConfigGeneration = generation
        // Detect a selection change from any source (mac-side Cmd-A/drag as well as
        // phone gestures) and push it, so the phone reloads the affected history
        // tiles; the live band already reflects it via the rendered video.
        if let textview = session.textview {
            let current = currentSelectionRange(textview)
            let decision = Self.selectionPushDecision(current: current,
                                                      lastSent: context.lastSentSelectionRange,
                                                      generationBumped: generationBumped)
            // Only forget an in-progress drag when the change came from ELSEWHERE (a
            // real value change: mac Cmd-A, a click). A bump-forced re-push of the
            // SAME value must NOT reset the drag, or a resize mid-drag would wipe the
            // anchor and collapse the selection to the cell under the finger.
            if decision.resetDragState {
                resetSelectionDragState(context)
            }
            if decision.push {
                sendSelectionRange(streamID: streamID, textview: textview)
            }
        }
        context.streamer.tick(nowMilliseconds: UInt64(max(0, CACurrentMediaTime() * 1000)))
    }

    private func endStream(_ streamID: UInt32, reason: CompanionStreamEndReason) {
        guard let context = streams.removeValue(forKey: streamID) else { return }
        link.streamAcks.unregister(streamID: streamID)
        RLog("stream \(streamID) END reason=\(reason)")
        context.timer.invalidate()
        context.streamer.stop()
        if streamIDForGuid[context.guid] == streamID {
            streamIDForGuid[context.guid] = nil
        }
        send(.streamEnded(streamID: streamID, reason: reason), requestID: nil)
    }

    private func endAllStreams(reason: CompanionStreamEndReason) {
        for streamID in Array(streams.keys) {
            endStream(streamID, reason: reason)
        }
    }

    // MARK: Handlers

    /// Resolve a live terminal session for content and streaming requests.
    private func contentSession(guid: String, requestID: UInt64?) -> PTYSession? {
        guard let session = iTermController.sharedInstance().anySession(forReference: guid),
              let textview = session.textview else {
            send(.error(CompanionError(code: .unknownSession,
                                       message: "That session no longer exists. It may have been closed.")),
                 requestID: requestID)
            return nil
        }
        guard textview.frame.width > 0 else {
            send(.error(CompanionError(code: .unknownSession,
                                       message: "That session hasn’t started running yet, so there is nothing to show.")),
                 requestID: requestID)
            return nil
        }
        return session
    }

    private func handleFetchSessionScreenInfo(guid: String, requestID: UInt64?) {
        guard let session = contentSession(guid: guid, requestID: requestID),
              let textview = session.textview else {
            return
        }
        let info = CompanionSessionScreenInfo(guid: guid,
                                              name: session.name,
                                              lineCount: Int(session.screen.numberOfLines()),
                                              columns: Int(session.columns),
                                              // Exclude the right gutter (accessory panels / timestamp
                                              // slot) so it matches the rendered tile width.
                                              width: Double(textview.widthExcludingRightGutter()),
                                              lineHeight: Double(textview.lineHeight),
                                              // Matches the fallback the offscreen renderer uses
                                              // for windowless (buried/peer) sessions.
                                              scale: Double(textview.window?.backingScaleFactor ?? 2.0))
        send(.sessionScreenInfo(info), requestID: requestID)
    }

    /// Upper bound on lines per content request, so one request cannot render
    /// (and frame) an arbitrarily large bitmap.
    private static let maxContentLines = 200

    private func handleFetchSessionContent(guid: String,
                                           firstLine: Int,
                                           lineCount: Int,
                                           requestID: UInt64?) {
        guard let session = contentSession(guid: guid, requestID: requestID),
              let textview = session.textview else {
            return
        }
        let totalLines = Int(session.screen.numberOfLines())
        let first = max(0, firstLine)
        let count = min(min(lineCount, Self.maxContentLines), totalLines - first)
        guard count > 0 else {
            send(.error(CompanionError(code: .badRequest,
                                       message: "The requested lines are out of range.")),
                 requestID: requestID)
            return
        }
        // A buried session (or a workgroup peer parked off screen, or one in
        // its undoable-termination window) has its textview's dataSource
        // detached, so the renderer sees zero lines and fails. The screen
        // object still holds the content; re-attach it for the duration of
        // the render and restore the detached state afterwards. The Mac UI
        // never hits this because revealing a session disinters it first.
        let wasDetached = textview.dataSource == nil
        if wasDetached {
            textview.dataSource = session.screen
        }
        defer {
            if wasDetached {
                textview.dataSource = nil
            }
        }
        // Renderer skips the background fill when bgColor is nil, leaving
        // margins transparent; fall back to black so tiles look continuous.
        let backgroundColor = session.processedBackgroundColor ?? .black
        guard let image = textview.renderImage(withLines: NSRange(location: first, length: count),
                                               includeMargins: false,
                                               backgroundColor: backgroundColor,
                                               showCursor: false) else {
            RLog("Companion bridge: render failed for \(guid): wasDetached=\(wasDetached) lines=\(totalLines) frame=\(NSStringFromRect(textview.frame))")
            send(.error(CompanionError(code: .internalError,
                                       message: "Rendering the session content failed.")),
                 requestID: requestID)
            return
        }
        let pngData = image.dataForFile(of: .png)
        guard !pngData.isEmpty else {
            send(.error(CompanionError(code: .internalError,
                                       message: "Encoding the session content failed.")),
                 requestID: requestID)
            return
        }
        send(.sessionContent(CompanionSessionContent(guid: guid,
                                                     firstLine: first,
                                                     lineCount: count,
                                                     pngData: pngData)),
             requestID: requestID)
    }

    /// Render a scrollback tile addressed by absolute line for the live canvas.
    /// The request is clamped to what is currently available; the reply reports the
    /// range actually covered plus the current window (oldest absolute line + total
    /// lines), so the phone can size its canvas and resolve eviction races.
    private func handleFetchHistoryTile(streamID: UInt32,
                                        firstAbsLine: Int64,
                                        lineCount: Int,
                                        generationId: UInt32,
                                        requestID: UInt64?) {
        RLog("Companion historyTile req stream=\(streamID) firstAbs=\(firstAbsLine) lineCount=\(lineCount) gen=\(generationId)")
        guard let context = streams[streamID],
              let session = iTermController.sharedInstance().anySession(forReference: context.guid),
              let textview = session.textview else {
            RLog("Companion historyTile FAIL: no such stream \(streamID)")
            send(.error(CompanionError(code: .badRequest, message: "No such stream.")), requestID: requestID)
            return
        }
        let overflow = session.screen.totalScrollbackOverflow()
        let total = Int(session.screen.numberOfLines())
        let window = CompanionHistoryWindow(firstAbsLine: overflow, lineCount: total)
        // Entirely evicted (or empty): reply with a 0-line tile carrying the window
        // so the phone marks the region unavailable without erroring.
        guard let covered = window.clamped(absLine: firstAbsLine, count: min(lineCount, Self.maxContentLines)) else {
            RLog("Companion historyTile EVICTED firstAbs=\(firstAbsLine) window=[\(overflow),\(overflow + Int64(total))) -> 0 lines")
            send(.historyTile(CompanionHistoryTile(streamID: streamID, generationId: generationId,
                                                   firstAbsLine: max(firstAbsLine, overflow), lineCount: 0,
                                                   windowFirstAbsLine: overflow, windowLineCount: total,
                                                   pngData: Data())),
                 requestID: requestID)
            return
        }
        let relativeFirst = Int(covered.absLine - overflow)
        // Detached sessions (buried/parked) render zero lines; re-attach for the
        // render and restore after, as handleFetchSessionContent does.
        let wasDetached = textview.dataSource == nil
        if wasDetached { textview.dataSource = session.screen }
        defer { if wasDetached { textview.dataSource = nil } }
        let backgroundColor = session.processedBackgroundColor ?? .black
        // Render with the current selection so scrollback shows the same highlight
        // as the live band; the phone refetches affected tiles when it changes.
        guard let image = textview.renderImage(withLines: NSRange(location: relativeFirst, length: covered.count),
                                               includeMargins: false,
                                               backgroundColor: backgroundColor,
                                               showCursor: false,
                                               includeSelection: true) else {
            RLog("Companion historyTile FAIL render covered=[\(covered.absLine),+\(covered.count)) rel=\(relativeFirst) total=\(total) detached=\(wasDetached) frame=\(NSStringFromRect(textview.frame))")
            send(.error(CompanionError(code: .internalError, message: "Rendering the session content failed.")),
                 requestID: requestID)
            return
        }
        let pngData = image.dataForFile(of: .png)
        RLog("Companion historyTile OK covered=[\(covered.absLine),+\(covered.count)) overflow=\(overflow) total=\(total) bytes=\(pngData.count)")
        send(.historyTile(CompanionHistoryTile(streamID: streamID, generationId: generationId,
                                               firstAbsLine: covered.absLine, lineCount: covered.count,
                                               windowFirstAbsLine: overflow, windowLineCount: total,
                                               pngData: pngData)),
             requestID: requestID)
    }

    // MARK: Sending

    /// Enqueue one envelope. Synchronous: enqueue order (main-actor order) is
    /// transmit order among control frames, which always precede pending media.
    private func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox?.enqueueControl(HostEnvelope(requestID: requestID, payload: payload))
    }
}

private extension CompanionSelectionMode {
    /// Map the wire selection mode to iTerm2's. Box selection is not exposed to the
    /// phone, so there is no inverse for it.
    var iTermSelectionMode: iTermSelectionMode {
        switch self {
        case .character: return .kiTermSelectionModeCharacter
        case .word: return .kiTermSelectionModeWord
        case .line: return .kiTermSelectionModeWholeLine
        case .smart: return .kiTermSelectionModeSmart
        }
    }
}
