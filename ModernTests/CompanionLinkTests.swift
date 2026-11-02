//
//  CompanionLinkTests.swift
//  iTerm2 ModernTests
//
//  CompanionLink is the off-main endpoint of a phone connection. These tests
//  drive it the way a phone would, over an in-memory transport, and pin:
//
//    - It keeps answering hello and ping while the main queue is frozen by a
//      modal run loop started from a main-queue callout (the bug: iTerm2 Buddy
//      went dead whenever such an alert was up).
//    - What it answers itself versus what it forwards to the bridge, and that
//      forwarding preserves wire order with `.closed` last.
//    - Version gating, farewell ordering and safe terminal input during stalls.

import XCTest
import os
import CompanionProtocol
@testable import iTerm2SharedARC

final class CompanionLinkTests: XCTestCase {
    // MARK: Fixture

    /// The phone's end of the connection.
    private final class Phone {
        let transport: CompanionLoopbackTransport

        init(transport: CompanionLoopbackTransport) {
            self.transport = transport
        }

        private static func encoder() -> JSONEncoder {
            let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
        }
        private static func decoder() -> JSONDecoder {
            let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
        }

        func send(_ payload: CompanionClientMessage, requestID: UInt64? = nil) async throws {
            let envelope = ClientEnvelope(requestID: requestID, payload: payload)
            try await transport.send(try Self.encoder().encode(envelope))
        }

        func sendRaw(_ data: Data) async throws {
            try await transport.send(data)
        }

        /// The next frame the Mac sent, described. Fails rather than hangs if
        /// nothing arrives.
        func next() async throws -> String {
            let transport = self.transport
            let data = try await FrozenMainQueue.withFailsafe("the next frame from the Mac") {
                try await transport.receive()
            }
            let envelope = try Self.decoder().decode(HostEnvelope.self, from: data)
            return CompanionLinkTests.describe(envelope)
        }

        /// The next frame the Mac sent, decoded.
        func nextEnvelope() async throws -> HostEnvelope {
            let transport = self.transport
            let data = try await FrozenMainQueue.withFailsafe("the next frame from the Mac") {
                try await transport.receive()
            }
            return try Self.decoder().decode(HostEnvelope.self, from: data)
        }

        /// Asserts the connection is closed with nothing further queued.
        func expectClosed(file: StaticString = #filePath, line: UInt = #line) async {
            let transport = self.transport
            do {
                let data = try await FrozenMainQueue.withFailsafe("the connection to close") {
                    try await transport.receive()
                }
                let text = String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
                XCTFail("expected the connection to be closed, but received: \(text)", file: file, line: line)
            } catch {
                XCTAssertFalse(error is FrozenMainQueue.Timeout,
                               "the connection never closed", file: file, line: line)
            }
        }

        func close() async {
            await transport.close()
        }
    }

    /// Stands in for the keychain-backed room secret store.
    private final class RoomSecretStore: Sendable {
        struct Unwritable: Error {}
        private let state = LockedState(initialState: (stored: [Data](), fails: false))

        var stored: [Data] { state.withLock { $0.stored } }
        func failWrites() { state.withLock { $0.fails = true } }

        func store(_ secret: Data) throws {
            let fails = state.withLock { state -> Bool in
                if !state.fails {
                    state.stored.append(secret)
                }
                return state.fails
            }
            if fails {
                throw Unwritable()
            }
        }
    }

    /// Stands in for CompanionMainThreadMonitor.
    private final class FakeStallSource: CompanionMainStallSource {
        private let state = LockedState(initialState: (blocked: false, observers: [@Sendable () -> Void]()))
        private let expedites = LockedState(initialState: 0)

        /// How many times the link asked for a quick check.
        var expediteCount: Int { expedites.withLock { $0 } }

        func expedite() {
            expedites.withLock { $0 += 1 }
        }

        func setBlocked(_ blocked: Bool) {
            let observers = state.withLock { state -> [@Sendable () -> Void] in
                state.blocked = blocked
                return state.observers
            }
            observers.forEach { $0() }
        }

        func isMainBlocked() -> Bool {
            return state.withLock { $0.blocked }
        }

        func addObserver(_ changed: @escaping @Sendable () -> Void) -> AnyObject {
            state.withLock { $0.observers.append(changed) }
            return NSObject()
        }
    }

    private struct Fixture {
        let link: CompanionLink
        let phone: Phone
        let roomSecrets: RoomSecretStore
        let stall: FakeStallSource
    }

    private var links: [CompanionLink] = []
    override func tearDown() {
        links.forEach { $0.close() }
        links.removeAll()
        super.tearDown()
    }

    private func makeFixture(start: Bool = true) -> Fixture {
        let (macEnd, phoneEnd) = CompanionLoopbackTransport.makePair()
        let roomSecrets = RoomSecretStore()
        let stall = FakeStallSource()
        let link = CompanionLink(transport: macEnd,
                                 storeRoomSecret: { try roomSecrets.store($0) },
                                 mainStall: stall)
        links.append(link)
        if start { link.start() }
        return Fixture(link: link, phone: Phone(transport: phoneEnd), roomSecrets: roomSecrets, stall: stall)
    }

    private static let compatibleHello = CompanionClientMessage.hello(
        revision: CompanionProtocolVersion.current,
        minimumPeer: CompanionProtocolVersion.minimumPeer)
    private static let incompatibleHello = CompanionClientMessage.hello(revision: 9999, minimumPeer: 9999)
    /// A phone from before the mac-status revision. Still compatible.
    private static let revision13Hello = CompanionClientMessage.hello(revision: 13, minimumPeer: 11)

    // MARK: Describing frames and events

    private static func tag(_ requestID: UInt64?) -> String {
        return requestID.map { "#\($0)" } ?? ""
    }

    private static func describe(_ envelope: HostEnvelope) -> String {
        let name: String
        switch envelope.payload {
        case .hello:
            name = "hello"
        case .pong:
            name = "pong"
        case .relayRoomSecretStored:
            name = "relayRoomSecretStored"
        case .error:
            name = "error"
        case .unpaired:
            name = "unpaired"
        default:
            name = "other"
        }
        return name + tag(envelope.requestID)
    }

    private static func describe(_ payload: CompanionClientMessage) -> String {
        switch payload {
        case .hello(let revision, _):
            return "hello(\(revision))"
        case .ping:
            return "ping"
        case .relayRoomSecret:
            return "relayRoomSecret"
        case .sendKey:
            return "sendKey"
        case .reportScrollWheel:
            return "reportScrollWheel"
        case .pasteText:
            return "pasteText"
        case .listSessions:
            return "listSessions"
        case .stopSessionStream(let id):
            return "stopSessionStream(\(id))"
        default:
            return "other"
        }
    }

    private static func describe(_ event: CompanionLink.Event) -> String {
        switch event {
        case .envelope(let envelope, let handledByLink):
            return (handledByLink ? "handled " : "forwarded ") + describe(envelope.payload) + tag(envelope.requestID)
        case .helloCompleted(let peerRevision, let blocked):
            return "helloCompleted(\(peerRevision), blocked=\(blocked))"
        case .versionIncompatible:
            return "versionIncompatible"
        case .closed(let error):
            return error == nil ? "closed(locally)" : "closed(dropped)"
        }
    }

    /// Every event the link emitted, up to the end of its stream.
    private func allEvents(_ link: CompanionLink) async throws -> [CompanionLink.Event] {
        return try await FrozenMainQueue.withFailsafe("the link's event stream to end") {
            var events: [CompanionLink.Event] = []
            for await event in link.events {
                events.append(event)
            }
            return events
        }
    }

    private func allEventDescriptions(_ link: CompanionLink) async throws -> [String] {
        return try await allEvents(link).map { Self.describe($0) }
    }


    private static func key(_ text: String) -> CompanionClientMessage {
        .sendKey(sessionGuid: "g", event: CompanionKeyEvent(key: .text(text)))
    }

    func testHelloIsAnsweredWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(Self.compatibleHello, requestID: 7)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "hello#7")
        }
    }

    func testPingIsAnsweredWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(.ping, requestID: 2)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "pong#2")
        }
    }

    func testLinkStartedInsideTheFreezingCalloutStillAnswers() async throws {
        let fixture = makeFixture(start: false)
        try await FrozenMainQueue.run(setup: {
            fixture.link.start()
        }) { _ in
            try await fixture.phone.send(Self.compatibleHello, requestID: 1)
            let reply = try await fixture.phone.next()
            XCTAssertEqual(reply, "hello#1")
        }
    }

    func testRoomSecretIsStoredAndAckedWhileMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        let secret = Data(repeating: 7, count: 32)
        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(.relayRoomSecret(secret), requestID: 4)
            let ack = try await fixture.phone.next()
            XCTAssertEqual(ack, "relayRoomSecretStored#4")
            try await fixture.phone.send(Self.compatibleHello, requestID: 5)
            let hello = try await fixture.phone.next()
            XCTAssertEqual(hello, "hello#5")
        }
        XCTAssertEqual(fixture.roomSecrets.stored, [secret])
    }

    func testRoomSecretStoreFailureWithholdsTheAck() async throws {
        let fixture = makeFixture()
        fixture.roomSecrets.failWrites()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 4)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#4", "the phone retries on its next connection")
        XCTAssertEqual(fixture.roomSecrets.stored, [])
    }

    func testRoomSecretIsNotStoredOnceThePairingIsBeingRemoved() async throws {
        let fixture = makeFixture()
        fixture.link.stopStoringRoomSecret()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 4)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#4", "no ack, so the phone does not register a verifier for it")
        XCTAssertEqual(fixture.roomSecrets.stored, [])
    }

    func testVersionBlockedPeerCannotStoreARoomSecret() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(.relayRoomSecret(Data(repeating: 7, count: 32)), requestID: 2)
        let reply = try await fixture.phone.next()
        XCTAssertEqual(reply, "error#2")
        XCTAssertEqual(fixture.roomSecrets.stored, [])
    }

    func testCompatibleHelloEmitsEnvelopeThenHelloCompleted() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "closed(dropped)"])
    }

    func testVersionBlockedPeerGetsErrorsAndNothingIsForwarded() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        let helloReply = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello#1")

        try await fixture.phone.send(.listSessions, requestID: 2)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#2")
        // Even ping is refused: a blocked peer is served nothing but a re-hello.
        try await fixture.phone.send(.ping, requestID: 3)
        let pingRefusal = try await fixture.phone.next()
        XCTAssertEqual(pingRefusal, "error#3")

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(9999)#1",
                                "helloCompleted(9999, blocked=true)",
                                "versionIncompatible",
                                "closed(dropped)"])
    }

    func testBlockedPeerIsUnblockedByALaterCompatibleHello() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        try await fixture.phone.send(Self.compatibleHello, requestID: 2)
        let helloReply = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello#2")
        try await fixture.phone.send(.ping, requestID: 3)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#3")

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(9999)#1",
                                "helloCompleted(9999, blocked=true)",
                                "versionIncompatible",
                                "handled hello(\(CompanionProtocolVersion.current))#2",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "handled ping#3",
                                "closed(dropped)"])
    }

    func testPushesToBlockedPeerAreDroppedButTheFarewellIsDelivered() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.incompatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.send(.sessions([]), requestID: nil)
        fixture.link.send(.sessions([]), requestID: nil)
        await fixture.link.sendFarewellAndClose()

        let frame = try await fixture.phone.next()
        XCTAssertEqual(frame, "unpaired")
        await fixture.phone.expectClosed()
    }

    func testEnvelopesAreForwardedInWireOrderAndClosedIsLast() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        try await fixture.phone.send(.listSessions, requestID: 2)
        try await fixture.phone.send(.ping, requestID: 3)
        try await fixture.phone.send(.stopSessionStream(streamID: 1))
        try await fixture.phone.send(.stopSessionStream(streamID: 2))
        // The two replies the link owes prove it has read that far.
        let helloReply = try await fixture.phone.next()
        let pong = try await fixture.phone.next()
        XCTAssertEqual(helloReply, "hello#1")
        XCTAssertEqual(pong, "pong#3")
        await fixture.phone.close()

        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "forwarded listSessions#2",
                                "handled ping#3",
                                "forwarded stopSessionStream(1)",
                                "forwarded stopSessionStream(2)",
                                "closed(dropped)"])
    }

    func testUndecodableFrameIsDroppedAndTheLinkKeepsGoing() async throws {
        let fixture = makeFixture()
        try await fixture.phone.sendRaw(Data("not json".utf8))
        try await fixture.phone.send(.ping, requestID: 1)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#1")
        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled ping#1", "closed(dropped)"])
    }

    func testSendsReachThePhoneInCallOrder() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.link.send(.pong, requestID: 10)
        fixture.link.send(.sessions([]), requestID: nil)
        fixture.link.send(.pong, requestID: 11)
        let first = try await fixture.phone.next()
        let second = try await fixture.phone.next()
        let third = try await fixture.phone.next()
        XCTAssertEqual([first, second, third], ["pong#10", "other", "pong#11"])
    }

    func testFarewellIsTheLastFrameAndThenTheConnectionCloses() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.send(.sessions([]), requestID: nil)
        await fixture.link.sendFarewellAndClose()

        let first = try await fixture.phone.next()
        let second = try await fixture.phone.next()
        XCTAssertEqual([first, second], ["other", "unpaired"])
        await fixture.phone.expectClosed()

        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events.last, "closed(locally)")
    }

    func testCloseEndsTheConnectionAndReportsALocalClose() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(.ping, requestID: 1)
        _ = try await fixture.phone.next()

        fixture.link.close()
        fixture.link.close()  // idempotent

        await fixture.phone.expectClosed()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNil(error, "a deliberate close is not a drop")
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled ping#1", "closed(locally)"])
    }

    func testCloseBeforeStartClosesTheTransport() async throws {
        let fixture = makeFixture(start: false)
        fixture.link.close()

        await fixture.phone.expectClosed()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNil(error)
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["closed(locally)"])
        // A late start() must not revive it.
        fixture.link.start()
        await fixture.phone.expectClosed()
    }

    func testRemoteCloseIsReportedAsADrop() async throws {
        let fixture = makeFixture()
        await fixture.phone.close()
        let link = fixture.link
        let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
            await link.waitUntilClosed()
        }
        XCTAssertNotNil(error, "the phone going away is a drop")
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["closed(dropped)"])
    }

    func testWaitUntilClosedReturnsImmediatelyOnceClosed() async throws {
        let fixture = makeFixture()
        XCTAssertFalse(fixture.link.isClosed)
        await fixture.phone.close()
        let link = fixture.link
        for _ in 0..<2 {
            let error = try await FrozenMainQueue.withFailsafe("waitUntilClosed") {
                await link.waitUntilClosed()
            }
            XCTAssertNotNil(error)
        }
        XCTAssertTrue(fixture.link.isClosed)
    }

    func testStreamAcksAreDeliveredWhileTheMainQueueIsFrozen() async throws {
        let fixture = makeFixture()
        let acks = LockedState(initialState: [String]())
        fixture.link.streamAcks.register(streamID: 7) { pts, depth in
            acks.withLock { $0.append("\(pts)/\(depth)") }
        }
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()

        try await FrozenMainQueue.run { _ in
            try await fixture.phone.send(.streamAck(streamID: 7, lastPTSMilliseconds: 1234, queueDepth: 2))
            // For a stream nobody registered: dropped, not an error.
            try await fixture.phone.send(.streamAck(streamID: 8, lastPTSMilliseconds: 1, queueDepth: 0))
            try await fixture.phone.send(.ping, requestID: 2)
            let pong = try await fixture.phone.next()
            XCTAssertEqual(pong, "pong#2")
            XCTAssertEqual(acks.withLock { $0 }, ["1234/2"])
        }

        fixture.link.streamAcks.unregister(streamID: 7)
        try await fixture.phone.send(.streamAck(streamID: 7, lastPTSMilliseconds: 9999, queueDepth: 0))
        try await fixture.phone.send(.ping, requestID: 3)
        _ = try await fixture.phone.next()
        XCTAssertEqual(acks.withLock { $0 }, ["1234/2"])
    }

    func testScrollWheelReportsAreRefusedWhileTheMainThreadIsBlocked() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.stall.setBlocked(true)

        try await fixture.phone.send(.reportScrollWheel(streamID: 1, up: true, lines: 3), requestID: 5)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#5")
        try await fixture.phone.send(.reportScrollWheel(streamID: 1, up: true, lines: 3))
        // A sync point: the link has read both reports before the stall ends.
        try await fixture.phone.send(.ping, requestID: 6)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#6")

        fixture.stall.setBlocked(false)
        try await fixture.phone.send(.reportScrollWheel(streamID: 1, up: false, lines: 1), requestID: 7)
        try await fixture.phone.send(.ping, requestID: 8)
        _ = try await fixture.phone.next()

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events.filter { $0.contains("reportScrollWheel") }, ["forwarded reportScrollWheel#7"])
    }

    func testKeysAndPastesAreRefusedWhileTheMainThreadIsBlocked() async throws {
        let fixture = makeFixture()
        try await fixture.phone.send(Self.compatibleHello, requestID: 1)
        _ = try await fixture.phone.next()
        fixture.stall.setBlocked(true)

        try await fixture.phone.send(Self.key("x"), requestID: 5)
        let refusal = try await fixture.phone.next()
        XCTAssertEqual(refusal, "error#5")
        // Sent without a request ID, as the phone normally sends them: dropped.
        try await fixture.phone.send(Self.key("y"))
        try await fixture.phone.send(.pasteText(sessionGuid: "g", text: "rm -rf /"))
        try await fixture.phone.send(.ping, requestID: 6)
        let pong = try await fixture.phone.next()
        XCTAssertEqual(pong, "pong#6")

        // Unblocked: input goes through again.
        fixture.stall.setBlocked(false)
        try await fixture.phone.send(Self.key("z"), requestID: 7)
        try await fixture.phone.send(.ping, requestID: 8)
        _ = try await fixture.phone.next()

        await fixture.phone.close()
        let events = try await allEventDescriptions(fixture.link)
        XCTAssertEqual(events, ["handled hello(\(CompanionProtocolVersion.current))#1",
                                "helloCompleted(\(CompanionProtocolVersion.current), blocked=false)",
                                "handled ping#6",
                                "forwarded sendKey#7",
                                "handled ping#8",
                                "closed(dropped)"],
                       "nothing typed during the block reaches the bridge")
    }
}
