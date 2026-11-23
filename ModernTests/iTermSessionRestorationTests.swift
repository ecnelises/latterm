//
//  iTermSessionRestorationTests.swift
//  iTerm2
//
//  Regression tests for issue 12866: after restart, a pane could relaunch in $HOME instead of
//  its saved working directory. Root cause: a session arrangement POD nested an NSMutableSet
//  (Automatic Profile Switching's "Overridden Fields"). The restorable-state graph store archives
//  PODs with secure coding (any class) but decodes them with a restricted basic-classes allowlist
//  that lacked NSSet, so the whole POD failed to decode and every key but the separately stored
//  Contents was dropped, leaving the session to launch fresh in $HOME.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSessionRestorationTests: XCTestCase {

    @MainActor
    func testUndoTerminationReattachesTheOriginalViewAndSession() throws {
        let fixture = TerminalWindowTestFixture()
        defer { fixture.close() }
        let session = fixture.addTab()
        let originalViewID = ObjectIdentifier(try XCTUnwrap(session.view))
        session.terminate()
        XCTAssertEqual(session.swiftState.viewAwaitingTerminationUndo.map(ObjectIdentifier.init), originalViewID)
        XCTAssertFalse(fixture.terminal.currentSession() === session)

        XCTAssertTrue(session.revive())
        iTermController.sharedInstance()?.removeSession(fromRestorableSessions: session)
        fixture.terminal.addRevivedSession(session)
        XCTAssertNil(session.swiftState.viewAwaitingTerminationUndo)
        XCTAssertTrue(fixture.terminal.currentSession() === session)
        let revivedView = try XCTUnwrap(session.view)
        XCTAssertEqual(ObjectIdentifier(revivedView), originalViewID)
        XCTAssertTrue(revivedView.window === fixture.window)
    }

    @MainActor
    func testAppKitResolvesTheSavedWindowRestorerAndReadsItsArchivedArrangement() throws {
        XCTAssertTrue(NSClassFromString("PseudoTerminalRestorer") === PseudoTerminalRestorer.self)
        let archive = NSKeyedArchiver(requiringSecureCoding: false)
        archive.encode(["Tab GUID": "tab"], forKey: kTerminalWindowStateRestorationWindowArrangementKey)
        archive.finishEncoding()
        let coder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        coder.requiresSecureCoding = false
        let state = PseudoTerminalState(coder: coder)
        XCTAssertTrue(state.coder === coder)
        XCTAssertEqual(state.arrangement?["Tab GUID"] as? String, "tab")
        coder.finishDecoding()
    }

    @MainActor
    func testDatabaseFinishingDuringFullscreenWaitsForTheLastWindow() {
        let queue = WindowRestorationQueue()
        var events: [String] = []
        queue.enqueue {
            events.append("fullscreen")
            queue.pauseForFullscreen()
            queue.drain()
        }
        queue.enqueue { events.append("window") }
        queue.afterRestoration { events.append("post") }
        queue.drain()
        queue.externalRestorationFinished()
        queue.afterWindows { events.append("after windows") }
        XCTAssertEqual(events, ["fullscreen"])
        queue.fullscreenFinished()
        queue.externalRestorationFinished()
        XCTAssertEqual(events, ["fullscreen", "window", "after windows", "post"])
    }

    @MainActor
    func testLastFullscreenWindowAndReentrantPostRestorationCallbacks() {
        let queue = WindowRestorationQueue()
        var events: [Int] = []
        queue.enqueue { queue.pauseForFullscreen() }
        queue.afterRestoration {
            events.append(1)
            queue.afterRestoration { events.append(3) }
            queue.externalRestorationFinished()
        }
        queue.afterRestoration { events.append(2) }
        queue.drain()
        queue.externalRestorationFinished()
        XCTAssertTrue(events.isEmpty)
        queue.fullscreenFinished()
        queue.afterRestoration { events.append(4) }
        XCTAssertEqual(events, [1, 2, 3, 4])
    }

    @MainActor
    func testSynchronousResumeDoesNotRepeatTheCurrentWindow() {
        let queue = WindowRestorationQueue()
        var events: [Int] = []
        queue.enqueue {
            events.append(1)
            queue.pauseForFullscreen()
            queue.fullscreenFinished()
        }
        queue.enqueue { events.append(2) }
        queue.afterRestoration { events.append(3) }
        queue.drain()
        XCTAssertEqual(events, [1, 2])
        queue.externalRestorationFinished()
        XCTAssertEqual(events, [1, 2, 3])
    }

    func testTerminalRestoresModifierLevelWithoutOverwritingKittyFlags() {
        let terminal = VT100Terminal()
        var state = terminal.stateDictionary!
        state["Send Modifiers"] = [-1, -1, -1, -1, 2]
        state["Key Reporting Flags"] = 1
        terminal.setStateFrom(state)
        XCTAssertEqual(terminal.sendModifiers[4] as? Int, 2)
        XCTAssertEqual(terminal.keyReportingFlags.rawValue, 1)
        let restored = VT100Terminal()
        restored.setStateFrom(terminal.stateDictionary)
        XCTAssertEqual(restored.sendModifiers[4] as? Int, 2)
        XCTAssertEqual(restored.keyReportingFlags.rawValue, 1)
    }

    func testTerminalPadsLegacyModifierState() {
        let terminal = VT100Terminal()
        var state = terminal.stateDictionary!
        state["Send Modifiers"] = [1, 2]
        terminal.setStateFrom(state)
        XCTAssertEqual(terminal.sendModifiers.count, 5)
        XCTAssertEqual(terminal.sendModifiers[0] as? Int, 1)
        XCTAssertEqual(terminal.sendModifiers[4] as? Int, -1)
    }

    // The reader fix: a node POD that nests an NSSet must survive the exact archive/unarchive
    // round trip the graph store uses (-[iTermEncoderGraphRecord data] to write,
    // it_unarchivedObjectOfBasicClasses to read). Before adding NSSet to the decode allowlist,
    // the read returned nil and the entire POD was lost.
    func testGraphPODWithNestedNSSetSurvivesRoundTrip() throws {
        // Mimics the real shape: a session dict whose APS state holds a set of overridden fields.
        let pod: [String: Any] = [
            "Working Directory": "/Users/nickka/work",
            "Automatic Profile Switching": [
                "Profile Stack": [
                    ["Overridden Fields": NSMutableSet(array: ["Name", "Command"])]
                ]
            ]
        ]
        // -data archives with requiresSecureCoding == YES, exactly as the graph store persists PODs.
        let data = iTermEncoderGraphRecord.withPODs(pod,
                                                    graphs: [],
                                                    generation: 1,
                                                    key: "Session",
                                                    identifier: "",
                                                    rowid: nil).data

        let restored = try XCTUnwrap((try? (data as NSData).it_unarchivedObjectOfBasicClasses()) as? [String: Any],
                                     "Basic-classes decode dropped the POD; NSSet must be in the allowlist")
        XCTAssertEqual(restored as NSDictionary, pod as NSDictionary)
    }

    // The writer fix: iTermSavedProfile must serialize overridden fields as a plist/allowlist-safe
    // array (never an NSSet) so it can't poison the arrangement, while still round tripping back to
    // a set.
    func testSavedProfileSerializesOverriddenFieldsAsArray() {
        let saved = iTermSavedProfile()
        saved.profile = ["Name": "Work"]
        saved.originalProfile = ["Name": "Work"]
        saved.overriddenFields = NSMutableSet(array: ["Name", "Command"])

        let state = saved.savedState()

        // The serialized value must be a plain array, not a set.
        let fields = state["Overridden Fields"]
        XCTAssertTrue(fields is [Any], "Expected an array, got \(String(describing: fields))")
        XCTAssertFalse(fields is NSSet)

        // It round trips back to the original set.
        let restored = iTermSavedProfile(savedState: state)
        XCTAssertEqual(restored.overriddenFields, NSMutableSet(array: ["Name", "Command"]))
    }

    // Backward compatibility: state written by an older build still held an NSSet. It must still load.
    func testSavedProfileLoadsLegacySetForm() {
        let legacy: [String: Any] = [
            "Profile": ["Name": "Work"],
            "Original Profile": ["Name": "Work"],
            "Overridden Fields": NSMutableSet(array: ["Name", "Command"])
        ]
        let restored = iTermSavedProfile(savedState: legacy)
        XCTAssertEqual(restored.overriddenFields, NSMutableSet(array: ["Name", "Command"]))
    }
}

extension iTermSessionRestorationTests {
    // The collector passes attachment objects through by identity. It never starts a job.
    private final class Attachment: NSObject, iTermPartialAttachment {
        var partialResult: iTermJobManagerPartialResult!
        var jobManager: iTermJobManager!
        var queue: DispatchQueue!
    }

    private final class JobResult: NSObject, iTermJobManagerPartialResult {}

    private final class ReconnectingManager: iTermMultiServerJobManager {
        var socketNumber: Int32?
        var pid: NSNumber?
        var reply: ((iTermJobManagerPartialResult) -> Void)?

        override func asyncPartialAttach(toServer connection: iTermGeneralServerConnection, withProcessID pid: NSNumber,
                                         completion: @escaping (iTermJobManagerPartialResult) -> Void) {
            socketNumber = connection.multi.number
            self.pid = pid
            reply = completion
        }
    }

    func testJobAttachmentPreservesServerIdentifierManagerQueueAndResult() throws {
        let manager = ReconnectingManager()
        let result = JobResult()
        let identifier = ["Type": "multiserver", "Version": 1, "Socket": 3, "Child PID": 314] as [AnyHashable: Any]
        var requestedQueue: DispatchQueue?
        var received: RestorationAttachments?
        PTYSession.openJobAttachment(for: identifier, makeManager: { queue in
            requestedQueue = queue
            return manager
        }, completion: { received = $0 })
        XCTAssertNil(received)
        XCTAssertEqual(manager.socketNumber, 3)
        XCTAssertEqual(manager.pid, 314)
        let reply = try XCTUnwrap(manager.reply)
        manager.reply = nil
        reply(result)
        // Production uses the dictionary decoded from disk as an Objective-C dictionary key.
        let objcMap = try XCTUnwrap(received) as NSDictionary
        let restored = try XCTUnwrap(objcMap[identifier as NSDictionary] as? iTermPartialAttachment)
        XCTAssertTrue(restored.jobManager === manager)
        XCTAssertTrue(restored.partialResult === result)
        XCTAssertTrue(restored.queue === requestedQueue)
    }

    func testUnsupportedServerIdentifierCompletesWithoutOpeningAManager() {
        let identifier: [AnyHashable: Any] = ["Type": "multiserver", "Version": 100, "Socket": 3, "Child PID": 314]
        var calls = 0
        PTYSession.openJobAttachment(for: identifier, makeManager: { _ in
            XCTFail("An unsupported identifier must never open a connection")
            return nil
        }, completion: { results in
            XCTAssertTrue(results.isEmpty)
            calls += 1
        })
        XCTAssertEqual(calls, 1)
    }

    func testTimeoutDeliversOnlyReadyAttachmentsAndForwardsEveryLateTab() {
        let first = Attachment()
        let lateFirst = Attachment()
        let lateSecond = Attachment()
        let identifier: NSDictionary = ["pid": 1]
        var deliveries = [RestorationAttachments]()
        var orphans = [[iTermPartialAttachment]]()
        let batch = RestorationAttachmentBatch(count: 3, completion: { deliveries.append($0) },
                                                late: { orphans.append($0) })
        batch.receive([identifier: first])
        batch.finish() // deadline
        batch.receive([identifier: lateFirst])
        batch.receive([["pid": 2]: lateSecond])
        batch.finish() // all tabs eventually returned
        XCTAssertEqual(deliveries.count, 1)
        XCTAssertTrue(deliveries.first?[["pid": 1]] as? Attachment === first)
        XCTAssertEqual(orphans.count, 2)
        XCTAssertTrue(orphans.first?.first as? Attachment === lateFirst)
        XCTAssertTrue(orphans.last?.first as? Attachment === lateSecond)
    }

    func testAllTabsArriveBeforeDeadlineAndEqualIdentifiersMerge() {
        let first = Attachment()
        let replacement = Attachment()
        var deliveries = [RestorationAttachments]()
        let batch = RestorationAttachmentBatch(count: 2, completion: { deliveries.append($0) },
                                                late: { _ in XCTFail("No tab arrived late") })
        batch.receive([["pid": 1]: first])
        batch.receive([["pid": 1]: replacement, ["pid": 2]: first])
        XCTAssertEqual(deliveries.count, 1, "The last tab must finish restoration immediately")
        batch.finish()
        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(deliveries.first?.count, 2)
        XCTAssertTrue(deliveries.first?[["pid": 1]] as? Attachment === replacement)
    }

    func testLayoutsWithoutReattachableJobsCompleteOnMain() {
        let skipped = [TAB_ARRANGEMENT_SESSION: [SESSION_ARRANGEMENT_TMUX_PANE: 0]]
        let invalid = [TAB_ARRANGEMENT_SESSION: [SESSION_ARRANGEMENT_SERVER_DICT: ["type": "unknown"]]]
        let split: PTYTab.Arrangement = [TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SPLITTER, SUBVIEWS: [skipped, invalid]]
        let layouts: [PTYTab.Arrangement] = [[:], [TAB_ARRANGEMENT_ROOT: skipped], [TAB_ARRANGEMENT_ROOT: split]]
        let restored = expectation(description: "Every tab completes once")
        restored.expectedFulfillmentCount = layouts.count
        for layout in layouts {
            PTYTab.openPartialAttachments(forArrangement: layout) { results in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(results.isEmpty)
                restored.fulfill()
            }
        }
        wait(for: [restored], timeout: 5)
    }

    func testSessionMapRequiresEveryLeafAndSupportsLegacyIdentifiers() throws {
        let first = try XCTUnwrap(PTYSession(synthetic: true))
        let second = try XCTUnwrap(PTYSession(synthetic: true))
        func layout(_ ids: [PTYTab.Arrangement]) -> PTYTab.Arrangement {
            [TAB_ARRANGEMENT_ROOT: [TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SPLITTER, SUBVIEWS: ids]]
        }
        let legacy = [TAB_ARRANGEMENT_SESSION: [SESSION_UNIQUE_ID: first.guid]]
        let modern = [TAB_ARRANGEMENT_SESSION: [SESSION_ARRANGEMENT_GUID: second.guid]]
        let nested = [TAB_ARRANGEMENT_VIEW_TYPE: VIEW_TYPE_SPLITTER, SUBVIEWS: [legacy, modern]] as PTYTab.Arrangement
        let saved = layout([nested, legacy])
        let map = try XCTUnwrap(PTYTab.sessionMap(withArrangement: saved, sessions: [second, first, first]))
        XCTAssertEqual(map.count, 2)
        XCTAssertTrue(map[first.guid] === first)
        XCTAssertTrue(map[second.guid] === second)
        XCTAssertNil(PTYTab.sessionMap(withArrangement: saved, sessions: [first]))
        XCTAssertNil(PTYTab.sessionMap(withArrangement: layout([legacy, [:]]), sessions: [first]))
        XCTAssertNil(PTYTab.sessionMap(withArrangement: [:], sessions: [first]))
        XCTAssertNil(PTYSession.guid(inArrangement: [SESSION_ARRANGEMENT_GUID: 42]))
        XCTAssertEqual(PTYTab.sessionMap(withArrangement: layout([]), sessions: [first])?.count, 0)
    }

    func testRegistrationKeepsLatestContentsUntilStartupCleanup() {
        let id = UUID().uuidString
        let first: NSDictionary = ["generation": 1]
        let latest: NSDictionary = ["generation": 2]
        PTYSession.registerSession(inArrangement: [SESSION_ARRANGEMENT_GUID: id, SESSION_ARRANGEMENT_CONTENTS: first])
        XCTAssertEqual(PTYSession.registeredContents(forGUID: id), first)
        PTYSession.registerSession(inArrangement: [SESSION_ARRANGEMENT_GUID: id, SESSION_ARRANGEMENT_CONTENTS: latest])
        PTYSession.registerSession(inArrangement: [SESSION_ARRANGEMENT_GUID: id])
        XCTAssertEqual(PTYSession.registeredContents(forGUID: id), latest)
        PTYSession.removeAllRegisteredSessions()
        XCTAssertNil(PTYSession.registeredContents(forGUID: id))
    }
}
