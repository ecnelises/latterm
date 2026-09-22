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
