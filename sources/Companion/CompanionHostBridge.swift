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
    private let transport: MessageTransport
    private var receiveTask: Task<Void, Never>?
    /// Control frames drain ahead of media so input/replies never wait behind a
    /// video backlog; media is never dropped (see CompanionPriorityOutbox).
    private var outbox: CompanionPriorityOutbox<HostEnvelope>?
    private var outboxTask: Task<Void, Never>?

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
    /// Set once an incompatible hello is seen: the bridge then serves nothing but
    /// a re-hello, so a stale peer cannot drive an out-of-date protocol.
    private var versionBlocked = false

    init(transport: MessageTransport) {
        self.transport = transport
    }

    func start() {
        RLog("bridge start (phone connected, bridge live)")

        let outbox = CompanionPriorityOutbox<HostEnvelope>()
        self.outbox = outbox
        outboxTask = Task { [transport] in
            // Diagnostic counters/heartbeat. If a send wedges
            // (half-open splice), the heartbeat below stops logging while the
            // bridge believes it is still connected -- the signal we need.
            var mediaFrames = 0
            var mediaBytes = 0
            var controlFrames = 0
            var lastHeartbeat = CACurrentMediaTime()
            RLog("bridge outbox drain started")
            drain: while true {
                let data: Data
                let isMedia: Bool
                switch await outbox.next() {
                case .finished:
                    break drain
                case .control(let envelope):
                    isMedia = false
                    do {
                        data = try WireCoding.encode(envelope)
                    } catch {
                        RLog("Companion bridge: DROPPING unencodable envelope: \(error)")
                        continue
                    }
                case .media(let payload):
                    isMedia = true
                    // Control frames stay bare JSON; media frames carry the marker.
                    data = CompanionFrameChannel.frameMedia(payload)
                }
                do {
                    try await transport.send(data)
                } catch {
                    RLog("bridge outbox send FAILED (outbox dead) after \(mediaFrames) media/\(controlFrames) control: \(error)")
                    break drain
                }
                if isMedia {
                    mediaFrames += 1
                    mediaBytes += data.count
                } else {
                    controlFrames += 1
                }
                let now = CACurrentMediaTime()
                if now - lastHeartbeat >= 5 {
                    RLog("bridge outbox alive: sent \(mediaFrames) media (\(mediaBytes) B), \(controlFrames) control")
                    lastHeartbeat = now
                }
            }
            RLog("bridge outbox drained/exited: \(mediaFrames) media, \(controlFrames) control total")
        }

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }

    }

    /// Tell the phone it has been unpaired, flush the outbox so the message
    /// actually reaches the wire, then tear down. Used by unpair; a plain
    /// stop() would race the farewell against the connection close.
    func announceUnpairedAndStop() async {
        RLog("Companion bridge: announcing unpair")
        onClose = nil
        endAllStreams(reason: .sessionClosed)
        send(.unpaired, requestID: nil)
        outbox?.finish()
        outbox = nil
        // Drain: the outbox task exits once it has sent everything enqueued
        // before finish(), including the farewell.
        await outboxTask?.value
        outboxTask = nil
        DLog("Companion bridge: farewell flushed; closing transport")
        // Tear down the receive side only AFTER the farewell is on the wire:
        // cancelling the receive task cancels the underlying connection (its
        // onCancel treats cancellation as abandoning the transport), which
        // would kill the farewell if done first.
        receiveTask?.cancel()
        receiveTask = nil
        await transport.close()
    }

    func stop() {
        // A user-initiated stop is not a remote disconnect; don't report one.
        onClose = nil
        receiveTask?.cancel()
        receiveTask = nil
        teardownStreams()
        let transport = self.transport
        Task { await transport.close() }
    }

    private func teardownStreams() {
        endAllStreams(reason: .sessionClosed)
        outbox?.finish()
        outbox = nil
        outboxTask?.cancel()
        outboxTask = nil
    }

    // MARK: Receive loop

    private func runReceiveLoop() async {
        // If the relay splice goes half-open during streaming, receive()
        // can block forever -- we'd see "started" but never "receive FAILED" or
        // "exited", confirming the wedge (no teardown, no re-park).
        RLog("bridge receiveLoop started")
        var dropError: Error?
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                RLog("bridge receiveLoop receive() FAILED (drop detected): \(error)")
                dropError = error
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        RLog("bridge receiveLoop exited -> teardownStreams + onClose (will re-park)")
        teardownStreams()
        onClose?(dropError)
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        if versionBlocked {
            if case .hello(let revision, let minimumPeer) = envelope.payload {
                handleHello(peerRevision: revision, peerMinimumPeer: minimumPeer, requestID: requestID)
            } else {
                send(.error(CompanionError(code: .badRequest,
                                           message: "Companion app upgrade required")),
                     requestID: requestID)
            }
            return
        }

        switch envelope.payload {
        case .unsupported:
            send(.error(CompanionError(code: .badRequest,
                                       message: "Unsupported request; app upgrade required")),
                 requestID: requestID)
        case .hello(let revision, let minimumPeer):
            handleHello(peerRevision: revision, peerMinimumPeer: minimumPeer, requestID: requestID)
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
        case .ping:
            send(.pong, requestID: requestID)
        case .relayRoomSecret(let secret):
            do {
                try CompanionMacIdentity.storePairedRoomSecret(secret)
                send(.relayRoomSecretStored, requestID: requestID)
            } catch {
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
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
        case .streamAck(let streamID, let lastPTSMilliseconds, let queueDepth):
            streams[streamID]?.streamer.noteAck(ptsMilliseconds: lastPTSMilliseconds,
                                                queueDepth: queueDepth)
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
            // selection directly.
            var moved = true
            switch phase {
            case .begin:
                textview.selection?.begin(at: coord, mode: mode.iTermSelectionMode,
                                          resume: false, append: false)
            case .move:
                moved = textview.selection?.moveEndpoint(to: coord) ?? false
            case .end:
                moved = textview.selection?.moveEndpoint(to: coord) ?? false
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
        let span = selection.spanningAbsRange
        let gridWidth = Int(textview.dataSource?.width() ?? 0)
        let end = Self.inclusiveSelectionEnd(exclusiveColumn: Int(span.end.x), absLine: span.end.y,
                                             gridWidth: gridWidth)
        return CompanionSelectionRange(
            start: CompanionSelectionPoint(absLine: span.start.y, column: Int(span.start.x)),
            end: CompanionSelectionPoint(absLine: end.absLine, column: end.column))
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

    private func handleHello(peerRevision: Int, peerMinimumPeer: Int, requestID: UInt64?) {
        send(.hello(revision: CompanionProtocolVersion.current,
                    minimumPeer: CompanionProtocolVersion.minimumPeer),
             requestID: requestID)
        let verdict = CompanionProtocolVersion.evaluate(peerRevision: peerRevision,
                                                        peerMinimumPeer: peerMinimumPeer)
        versionBlocked = (verdict != .compatible)
        RLog("Companion bridge: hello peer(rev=\(peerRevision), min=\(peerMinimumPeer)) -> \(verdict)")
        guard verdict != .compatible else { return }
        onVersionIncompatible?(verdict)
    }

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
