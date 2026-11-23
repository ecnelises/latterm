//
//  iTermPTYTabRecursiveRestoreSplittersTests.swift
//  ModernTests
//
//  Characterization tests for the recursive tree-build that turns an
//  arrangement dictionary into a live NSSplitView/SessionView
//  hierarchy. The implementation lives in
//  iTermSplitTreeRebuilder.buildSplitterTree (Swift, since the port);
//  PTYTab._recursiveRestoreSplitters is a thin ObjC shim that delegates
//  to the same code path.
//
//  These tests act as a regression safety net for the leaf-resolver
//  generalization and any future refactoring of the rebuild logic.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermPTYTabRecursiveRestoreSplittersTests: XCTestCase {

    // MARK: - Arrangement key constants
    //
    // These mirror the file-static keys in PTYTab.m. The on-disk arrangement
    // format is stable, so duplicating them as literals here is acceptable.

    private let kViewType         = "View Type"
    private let kSplitter         = "Splitter"
    private let kSessionView      = "SessionView"
    private let kSubviews         = "Subviews"
    private let kIsVertical       = "isVertical"
    private let kFrame            = "frame"
    private let kSplitterID       = "Splitter ID"
    private let kTmuxWindowPane   = "tmux window pane"
    private let kArrangementID    = "ID"

    private let kFrameX           = "x"
    private let kFrameY           = "y"
    private let kFrameWidth       = "width"
    private let kFrameHeight      = "height"

    // MARK: - Arrangement builders

    private func frameDict(_ rect: NSRect) -> [String: Any] {
        return [
            kFrameX:      rect.origin.x,
            kFrameY:      rect.origin.y,
            kFrameWidth:  rect.size.width,
            kFrameHeight: rect.size.height,
        ]
    }

    private func leaf(frame: NSRect,
                      tmuxPane: Int? = nil,
                      arrangementID: Int? = nil) -> [String: Any] {
        var d: [String: Any] = [
            kViewType: kSessionView,
            kFrame:    frameDict(frame),
        ]
        if let tmuxPane = tmuxPane {
            d[kTmuxWindowPane] = tmuxPane
        }
        if let arrangementID = arrangementID {
            d[kArrangementID] = arrangementID
        }
        return d
    }

    private func splitter(vertical: Bool,
                          frame: NSRect,
                          children: [[String: Any]],
                          splitterID: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            kViewType:    kSplitter,
            kIsVertical:  vertical,
            kFrame:       frameDict(frame),
            kSubviews:    children,
        ]
        if let splitterID = splitterID {
            d[kSplitterID] = splitterID
        }
        return d
    }

    // MARK: - Tests

    func testLiveAndMaximizedLayoutsEncodeTheSameHierarchy() throws {
        let frame = NSRect(x: 10, y: 20, width: 320, height: 180)
        let root = NSSplitView(frame: frame)
        let inner = try XCTUnwrap(PTYSplitView(frame: root.bounds, uniqueIdentifier: "inner"))
        inner.isVertical = true
        let sessions = try (0..<3).map { _ in try XCTUnwrap(PTYSession(synthetic: false)) }
        let mapping = NSMapTable<SessionView, PTYSession>.strongToStrongObjects()
        for (index, session) in sessions.enumerated() {
            let pane = SessionView(frame: frame)
            session.view = pane
            mapping.setObject(session, forKey: pane)
            (index == 0 ? root : inner).addSubview(pane)
        }
        root.addSubview(inner)
        let tab = try XCTUnwrap(PTYTab(root: root, sessions: mapping))
        tab.activeSession = sessions[2]
        let live = try XCTUnwrap(tab.arrangement())
        for session in sessions {
            XCTAssertNotNil(PTYTab.arrangement(forSessionWithGUID: session.guid, in: live))
        }
        let adapter = iTermMutableDictionaryEncoderAdapter.encoder()
        let ids = NSMutableDictionary()
        XCTAssertTrue(PTYTab.encodeLayout(withContents: false, constructIDMap: true, encoder: adapter,
                                          options: nil, activeSession: tab.activeSession, tabGUID: "tab",
                                          titleOverride: "Work", isMaximized: false, savedArrangement: nil,
                                          idMap: ids, root: root, sessionViewFinder: { _ in nil },
                                          sessionFinder: { mapping.object(forKey: $0) }))
        let saved = try XCTUnwrap(adapter.mutableDictionary as? PTYTab.Arrangement)
        XCTAssertEqual(saved["Title Override"] as? String, "Work")
        let layout = try XCTUnwrap(saved["Root"] as? PTYTab.Arrangement)
        let children = try XCTUnwrap(layout[kSubviews] as? [PTYTab.Arrangement])
        XCTAssertEqual(children.count, 2)
        let column = try XCTUnwrap(children.last)
        XCTAssertEqual(column[kSplitterID] as? String, "inner")
        XCTAssertEqual(column[kIsVertical] as? Bool, true)
        let leaves = [try XCTUnwrap(children.first)] + (try XCTUnwrap(column[kSubviews] as? [PTYTab.Arrangement]))
        XCTAssertEqual(leaves.compactMap { $0["ID"] as? Int }, [0, 1, 2])
        XCTAssertEqual(leaves.compactMap { $0["Is Active"] as? Bool }, [false, false, true])
        for (index, session) in sessions.enumerated() {
            XCTAssertTrue(ids[index] as? SessionView === session.view)
            let pane = try XCTUnwrap(session.view)
            XCTAssertEqual(pane.savedSize, pane.frame.size)
        }

        // Saved geometry survives a resize while session contents reflect the current session.
        root.frame.size.width += 100
        let newGUID = UUID().uuidString
        sessions[2].setValue(newGUID, forKey: "guid")
        let graph = iTermGraphEncoder(key: "tab", identifier: "tab", generation: 1)
        XCTAssertTrue(PTYTab.encodeLayout(withContents: false, constructIDMap: false,
                                          encoder: iTermGraphEncoderAdapter(graphEncoder: graph), options: nil,
                                          activeSession: tab.activeSession, tabGUID: "tab", titleOverride: nil,
                                          isMaximized: true, savedArrangement: saved, idMap: ids, root: nil,
                                          sessionViewFinder: { _ in nil }, sessionFinder: { mapping.object(forKey: $0) }))
        let maximized = try XCTUnwrap(graph.record?.propertyListValue as? PTYTab.Arrangement)
        let restored = try XCTUnwrap(maximized["Root"] as? PTYTab.Arrangement)
        XCTAssertEqual(restored["Maximized"] as? Bool, true)
        XCTAssertEqual(restored[kFrame] as? [String: CGFloat], layout[kFrame] as? [String: CGFloat])
        XCTAssertNotNil(PTYTab.arrangement(forSessionWithGUID: newGUID, in: maximized))
        XCTAssertNil(layout["Maximized"])

        ids.removeObject(forKey: 1)
        let incomplete = iTermMutableDictionaryEncoderAdapter.encoder()
        XCTAssertFalse(PTYTab.encodeLayout(withContents: false, constructIDMap: false, encoder: incomplete,
                                           options: nil, activeSession: nil, tabGUID: "tab", titleOverride: nil,
                                           isMaximized: true, savedArrangement: saved, idMap: ids, root: nil,
                                           sessionViewFinder: { _ in nil }, sessionFinder: { mapping.object(forKey: $0) }))
        XCTAssertNil(incomplete.mutableDictionary["Root"])
    }

    func testMissingLiveSessionRollsBackRootAndPaneIDMap() throws {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let root = try XCTUnwrap(PTYSplitView(frame: frame, uniqueIdentifier: "root"))
        let nested = try XCTUnwrap(PTYSplitView(frame: frame, uniqueIdentifier: "nested"))
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let pane = SessionView(frame: frame)
        session.view = pane
        root.addSubview(pane)
        root.addSubview(nested)
        nested.addSubview(SessionView(frame: frame))
        let adapter = iTermMutableDictionaryEncoderAdapter.encoder()
        let ids = NSMutableDictionary()
        XCTAssertFalse(PTYTab.encodeLayout(withContents: false, constructIDMap: true, encoder: adapter,
                                           options: nil, activeSession: session, tabGUID: "tab", titleOverride: nil,
                                           isMaximized: false, savedArrangement: nil, idMap: ids, root: root,
                                           sessionViewFinder: { _ in nil }, sessionFinder: { $0 === pane ? session : nil }))
        XCTAssertNil(adapter.mutableDictionary["Root"])
        XCTAssertEqual(ids.count, 0)
    }

    func testStandaloneArchiveLeavesPaneInItsOriginalContainer() throws {
        final class Pane: SessionView {
            var moves = 0
            override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                moves += 1
            }
        }

        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let pane = try XCTUnwrap(Pane(frame: NSRect(x: 15, y: 20, width: 120, height: 80)))
        session.view = pane
        let parent = NSView()
        parent.addSubview(NSView())
        parent.addSubview(pane)
        let moves = pane.moves
        let originalFrame = pane.frame
        let adapter = iTermMutableDictionaryEncoderAdapter.encoder()
        XCTAssertTrue(PTYTab.encodeStandaloneArchive(for: session, tabGUID: "tab", encoder: adapter,
                                                      options: [PTYTabArrangementOptionsReplacementProfile: ["archive": true]]))
        let root = try XCTUnwrap(adapter.mutableDictionary["Root"] as? PTYTab.Arrangement)
        let children = try XCTUnwrap(root[kSubviews] as? [PTYTab.Arrangement])
        XCTAssertEqual(children.count, 1)
        let leaf = try XCTUnwrap(children.first)
        XCTAssertEqual(leaf["Is Active"] as? Bool, true)
        let archived = try XCTUnwrap(leaf["Session"] as? PTYTab.Arrangement)
        XCTAssertEqual(archived["Bookmark"] as? [String: Bool], ["archive": true])
        XCTAssertEqual(PTYSession.guid(inArrangement: archived), session.guid)
        XCTAssertEqual(pane.moves, moves)
        XCTAssertTrue(parent.subviews.last === pane)
        XCTAssertEqual(pane.frame, originalFrame)
    }

    func testNestedSessionLookupAndRepairPreserveSavedLayout() throws {
        let first = ["Session": ["Session Unique ID": "legacy", "Working Directory": "/old"]]
        let target = ["Session": ["Session GUID": "target", "Working Directory": "/old"]]
        let nested: PTYTab.Arrangement = [kViewType: kSplitter, kSubviews: [target, first], "weight": 2]
        let root: PTYTab.Arrangement = [kViewType: kSplitter, kSubviews: [first, nested]]
        let saved: PTYTab.Arrangement = ["Root": root, "Tab GUID": "tab"]

        var visited: [String] = []
        XCTAssertTrue(PTYTab.arrangement(saved) { session in
            let guid = PTYSession.guid(inArrangement: session) ?? ""
            visited.append(guid)
            return guid == "target"
        })
        XCTAssertEqual(visited, ["legacy", "target"])

        let repaired = PTYTab.repairedArrangement(saved, replacingOldCWDOfSessionWithGUID: "target", withOldCWD: "/new")
        XCTAssertEqual(PTYTab.arrangement(forSessionWithGUID: "target", in: repaired)?["Working Directory"] as? String, "/new")
        XCTAssertEqual(PTYTab.arrangement(forSessionWithGUID: "legacy", in: repaired)?["Working Directory"] as? String, "/old")
        XCTAssertEqual(PTYTab.arrangement(forSessionWithGUID: "target", in: saved)?["Working Directory"] as? String, "/old")
        XCTAssertNil(PTYTab.arrangement(forSessionWithGUID: "missing", in: repaired))
        let newRoot = try XCTUnwrap(repaired["Root"] as? PTYTab.Arrangement)
        let children = try XCTUnwrap(newRoot[kSubviews] as? [PTYTab.Arrangement])
        XCTAssertEqual(children.last?["weight"] as? Int, 2)
        XCTAssertEqual(repaired["Tab GUID"] as? String, "tab")
    }

    func testWindowProfileRepairUpdatesOnlyMatchingSavedSessions() throws {
        let profiles = ["old", "keep"].map { guid in
            ["Session": ["Session GUID": guid, "Bookmark": [KEY_GUID: guid]]]
        }
        let tab: PTYTab.Arrangement = ["Root": [kViewType: kSplitter, kSubviews: profiles]]
        let window: PTYTab.Arrangement = ["Tabs": [tab]]
        let repaired = try XCTUnwrap(PseudoTerminal.repairedArrangement(window, replacingProfileWithGUID: "old",
                                                                         withProfile: [KEY_GUID: "new"]))
        let tabs = try XCTUnwrap(repaired["Tabs"] as? [PTYTab.Arrangement])
        let repairedTab = try XCTUnwrap(tabs.first)
        for (sessionGUID, expectedProfileGUID) in [("old", "new"), ("keep", "keep")] {
            let session = try XCTUnwrap(PTYTab.arrangement(forSessionWithGUID: sessionGUID, in: repairedTab))
            let profile = try XCTUnwrap(session["Bookmark"] as? [String: String])
            XCTAssertEqual(profile[KEY_GUID], expectedProfileGUID)
        }
    }

    /// With nil idMap and sessionMap, every leaf becomes a fresh SessionView
    /// and every splitter node becomes an NSSplitView with the right vertical flag.
    func testNoMapsGeneratesFreshLeavesAndCorrectShape() {
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 100)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement,
            idMap: nil,
            sessionMap: nil,
            revivedSessions: nil)

        guard let split = view as? NSSplitView else {
            XCTFail("expected NSSplitView, got \(type(of: view))")
            return
        }
        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.subviews.count, 2)
        XCTAssertTrue(split.subviews[0] is SessionView,
                      "expected leaf to be SessionView")
        XCTAssertTrue(split.subviews[1] is SessionView)
    }

    /// Horizontal splitter sets isVertical=false on the produced NSSplitView.
    func testHorizontalSplitterProducesNonVerticalSplit() {
        let arrangement = splitter(
            vertical: false,
            frame: NSRect(x: 0, y: 0, width: 100, height: 200),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 0, y: 100, width: 100, height: 100)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let split = view as! NSSplitView
        XCTAssertFalse(split.isVertical)
    }

    /// Nested mixed-orientation splitters produce the right hierarchy:
    /// V[ leaf, H[leaf, leaf] ]
    func testNestedMixedOrientationShape() {
        let inner = splitter(
            vertical: false,
            frame: NSRect(x: 100, y: 0, width: 100, height: 100),
            children: [
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 50)),
                leaf(frame: NSRect(x: 100, y: 50, width: 100, height: 50)),
            ])
        let outer = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                inner,
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: outer, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let outerSplit = view as! NSSplitView
        XCTAssertTrue(outerSplit.isVertical)
        XCTAssertEqual(outerSplit.subviews.count, 2)
        XCTAssertTrue(outerSplit.subviews[0] is SessionView)

        let innerSplit = outerSplit.subviews[1] as! NSSplitView
        XCTAssertFalse(innerSplit.isVertical)
        XCTAssertEqual(innerSplit.subviews.count, 2)
        XCTAssertTrue(innerSplit.subviews[0] is SessionView)
        XCTAssertTrue(innerSplit.subviews[1] is SessionView)
    }

    /// A leaf whose tmux pane key is in idMap recycles the existing
    /// SessionView (same identity), and resets its frame to the arrangement's.
    func testRecycleViaTmuxPaneKey() {
        let recycled = SessionView(frame: NSRect(x: 999, y: 999, width: 10, height: 10))
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 42): recycled]

        let leafFrame = NSRect(x: 0, y: 0, width: 100, height: 50)
        let arrangement = leaf(frame: leafFrame, tmuxPane: 42)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil)

        XCTAssertTrue(view === recycled,
                      "expected the same SessionView instance to be recycled")
        XCTAssertEqual((view as! SessionView).frame, leafFrame,
                       "recycled view's frame should be reset to the arrangement frame")
    }

    /// A leaf whose tmux pane key is NOT in idMap produces a fresh SessionView.
    func testFreshLeafWhenTmuxPaneNotInIdMap() {
        let other = SessionView(frame: NSRect(x: 999, y: 999, width: 10, height: 10))
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 7): other]

        let leafFrame = NSRect(x: 0, y: 0, width: 80, height: 40)
        let arrangement = leaf(frame: leafFrame, tmuxPane: 42)  // not 7

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil)

        XCTAssertFalse(view === other, "should not recycle the unrelated SessionView")
        XCTAssertTrue(view is SessionView)
        XCTAssertEqual((view as! SessionView).frame, leafFrame)
    }

    /// When an arrangementID match exists in idMap (the maximize-restoration
    /// path), that SessionView is returned. The arrangement-ID lookup short-
    /// circuits before the tmux-pane lookup, so the leaf's frame is preserved
    /// via restoreFrameSize rather than being overwritten from the
    /// arrangement frame.
    func testRecycleViaArrangementID() {
        let recycled = SessionView(frame: NSRect(x: 5, y: 5, width: 50, height: 25))
        // TAB_ARRANGEMENT_ID values are NSNumber (assigned via idMap.count
        // when encoding for maximize). The dict is keyed by NSNumber.
        let idMap: [NSNumber: SessionView] = [NSNumber(value: 99): recycled]

        let arrangement = leaf(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            arrangementID: 99)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement,
            idMap: idMap,
            sessionMap: nil,
            revivedSessions: nil)

        XCTAssertTrue(view === recycled, "expected recycle via arrangement ID")
    }

    /// Splitter unique ID is propagated to the constructed PTYSplitView.
    func testSplitterUniqueIDPropagation() {
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
                leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 100)),
            ],
            splitterID: "split-abc")

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        let split = view as! PTYSplitView
        XCTAssertEqual(split.stringUniqueIdentifier(), "split-abc")
    }

    /// Splitter frame is applied to the produced NSSplitView.
    func testSplitterFrameApplied() {
        let frame = NSRect(x: 10, y: 20, width: 300, height: 150)
        let arrangement = splitter(
            vertical: true,
            frame: frame,
            children: [
                leaf(frame: NSRect(x: 10, y: 20, width: 150, height: 150)),
                leaf(frame: NSRect(x: 160, y: 20, width: 150, height: 150)),
            ])

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        XCTAssertEqual(view.frame, frame)
    }

    /// Leaf-only arrangement (no enclosing splitter) returns a SessionView,
    /// not a splitter.
    func testBareLeafArrangementReturnsSessionView() {
        let frame = NSRect(x: 0, y: 0, width: 80, height: 40)
        let arrangement = leaf(frame: frame)

        let view = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: nil, sessionMap: nil, revivedSessions: nil)
        XCTAssertTrue(view is SessionView)
        XCTAssertFalse(view is NSSplitView)
        XCTAssertEqual(view.frame, frame)
    }

    /// idMap recycling applies recursively inside nested splitters.
    func testRecycleAcrossNestedSplitters() {
        let recycledA = SessionView(frame: .zero)
        let recycledB = SessionView(frame: .zero)
        let idMap: [NSNumber: SessionView] = [
            NSNumber(value: 1): recycledA,
            NSNumber(value: 2): recycledB,
        ]
        let arrangement = splitter(
            vertical: true,
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            children: [
                leaf(frame: NSRect(x: 0, y: 0, width: 100, height: 100), tmuxPane: 1),
                splitter(
                    vertical: false,
                    frame: NSRect(x: 100, y: 0, width: 100, height: 100),
                    children: [
                        leaf(frame: NSRect(x: 100, y: 0, width: 100, height: 50), tmuxPane: 2),
                        leaf(frame: NSRect(x: 100, y: 50, width: 100, height: 50), tmuxPane: 3),
                    ]),
            ])

        let outer = iTermSplitTreeRebuilder.buildSplitterTree(
            arrangement: arrangement, idMap: idMap, sessionMap: nil, revivedSessions: nil) as! NSSplitView

        XCTAssertTrue(outer.subviews[0] === recycledA)
        let inner = outer.subviews[1] as! NSSplitView
        XCTAssertTrue(inner.subviews[0] === recycledB)
        // Pane 3 is not in idMap so a fresh SessionView is created.
        XCTAssertFalse(inner.subviews[1] === recycledA)
        XCTAssertFalse(inner.subviews[1] === recycledB)
        XCTAssertTrue(inner.subviews[1] is SessionView)
    }
}
