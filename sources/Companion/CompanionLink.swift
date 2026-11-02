//
//  CompanionLink.swift
//  iTerm2
//
//  The network endpoint of one phone connection, kept OFF the main actor.
//
//  A modal alert started from a main-queue callout freezes the main dispatch
//  queue and every @MainActor job until it is dismissed. CompanionHostBridge is
//  @MainActor because its handlers read and write app state, so on its own it
//  goes silent for the whole time such an alert is up. The link owns the parts
//  that must keep working regardless: the receive loop, the outbox drain, and
//  the few messages that can be answered without app state (hello, ping, and
//  the relay room secret a connecting phone sends before its hello). It also
//  keeps terminal input from queuing behind a blocked main thread.
//  Everything else is forwarded, in wire order, to the bridge through `events`,
//  where it simply waits until the main actor runs again.
//
//  Main-actor code talks to the link only through nonisolated, synchronous
//  calls (send, close). It must never reach the link with `Task { await
//  link... }`: a task created on the main actor starts on the main actor, so it
//  would be stuck behind the very freeze this type exists to survive.
//

import Foundation
import QuartzCore
import CompanionProtocol
import os

/// Delivers the phone's stream acknowledgements to the streamer that paces
/// against them, without going through the main actor. A streamer stops
/// emitting frames once it gets about half a second ahead of the last
/// acknowledgement, so if acknowledgements waited for the main queue the video
/// would stall for as long as an alert had that queue frozen.
final class CompanionStreamAckRouter: Sendable {
    typealias Sink = @Sendable (_ ptsMilliseconds: UInt64, _ queueDepth: Int) -> Void
    private let sinks = LockedState(initialState: [UInt32: Sink]())

    /// `sink` is called on the link's executor and must be safe on any thread.
    func register(streamID: UInt32, sink: @escaping Sink) {
        sinks.withLock { $0[streamID] = sink }
    }

    func unregister(streamID: UInt32) {
        sinks.withLock { $0[streamID] = nil }
    }

    func deliver(streamID: UInt32, ptsMilliseconds: UInt64, queueDepth: Int) {
        let sink = sinks.withLock { $0[streamID] }
        sink?(ptsMilliseconds, queueDepth)
    }
}

actor CompanionLink {
    enum Event {
        /// A decoded message from the phone, in wire order. `handledByLink` is
        /// true when the link already handled it (hello, ping, relayRoomSecret, streamAck);
        /// the bridge then only does its bookkeeping and must not answer again.
        case envelope(ClientEnvelope, handledByLink: Bool)
        /// The link answered a hello. `blocked` is true when the peer is
        /// version-incompatible. Follows that hello's `.envelope`.
        case helloCompleted(peerRevision: Int, blocked: Bool)
        /// The hello just completed was incompatible. Follows `.helloCompleted`.
        case versionIncompatible(CompanionProtocolVersion.Compatibility)
        /// The connection ended. Always the last event. The error is nil for a
        /// deliberate local close and non-nil when the connection dropped.
        case closed(Error?)
    }

    /// Outbound frames. Lock-protected, so main-actor code and encoder threads
    /// enqueue synchronously and enqueue order is wire order.
    nonisolated let outbox = CompanionPriorityOutbox<HostEnvelope>()

    /// Where the phone's acknowledgements of video frames go. The bridge
    /// registers each stream here, and the link delivers to it directly.
    nonisolated let streamAcks = CompanionStreamAckRouter()

    /// Single consumer: the @MainActor bridge.
    nonisolated let events: AsyncStream<Event>

    /// State that nonisolated entry points and the drain task share with the
    /// actor. Never held across a suspension point.
    private struct Shared: Sendable {
        var started = false
        var localCloseRequested = false
        /// Set once the connection has ended; `closeError` is then final.
        var finished = false
        var closeError: Error?
        var closeWaiters: [CheckedContinuation<Error?, Never>] = []
        var drainTask: Task<Void, Never>?
        /// The pairing is being removed: store no room secret from here on.
        var roomSecretStorageStopped = false
        /// While true the drain sends the peer nothing but hello, error, and
        /// unpaired. Mirrors `versionBlocked` for the drain task, which is not
        /// on the actor. The bridge learns of a blocked peer through an event
        /// that lags while the main actor is busy; this closes that gap.
        var versionBlocked = false
    }

    private nonisolated let shared = LockedState(initialState: Shared())
    /// Keeps the link subscribed to the stall monitor
    /// for as long as it is open.
    private nonisolated let subscriptions = LockedState(initialState: [AnyObject]())
    private nonisolated let transport: MessageTransport
    private nonisolated let storeRoomSecret: @Sendable (Data) throws -> Void
    private nonisolated let mainStall: CompanionMainStallSource
    private nonisolated let eventsContinuation: AsyncStream<Event>.Continuation

    private var versionBlocked = false

    init(transport: MessageTransport,
         storeRoomSecret: @escaping @Sendable (Data) throws -> Void,
         mainStall: CompanionMainStallSource) {
        self.transport = transport
        self.storeRoomSecret = storeRoomSecret
        self.mainStall = mainStall
        (events, eventsContinuation) = AsyncStream<Event>.makeStream()
    }

    static func makeForProduction(transport: MessageTransport) -> CompanionLink {
        CompanionLink(transport: transport,
                      storeRoomSecret: storeRoomSecretIfChanged,
                      mainStall: CompanionMainThreadMonitor.shared)
    }

    /// The production room secret store. The phone re-sends the secret on every
    /// connect, so skip the keychain write when it is the one already held.
    static let storeRoomSecretIfChanged: @Sendable (Data) throws -> Void = { secret in
        if CompanionMacIdentity.pairedRoomSecret() == secret {
            return
        }
        try CompanionMacIdentity.storePairedRoomSecret(secret)
    }

    // MARK: Nonisolated entry points

    /// Start receiving and sending. Safe to call from the main actor even if it
    /// is about to freeze: the tasks are detached, so none of them starts on
    /// the caller's actor.
    nonisolated func start() {
        let outbox = self.outbox
        let transport = self.transport
        let lock = self.shared
        let alreadyStarted = lock.withLock { state -> Bool in
            if state.started || state.finished {
                return true
            }
            state.started = true
            state.drainTask = Task.detached {
                await Self.drain(outbox: outbox, transport: transport, shared: lock)
            }
            return false
        }
        guard !alreadyStarted else { return }
        let token = mainStall.addObserver { }
        subscriptions.withLock { $0 = [token] }
        Task.detached { [self] in
            await self.receiveLoop()
        }
    }

    /// Enqueue one control message for the phone. Synchronous: call order is
    /// wire order among control frames.
    nonisolated func send(_ payload: CompanionHostMessage, requestID: UInt64?) {
        outbox.enqueueControl(HostEnvelope(requestID: requestID, payload: payload))
    }

    /// Close the connection without a farewell. Idempotent.
    nonisolated func close() {
        let (alreadyRequested, started) = shared.withLock { shared -> (Bool, Bool) in
            let result = (shared.localCloseRequested, shared.started)
            shared.localCloseRequested = true
            return result
        }
        guard !alreadyRequested else { return }
        outbox.finish()
        let transport = self.transport
        Task.detached {
            // When started, the receive loop sees this and reports the close.
            await transport.close()
        }
        if !started {
            // No receive loop is running to notice, so report it here.
            finish(error: nil)
        }
    }

    /// Send `.unpaired`, wait until it is on the wire, then close. The farewell
    /// reaches the phone even if it is version-blocked.
    nonisolated func sendFarewellAndClose() async {
        let (alreadyRequested, drainTask) = shared.withLock { shared -> (Bool, Task<Void, Never>?) in
            let result = (shared.localCloseRequested, shared.drainTask)
            shared.localCloseRequested = true
            return result
        }
        guard !alreadyRequested else { return }
        send(.unpaired, requestID: nil)
        outbox.finish()
        // The drain exits once it has sent everything enqueued before finish(),
        // including the farewell. Close only AFTER that: closing the transport
        // first would race the farewell against the connection teardown.
        await drainTask?.value
        DLog("Companion link: farewell flushed; closing transport")
        await transport.close()
        if drainTask == nil {
            finish(error: nil)
        }
    }

    /// Whether the connection has ended.
    nonisolated var isClosed: Bool {
        return shared.withLock { $0.finished }
    }

    /// Suspends until the connection has ended, then returns what `.closed`
    /// carried.
    nonisolated func waitUntilClosed() async -> Error? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            let result = shared.withLock { shared -> (finished: Bool, error: Error?) in
                if shared.finished {
                    return (true, shared.closeError)
                }
                shared.closeWaiters.append(continuation)
                return (false, nil)
            }
            if result.finished {
                continuation.resume(returning: result.error)
            }
        }
    }

    // MARK: Drain

    private static func isAllowedWhileVersionBlocked(_ payload: CompanionHostMessage) -> Bool {
        switch payload {
        case .hello, .error, .unpaired:
            return true
        default:
            return false
        }
    }

    private static func drain(outbox: CompanionPriorityOutbox<HostEnvelope>,
                              transport: MessageTransport,
                              shared: LockedState<Shared>) async {
        // Diagnostic counters/heartbeat. If a send wedges (half-open splice),
        // the heartbeat below stops logging while the link believes it is still
        // connected -- the signal we need.
        var mediaFrames = 0
        var mediaBytes = 0
        var controlFrames = 0
        var lastHeartbeat = CACurrentMediaTime()
        RLog("link outbox drain started")
        drain: while true {
            let data: Data
            let isMedia: Bool
            let item = await outbox.next()
            let blocked = shared.withLock { $0.versionBlocked }
            switch item {
            case .finished:
                break drain
            case .control(let envelope):
                isMedia = false
                if blocked && !isAllowedWhileVersionBlocked(envelope.payload) {
                    DLog("Companion link: dropping a frame for a version-blocked peer")
                    continue
                }
                do {
                    data = try WireCoding.encode(envelope)
                } catch {
                    RLog("Companion link: DROPPING unencodable envelope: \(error)")
                    continue
                }
            case .media(let payload):
                isMedia = true
                if blocked {
                    continue
                }
                // Control frames stay bare JSON; media frames carry the marker.
                data = CompanionFrameChannel.frameMedia(payload)
            }
            do {
                try await transport.send(data)
            } catch {
                RLog("link outbox send FAILED (outbox dead) after \(mediaFrames) media/\(controlFrames) control: \(error)")
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
                RLog("link outbox alive: sent \(mediaFrames) media (\(mediaBytes) B), \(controlFrames) control")
                lastHeartbeat = now
            }
        }
        RLog("link outbox drained/exited: \(mediaFrames) media, \(controlFrames) control total")
    }

    // MARK: Receive

    private func receiveLoop() async {
        // If the relay splice goes half-open during streaming, receive() can
        // block forever -- we'd see "started" but never "receive FAILED" or
        // "exited", confirming the wedge (no teardown, no re-park).
        RLog("link receiveLoop started")
        let dropError: Error
        while true {
            let frame: Data
            do {
                frame = try await transport.receive()
            } catch {
                RLog("link receiveLoop receive() ended: \(error)")
                dropError = error
                break
            }
            guard let envelope = try? WireCoding.decode(ClientEnvelope.self, from: frame) else {
                // A frame we cannot decode (newer phone) is dropped, not fatal.
                continue
            }
            handle(envelope)
        }
        let closedLocally = shared.withLock { $0.localCloseRequested }
        RLog("link receiveLoop exited (closedLocally=\(closedLocally))")
        outbox.finish()
        finish(error: closedLocally ? nil : dropError)
    }

    private func handle(_ envelope: ClientEnvelope) {
        let requestID = envelope.requestID
        // An incompatible peer is served nothing but a re-hello: the phone shows
        // an upgrade panel and disconnects, but refuse here too so a stale peer
        // cannot drive an out-of-date protocol.
        if versionBlocked {
            if case .hello(let revision, let minimumPeer) = envelope.payload {
                handleHello(envelope, peerRevision: revision, peerMinimumPeer: minimumPeer)
            } else {
                send(.error(CompanionError(code: .badRequest, message: "Companion app upgrade required")),
                     requestID: requestID)
            }
            return
        }
        switch envelope.payload {
        case .hello(let revision, let minimumPeer):
            handleHello(envelope, peerRevision: revision, peerMinimumPeer: minimumPeer)
        case .ping:
            send(.pong, requestID: requestID)
            eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        case .relayRoomSecret(let secret):
            // A connecting phone couriers this BEFORE its hello and waits for
            // the ack, so it has to be answered here or the phone could never
            // reach hello while the main actor is frozen.
            // Persist the secret so the mac can sign its relay parks, then ack so
            // the phone may register its verifier. Idempotent (re-sent every
            // connect); a store failure simply withholds the ack, and the phone
            // retries on the next connection.
            do {
                // Stored under the lock that stopStoringRoomSecret takes, so an
                // unpair that has started deleting key material cannot have
                // the secret written back behind it.
                try shared.withLock { shared in
                    guard !shared.roomSecretStorageStopped else {
                        throw RoomSecretStorageStopped()
                    }
                    try storeRoomSecret(secret)
                }
                RLog("Companion link: stored relay room secret")
                send(.relayRoomSecretStored, requestID: requestID)
            } catch {
                RLog("Companion link: failed to store room secret: \(error)")
                send(.error(CompanionError(code: .internalError, message: "\(error)")),
                     requestID: requestID)
            }
            eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        case .streamAck(let streamID, let lastPTSMilliseconds, let queueDepth):
            streamAcks.deliver(streamID: streamID, ptsMilliseconds: lastPTSMilliseconds, queueDepth: queueDepth)
            eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        case .sendKey, .pasteText, .reportScrollWheel:
            // Terminal input is only meaningful now. Forwarded while the main
            // thread cannot act on it, it would sit in the event stream and be
            // typed into the session whenever the alert is finally dismissed,
            // possibly minutes later. Refuse it instead. This does not depend on
            // what the phone was told: an older Buddy does not know to hold its
            // input, and a new one may send before the status reaches it.
            guard !mainThreadCannotServeRequests() else {
                RLog("Companion link: refusing terminal input while the main thread is blocked")
                if let requestID {
                    send(.error(CompanionError(code: .internalError,
                                               message: "The Mac can’t accept input right now.")),
                         requestID: requestID)
                }
                break
            }
            eventsContinuation.yield(.envelope(envelope, handledByLink: false))
        default:
            eventsContinuation.yield(.envelope(envelope, handledByLink: false))
        }
    }

    /// Whether requests that need the main thread will go unserved for now.
    /// An alert being up is not enough to say so: one started by something the
    /// user did at the Mac leaves the main queue running.
    private func mainThreadCannotServeRequests() -> Bool {
        return mainStall.isMainBlocked()
    }

    private func handleHello(_ envelope: ClientEnvelope, peerRevision: Int, peerMinimumPeer: Int) {
        let verdict = CompanionProtocolVersion.evaluate(peerRevision: peerRevision,
                                                        peerMinimumPeer: peerMinimumPeer)
        let blocked = verdict != .compatible
        versionBlocked = blocked
        shared.withLock { $0.versionBlocked = blocked }
        send(.hello(revision: CompanionProtocolVersion.current,
                    minimumPeer: CompanionProtocolVersion.minimumPeer),
             requestID: envelope.requestID)
        eventsContinuation.yield(.envelope(envelope, handledByLink: true))
        eventsContinuation.yield(.helloCompleted(peerRevision: peerRevision, blocked: blocked))
        if blocked {
            eventsContinuation.yield(.versionIncompatible(verdict))
        }
    }

    // MARK: Ending

    /// The pairing is being removed. From now on a room secret the phone
    /// couriers is not stored. Returns only once any store already under way
    /// has finished, so the caller can delete the stored secret next and know
    /// nothing will write it back.
    nonisolated func stopStoringRoomSecret() {
        shared.withLock { $0.roomSecretStorageStopped = true }
    }

    private struct RoomSecretStorageStopped: Error, CustomStringConvertible {
        var description: String { "This Mac is no longer paired." }  // Localization unneeded
    }

    private nonisolated func finish(error: Error?) {
        let waiters = shared.withLock { shared -> [CheckedContinuation<Error?, Never>]? in
            if shared.finished {
                return nil
            }
            shared.finished = true
            shared.closeError = error
            let waiters = shared.closeWaiters
            shared.closeWaiters = []
            return waiters
        }
        guard let waiters else { return }
        subscriptions.withLock { $0 = [] }
        eventsContinuation.yield(.closed(error))
        eventsContinuation.finish()
        for waiter in waiters {
            waiter.resume(returning: error)
        }
    }
}
