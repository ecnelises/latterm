//
//  CompanionMessages.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  The terminal-control protocol spoken over the Noise-encrypted channel.
//

import Foundation
import CompanionProtocol

enum ForwardCompatibilityError: Error {
    case unknownCase
}

private struct CompanionDiscriminatorKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer {
    func decodeForwardCompatible<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        knownDiscriminators: Set<String>
    ) throws -> T {
        if let nested = try? nestedContainer(
            keyedBy: CompanionDiscriminatorKey.self,
            forKey: key),
           let discriminator = nested.allKeys.first?.stringValue,
           !knownDiscriminators.contains(discriminator) {
            throw ForwardCompatibilityError.unknownCase
        }
        return try decode(T.self, forKey: key)
    }
}

enum CompanionPushAuthorization: String, Codable {
    case notDetermined
    case denied
    case authorized
}
/// What a terminal session looks like on the wire. PTYSession itself cannot
/// cross, so this is the protocol's projection of one (used by the phone's
/// session picker).
public struct CompanionSessionSummary: Codable, Equatable, Hashable {
    public var guid: String
    public var name: String
    public var subtitle: String

    public init(guid: String, name: String, subtitle: String) {
        self.guid = guid
        self.name = name
        self.subtitle = subtitle
    }
}

/// pane, with one more level under panes that host a peer group.
struct CompanionSessionTree: Codable, Equatable {
    struct Window: Codable, Equatable {
        var title: String
        var tabs: [Tab]
    }
    struct Tab: Codable, Equatable {
        var title: String
        var panes: [Pane]
    }
    struct Pane: Codable, Equatable {
        /// The session currently occupying the pane.
        var session: CompanionSessionSummary
        /// All members of the pane's peer group when it hosts more than one
        /// session (e.g. a workgroup's Code Review peer); empty otherwise.
        var peers: [Peer]
    }
    struct Peer: Codable, Equatable {
        /// The peer's role name, e.g. “Code Review”.
        var roleName: String
        var session: CompanionSessionSummary
    }
    var windows: [Window]
}

/// Geometry of a session's content, fetched before any pixels so the phone can
/// size its scrollable canvas and decide how many lines to request per tile.
struct CompanionSessionScreenInfo: Codable, Equatable {
    var guid: String
    var name: String
    /// Total renderable lines (scrollback plus screen).
    var lineCount: Int
    var columns: Int
    /// Width in Mac points of a rendered line image (includes side margins).
    var width: Double
    /// Height in Mac points of one line (the cell height).
    var lineHeight: Double
    /// The backing scale content is rendered at (Mac pixels per Mac point),
    /// so the phone can stop zooming at the bitmaps' native resolution.
    var scale: Double
}

/// One rendered slice of a session's content, as a bitmap.
struct CompanionSessionContent: Codable {
    var guid: String
    /// First line actually rendered (requests are clamped to valid lines).
    var firstLine: Int
    /// Number of lines actually rendered.
    var lineCount: Int
    var pngData: Data
}

/// A rendered scrollback tile addressed by absolute (overflow-adjusted) line,
/// plus the current availability window so the phone can size its history canvas
/// and resolve eviction races deterministically.
struct CompanionHistoryTile: Codable, Equatable {
    var streamID: UInt32
    var generationId: UInt32
    /// First absolute line actually rendered (clamped to what is available).
    var firstAbsLine: Int64
    /// Lines actually rendered (0 if the request was entirely evicted).
    var lineCount: Int
    /// Oldest available absolute line right now (== totalScrollbackOverflow).
    var windowFirstAbsLine: Int64
    /// Total available lines right now (scrollback + screen).
    var windowLineCount: Int
    var pngData: Data
}

/// A codec for a live session stream.
enum CompanionStreamCodec: String, Codable, Equatable {
    case hevc
    case h264
}

/// Phone-supplied parameters for a live session stream.
struct CompanionStreamParams: Codable, Equatable {
    /// Codecs the phone can decode, best first; the host picks the first it can
    /// produce.
    var supportedCodecs: [CompanionStreamCodec]
    /// Upper bound on frames per second the phone wants delivered.
    var maxFrameRate: Double
    /// Phone-permitted sustained bandwidth ceiling in bits per second (e.g.
    /// tighter on cellular); the host streams at the min of this and its own
    /// budget. nil means the phone imposes no limit.
    var maxBitrate: Int?
    /// Highest media-frame wire version the phone can decode. nil/absent means the
    /// phone predates versioned frames, so the host must emit version 1. The host
    /// emits min(this, its own current version), so an old phone keeps working
    /// (without per-frame geometry) and a new phone gets generationId/liveTop.
    var maxMediaFrameVersion: Int? = nil

    init(supportedCodecs: [CompanionStreamCodec],
         maxFrameRate: Double,
         maxBitrate: Int?,
         maxMediaFrameVersion: Int? = nil) {
        self.supportedCodecs = supportedCodecs
        self.maxFrameRate = maxFrameRate
        self.maxBitrate = maxBitrate
        self.maxMediaFrameVersion = maxMediaFrameVersion
    }
}

/// Reply to `.startSessionStream`: the stream is live with the negotiated codec.
struct CompanionStreamStarted: Codable, Equatable {
    var streamID: UInt32
    var codec: CompanionStreamCodec
}

/// The fixed (per-generation) screen geometry needed to map a touch on the
/// encoded image to a terminal cell, all in ENCODED PIXELS (the units of
/// pixelWidth/pixelHeight), so the phone works entirely in image space:
///   column = floor((imageX - leftMargin) / cellWidth)
///   row    = floor((imageY - topMargin)  / cellHeight)
/// Margins are 0 today (the stream renders without margins) but are carried so
/// the transform stays correct if that changes. This changes only on a
/// resize/font/scale change, so it rides streamConfig with the generationId; the
/// per-frame top line (liveTop) rides the media-frame header instead.
struct CompanionCellGeometry: Codable, Equatable {
    var cellWidth: Double
    var cellHeight: Double
    var leftMargin: Double
    var topMargin: Double
}

/// A point in absolute terminal coordinates, computed by the phone from a touch
/// using the stream geometry: column is a 0-based cell, absLine is the
/// overflow-adjusted absolute line (so it stays valid as scrollback grows). The
/// host maps it to a VT100GridAbsCoord to drive the real selection.
struct CompanionSelectionPoint: Codable, Equatable {
    var absLine: Int64
    var column: Int
}

/// The current selection's span in absolute terminal coordinates, reported by the
/// host so the phone can draw draggable handles at the endpoints. start is the
/// earlier coordinate, end the later one.
struct CompanionSelectionRange: Codable, Equatable {
    var start: CompanionSelectionPoint
    var end: CompanionSelectionPoint
}

/// Phase of a phone-driven selection drag.
enum CompanionSelectionPhase: String, Codable, Equatable {
    case begin
    case move
    case end
}

/// How a selection snaps. character = exact cells; word/line/smart match the
/// Mac's double/triple/smart selection. Only meaningful on `.begin`.
enum CompanionSelectionMode: String, Codable, Equatable {
    case character
    case word
    case line
    case smart
}

/// Modifiers held while a companion key event is delivered. leftOption and
/// rightOption are kept distinct (rather than a single "option" flag) so the mac
/// can apply the profile's per-side Option behavior (Normal / Meta / Esc+);
/// control and shift map to the usual terminal encodings. Modeled as explicit
/// booleans so the wire form is self-describing and Codable is trivial.
struct CompanionKeyModifiers: Codable, Equatable {
    var control = false
    var shift = false
    var leftOption = false
    var rightOption = false

    static let none = CompanionKeyModifiers()

    var isEmpty: Bool { !control && !shift && !leftOption && !rightOption }
}

/// A non-text key the phone can inject: keys that have no literal character (or
/// whose bytes depend on terminal mode) and so cannot ride the `.text` path. The
/// mac maps each to the same bytes a hardware press would produce, honoring the
/// session's cursor/keypad/key-reporting modes.
///
/// FORWARD-COMPAT: this is a string-raw-value enum nested inside a `sendKey`. The
/// envelope's unknown-message fallback (`decodeForwardCompatible` -> `.unsupported`)
/// only covers unknown TOP-LEVEL discriminators, so a NEW special key sent from a
/// future phone to a current mac fails to decode the whole `sendKey` and the host
/// drops it (no per-key gating below `keyInputRevision`). Before adding any case here,
/// bump `keyInputRevision` (or add a decode fallback) so the new phone can gate on it.
enum CompanionSpecialKey: String, Codable, Equatable {
    case escape
    case tab
    case backspace        // ^? / ^H per profile (the keyboard's delete-left)
    case forwardDelete    // the "del" / forward-delete key
    case up, down, left, right
    case home, end, pageUp, pageDown, insert
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
}

/// One key press to inject into a session, either a run of literal characters
/// (ordinary typing, sent as real keystrokes rather than a bracketed paste) or a
/// single named special key. `modifiers` applies to the whole event; for a `.text`
/// run it is normally empty (the soft keyboard already delivers shifted/composed
/// characters) and carries a modifier only for an armed dead-key.
struct CompanionKeyEvent: Codable, Equatable {
    enum Key: Codable, Equatable {
        case text(String)
        case special(CompanionSpecialKey)
    }
    var key: Key
    var modifiers: CompanionKeyModifiers

    init(key: Key, modifiers: CompanionKeyModifiers = .none) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// Decoder configuration for a live stream: the codec parameter sets plus the
/// pixel geometry of the encoded frames. Re-sent with a fresh generationId
/// whenever the geometry changes.
struct CompanionStreamConfig: Codable, Equatable {
    var streamID: UInt32
    /// Bumped on every geometry change; media frames carry the generation they
    /// were rendered at so the phone applies the matching configuration.
    var generationId: UInt32
    /// Codec parameter sets (hvcC for HEVC, avcC for H.264) for decoder setup.
    var codecExtradata: Data
    var pixelWidth: Int
    var pixelHeight: Int
    /// Render scale (encoded pixels per Mac point).
    var scale: Double
    var columns: Int
    var rows: Int
    /// Cell/margin geometry for touch-to-cell mapping. Optional: a host too old
    /// to send it (pre-geometry build) decodes as nil, and the phone keeps the
    /// video working but cannot offer selection.
    var cellGeometry: CompanionCellGeometry? = nil
    /// Oldest available absolute line (== totalScrollbackOverflow) at config time,
    /// so the phone can lay out the history canvas. Older hosts decode as 0.
    var firstAbsLine: Int64 = 0
    /// Total available lines (scrollback + screen) at config time.
    var totalLines: Int = 0
    /// Whether the session's window can currently be resized to an arbitrary grid,
    /// so the phone can disable its resize control when a resize would be ignored
    /// (full screen, maximized, edge-attached, or width-locked). Optional: a host
    /// predating the resize feature omits it and decodes as nil (the phone gates the
    /// control on the mac's protocol revision anyway).
    var canResize: Bool? = nil
    /// Whether the session is currently on its alternate screen buffer (a full-screen
    /// app like vim/less/htop is up). The phone hides the primary buffer's scrollback
    /// while this is true, showing only the mutable section (the alt grid == the live
    /// viewport). Rides the config so a change propagates even on an idle screen; older
    /// hosts omit it and decode as false (scrollback shown as before).
    var altScreen: Bool = false
    /// Whether the session currently reports mouse-wheel events to the program
    /// (mirrors -[PTYSession scrollWheelReportingEnabled]). Combined with altScreen,
    /// the phone translates a scroll gesture into a `reportScrollWheel` message instead
    /// of browsing scrollback. Older hosts omit it and decode as false.
    var scrollWheelReporting: Bool = false

    init(streamID: UInt32, generationId: UInt32, codecExtradata: Data,
         pixelWidth: Int, pixelHeight: Int, scale: Double, columns: Int, rows: Int,
         cellGeometry: CompanionCellGeometry? = nil, firstAbsLine: Int64 = 0, totalLines: Int = 0,
         canResize: Bool? = nil, altScreen: Bool = false, scrollWheelReporting: Bool = false) {
        self.streamID = streamID
        self.generationId = generationId
        self.codecExtradata = codecExtradata
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.columns = columns
        self.rows = rows
        self.cellGeometry = cellGeometry
        self.firstAbsLine = firstAbsLine
        self.totalLines = totalLines
        self.canResize = canResize
        self.altScreen = altScreen
        self.scrollWheelReporting = scrollWheelReporting
    }

    // Custom decode: synthesized Decodable ignores the property defaults and throws
    // keyNotFound for an absent key, so a host predating firstAbsLine/totalLines
    // (added without a revision bump) would make the whole config undecodable and
    // leave the decoder unconfigured (permanent black view + keyframe-request loop).
    // decodeIfPresent restores the "older hosts decode as 0" contract.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamID = try c.decode(UInt32.self, forKey: .streamID)
        generationId = try c.decode(UInt32.self, forKey: .generationId)
        codecExtradata = try c.decode(Data.self, forKey: .codecExtradata)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        scale = try c.decode(Double.self, forKey: .scale)
        columns = try c.decode(Int.self, forKey: .columns)
        rows = try c.decode(Int.self, forKey: .rows)
        cellGeometry = try c.decodeIfPresent(CompanionCellGeometry.self, forKey: .cellGeometry)
        firstAbsLine = try c.decodeIfPresent(Int64.self, forKey: .firstAbsLine) ?? 0
        totalLines = try c.decodeIfPresent(Int.self, forKey: .totalLines) ?? 0
        canResize = try c.decodeIfPresent(Bool.self, forKey: .canResize)
        altScreen = try c.decodeIfPresent(Bool.self, forKey: .altScreen) ?? false
        scrollWheelReporting = try c.decodeIfPresent(Bool.self, forKey: .scrollWheelReporting) ?? false
    }
}

/// Why a live stream ended.
enum CompanionStreamEndReason: String, Codable, Equatable {
    case stoppedByClient
    case sessionClosed
    case superseded
    case error
    /// The host paused the stream to stay within the relay's data budget.
    case dataLimitReached
}

/// Sent by the phone (client) to the mac (host).
enum CompanionClientMessage: Codable, CompanionMessagePayload {
    case unsupported
    case hello(revision: Int, minimumPeer: Int)
    case listSessions
    case fetchSessionScreenInfo(sessionGuid: String)
    case fetchSessionContent(sessionGuid: String, firstLine: Int, lineCount: Int)
    case fetchHistoryTile(streamID: UInt32, firstAbsLine: Int64, lineCount: Int, generationId: UInt32)
    case fetchSessionTree
    case ping
    case relayRoomSecret(Data)
    case unpairing
    case startSessionStream(sessionGuid: String, params: CompanionStreamParams)
    case stopSessionStream(streamID: UInt32)
    case requestKeyframe(streamID: UInt32)
    case updateStreamParams(streamID: UInt32, params: CompanionStreamParams)
    case streamAck(streamID: UInt32, lastPTSMilliseconds: UInt64, queueDepth: Int)
    case reportScrollWheel(streamID: UInt32, up: Bool, lines: Int)
    case selectionGesture(streamID: UInt32,
                          phase: CompanionSelectionPhase,
                          mode: CompanionSelectionMode,
                          point: CompanionSelectionPoint)
    case clearSelection(streamID: UInt32)
    case copySelection(sessionGuid: String)
    case selectAllInStream(streamID: UInt32)
    case pasteText(sessionGuid: String, text: String)
    case sendKey(sessionGuid: String, event: CompanionKeyEvent)
    case resizeSession(sessionGuid: String, columns: Int, rows: Int)

    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "listSessions",
        "fetchSessionScreenInfo", "fetchSessionContent", "fetchHistoryTile",
        "fetchSessionTree", "ping", "relayRoomSecret", "unpairing",
        "startSessionStream", "stopSessionStream", "requestKeyframe",
        "updateStreamParams", "streamAck", "reportScrollWheel",
        "selectionGesture", "clearSelection", "copySelection",
        "selectAllInStream", "pasteText", "sendKey", "resizeSession",
    ]
}
/// Sent by the mac (host) to the phone (client). Either a reply correlated to a
/// client requestID (carried by the envelope) or an unsolicited event with no
/// requestID (a subscription delivery).
enum CompanionHostMessage: Codable, CompanionMessagePayload {
    case unsupported
    case hello(revision: Int, minimumPeer: Int)
    case sessions([CompanionSessionSummary])
    case sessionScreenInfo(CompanionSessionScreenInfo)
    case sessionContent(CompanionSessionContent)
    case historyTile(CompanionHistoryTile)
    case sessionTree(CompanionSessionTree)
    case pong
    case relayRoomSecretStored
    case unpaired
    case error(CompanionError)
    case streamStarted(CompanionStreamStarted)
    case streamConfig(CompanionStreamConfig)
    case streamEnded(streamID: UInt32, reason: CompanionStreamEndReason)
    case streamExtent(streamID: UInt32, firstAbsLine: Int64, totalLines: Int)
    case selectionText(text: String)
    case selectionRange(streamID: UInt32, range: CompanionSelectionRange?)

    static let knownPayloadKeys: Set<String> = [
        "unsupported", "hello", "sessions", "sessionScreenInfo",
        "sessionContent", "historyTile", "sessionTree", "pong",
        "relayRoomSecretStored", "unpaired", "error", "streamStarted",
        "streamConfig", "streamEnded", "streamExtent", "selectionText",
        "selectionRange",
    ]
}
/// The framed envelope every application message travels in. `requestID`
/// correlates a host reply with the client message that triggered it; it is nil
/// for unsolicited host events (deliveries, typing status).
/// A companion message that can represent "a message type this build does not
/// recognize." Lets CompanionEnvelope decode a newer peer's unknown message type
/// into a sentinel (preserving requestID) instead of failing the whole decode -
/// Swift's synthesized enum Codable throws on an unknown case, which would
/// otherwise make one new message type break an older peer entirely.
protocol CompanionMessagePayload: Codable {
    static var unsupported: Self { get }
    /// The discriminator keys (case names) this build recognizes. Synthesized
    /// enum Codable encodes a case as {"<caseName>": ...}; the envelope decoder
    /// maps an UNKNOWN discriminator to `.unsupported` (forward compatibility) but
    /// lets a decode failure of a KNOWN case propagate (a corrupt or newer-content
    /// body must not be masked as "unsupported"). Keep in sync with the cases.
    static var knownPayloadKeys: Set<String> { get }
}

struct CompanionEnvelope<Payload: CompanionMessagePayload>: Codable {
    var requestID: UInt64?
    var payload: Payload

    init(requestID: UInt64?, payload: Payload) {
        self.requestID = requestID
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey { case requestID, payload }

    // Custom decode for forward compatibility - but ONLY for a genuinely unknown
    // message TYPE. decodeForwardCompatible peeks the payload's discriminator: an
    // unknown case (a newer peer's new message type) throws
    // ForwardCompatibilityError.unknownCase, which we turn into `.unsupported`
    // with the requestID intact instead of failing the frame. A KNOWN case whose
    // body fails to decode (malformed, or a newer-content body) throws a
    // DecodingError that propagates to the read loop's drop-and-log path - a
    // blanket `try?` here would instead mask it as "unsupported", turning one bad
    // message into a failed reply (or a spurious "upgrade required"). Encoding
    // stays synthesized. (Shared with Message/ClientLocal; see
    // KeyedDecodingContainer.decodeForwardCompatible.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decodeIfPresent(UInt64.self, forKey: .requestID)
        do {
            payload = try container.decodeForwardCompatible(Payload.self, forKey: .payload,
                                                            knownDiscriminators: Payload.knownPayloadKeys)
        } catch ForwardCompatibilityError.unknownCase {
            payload = .unsupported
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requestID, forKey: .requestID)
        try container.encode(payload, forKey: .payload)
    }
}

typealias ClientEnvelope = CompanionEnvelope<CompanionClientMessage>
typealias HostEnvelope = CompanionEnvelope<CompanionHostMessage>
