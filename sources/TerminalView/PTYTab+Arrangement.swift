// Saved tab layouts contain splitter nodes and session-view leaves.
import AppKit

extension PTYTab {
    typealias Arrangement = [AnyHashable: Any]

    /// In pane order. A missing session is passed to the caller so that restoration can
    /// reject an incomplete map while searches can skip the missing leaf.
    @discardableResult
    static func visitSessionLeaves(in node: Arrangement,
                                   while visit: (Arrangement?) -> Bool) -> Bool {
        guard node[TAB_ARRANGEMENT_VIEW_TYPE] as? String == VIEW_TYPE_SPLITTER else {
            return visit(node[TAB_ARRANGEMENT_SESSION] as? Arrangement)
        }
        for child in node[SUBVIEWS] as? [Any] ?? [] {
            guard let child = child as? Arrangement else {
                if !visit(nil) { return false }
                continue
            }
            if !visitSessionLeaves(in: child, while: visit) { return false }
        }
        return true
    }

    private static func firstSession(in node: Arrangement,
                                     matching predicate: (Arrangement) -> Bool) -> Arrangement? {
        var match: Arrangement?
        visitSessionLeaves(in: node) { session in
            guard let session, predicate(session) else { return true }
            match = session
            return false
        }
        return match
    }

    @objc(sessionMapWithArrangement:sessions:)
    static func sessionMap(withArrangement arrangement: Arrangement, sessions: [PTYSession]) -> [String: PTYSession]? {
        guard let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement else { return nil }
        var byGUID = [String: PTYSession]()
        for session in sessions where byGUID[session.guid] == nil {
            byGUID[session.guid] = session
        }
        var matched = [String: PTYSession]()
        let complete = visitSessionLeaves(in: root) { leaf in
            guard let leaf, let guid = PTYSession.guid(inArrangement: leaf),
                  let session = byGUID[guid] else { return false }
            matched[guid] = session
            return true
        }
        return complete ? matched : nil
    }

    /// Register saved contents before startup restores sessions with matching identifiers.
    @objc(registerSessionsInArrangement:)
    static func registerSessions(in arrangement: Arrangement) {
        guard let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement else { return }
        visitSessionLeaves(in: root) { session in
            if let session { PTYSession.registerSession(inArrangement: session as NSDictionary) }
            return true
        }
    }

    @objc(arrangement:passesTest:)
    static func arrangement(_ arrangement: Arrangement, passesTest predicate: (Arrangement) -> Bool) -> Bool {
        guard let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement else { return false }
        return firstSession(in: root, matching: predicate) != nil
    }

    @objc(arrangementForSessionWithGUID:inArrangement:)
    static func arrangement(forSessionWithGUID guid: String, in arrangement: Arrangement) -> Arrangement? {
        guard let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement else { return nil }
        return firstSession(in: root) { PTYSession.guid(inArrangement: $0) == guid }
    }

    @objc(modifiedArrangement:mutator:)
    static func modifiedArrangement(_ arrangement: Arrangement,
                                    mutator: (Arrangement) -> Arrangement) -> Arrangement {
        func modify(_ node: Arrangement) -> Arrangement {
            var result = node
            if node[TAB_ARRANGEMENT_VIEW_TYPE] as? String == VIEW_TYPE_SPLITTER {
                if let children = node[SUBVIEWS] as? [Arrangement] {
                    result[SUBVIEWS] = children.map(modify)
                }
            } else if let session = node[TAB_ARRANGEMENT_SESSION] as? Arrangement {
                result[TAB_ARRANGEMENT_SESSION] = mutator(session)
            }
            return result
        }

        guard let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement else { return arrangement }
        var result = arrangement
        result[TAB_ARRANGEMENT_ROOT] = modify(root)
        return result
    }

    @objc(repairedArrangement:replacingProfileWithGUID:withProfile:)
    static func repairedArrangement(_ arrangement: Arrangement, replacingProfileWithGUID guid: String,
                                    withProfile profile: Arrangement) -> Arrangement {
        modifiedArrangement(arrangement) {
            PTYSession.repairedArrangement($0, replacingProfileWithGUID: guid, withProfile: profile)
        }
    }

    @objc(repairedArrangement:replacingOldCWDOfSessionWithGUID:withOldCWD:)
    static func repairedArrangement(_ arrangement: Arrangement, replacingOldCWDOfSessionWithGUID guid: String,
                                    withOldCWD cwd: String) -> Arrangement {
        modifiedArrangement(arrangement) {
            PTYSession.repairedArrangement($0, replacingOldCWDOfSessionWithGUID: guid, withOldCWD: cwd)
        }
    }

    @objc(repairedArrangement:profileMutator:)
    static func repairedArrangement(_ arrangement: Arrangement,
                                    profileMutator: (Arrangement) -> Arrangement) -> Arrangement {
        modifiedArrangement(arrangement) { PTYSession.repairedArrangement($0, profileMutator: profileMutator) }
    }

    @objc(repairedArrangement:settingCustomLocale:)
    static func repairedArrangement(_ arrangement: Arrangement, settingCustomLocale locale: String?) -> Arrangement {
        modifiedArrangement(arrangement) { PTYSession.repairedArrangement($0, settingCustomLocale: locale) }
    }
}

extension PTYTab {
    @objc(frameToDict:)
    static func arrangementFrame(_ frame: NSRect) -> [String: CGFloat] {
        [TAB_X: frame.origin.x, TAB_Y: frame.origin.y, TAB_WIDTH: frame.size.width, TAB_HEIGHT: frame.size.height]
    }

    // The graph encoder addresses siblings by identifier and records their display order separately.
    // Older arrangements can have missing or duplicate identifiers. Keep the first occurrence.
    private static func encodeSubviews<Node>(_ nodes: [Node], into encoder: iTermEncoderAdapter,
                                             identifier: (Node, Int) -> String?,
                                             write: (Node, iTermEncoderAdapter) -> Bool) -> Bool {
        var identifiers: [String] = []
        var children: [Node] = []
        var seen = Set<String>()
        for node in nodes {
            guard let id = identifier(node, children.count) else { return false }
            if seen.insert(id).inserted {
                identifiers.append(id)
                children.append(node)
            }
        }
        var complete = true
        encoder.encodeArray(withKey: SUBVIEWS, identifiers: identifiers,
                            generation: iTermGenerationAlwaysEncode) { childEncoder, index, _, stop in
            complete = write(children[index], childEncoder)
            stop.pointee = ObjCBool(!complete)
            return complete
        }
        return complete
    }

    @objc(encodeStandaloneArchiveForSession:tabGUID:encoder:options:)
    static func encodeStandaloneArchive(for session: PTYSession, tabGUID: String, encoder: iTermEncoderAdapter,
                                        options: Arrangement) -> Bool {
        guard let pane = session.view,
              let container = PTYSplitView(frame: pane.bounds, uniqueIdentifier: UUID().uuidString) else { return false }
        container.isVertical = true
        var options = options
        options[PTYTabArrangementOptionsOnlySessionID] = session.guid
        return encodeLayout(withContents: true, constructIDMap: false, encoder: encoder, options: options,
                            activeSession: session, tabGUID: tabGUID, titleOverride: nil, isMaximized: false,
                            savedArrangement: nil, idMap: nil, root: container, sessionViewFinder: { _ in pane },
                            sessionFinder: { _ in session })
    }

    @objc(encodeWithContents:constructIdMap:encoder:options:activeSession:tabGuid:titleOverride:isMaximized:savedArrangement:idMap:root:sessionViewFinder:sessionFinder:)
    static func encodeLayout(withContents contents: Bool, constructIDMap: Bool, encoder: iTermEncoderAdapter,
                             options: Arrangement?, activeSession: PTYSession?, tabGUID: String?,
                             titleOverride: String?, isMaximized: Bool, savedArrangement: Arrangement?,
                             idMap: NSMutableDictionary?, root: NSView?, sessionViewFinder: (String) -> SessionView?,
                             sessionFinder: (SessionView) -> PTYSession?) -> Bool {
        encoder.setObject(tabGUID, forKey: TAB_GUID)
        encoder.setObject(titleOverride, forKey: TAB_ARRANGEMENT_TITLE_OVERRIDE)
        let onlySessionID = options?[PTYTabArrangementOptionsOnlySessionID] as? String

        func encodeSaved(_ node: Arrangement, into encoder: iTermEncoderAdapter) -> Bool {
            let isSplitter = node[TAB_ARRANGEMENT_VIEW_TYPE] as? String == VIEW_TYPE_SPLITTER
            let childKey = isSplitter ? SUBVIEWS : TAB_ARRANGEMENT_SESSION
            for (key, value) in node {
                guard let key = key as? String else { return false }
                if key != childKey { encoder.setObject(value, forKey: key) }
            }
            if isSplitter {
                guard let children = node[SUBVIEWS] as? [Arrangement] else { return false }
                return encodeSubviews(children, into: encoder) { child, index in
                    if child[TAB_ARRANGEMENT_VIEW_TYPE] as? String == VIEW_TYPE_SPLITTER {
                        return child[TAB_ARRANGEMENT_SPLITTER_ID] as? String ?? String(index)
                    }
                    let session = child[TAB_ARRANGEMENT_SESSION] as? Arrangement
                    return session.flatMap { PTYSession.guid(inArrangement: $0) } ?? String(index)
                } write: { encodeSaved($0, into: $1) }
            }

            guard let id = node[TAB_ARRANGEMENT_ID] as? NSNumber, let pane = idMap?[id] as? SessionView,
                  let session = sessionFinder(pane) else {
                XLog("No live pane for saved arrangement leaf")
                return false
            }
            return encoder.encodeDictionary(withKey: TAB_ARRANGEMENT_SESSION, generation: iTermGenerationAlwaysEncode) {
                session.encodeArrangement(withContents: contents, encoder: $0, replacementProfile: nil,
                                          saveProgram: true, pendingJumps: nil, options: options)
            }
        }

        if isMaximized && onlySessionID == nil {
            // Serialize the original geometry with fresh session contents, without disturbing the live split.
            guard !constructIDMap, var saved = savedArrangement?[TAB_ARRANGEMENT_ROOT] as? Arrangement else {
                return false
            }
            saved[TAB_ARRANGEMENT_IS_MAXIMIZED] = true
            return encoder.encodeDictionary(withKey: TAB_ARRANGEMENT_ROOT, generation: iTermGenerationAlwaysEncode) {
                encodeSaved(saved, into: $0)
            }
        }

        guard let root, !constructIDMap || idMap != nil else { return false }
        let firstID = idMap?.count ?? 0
        var mappedPanes: [SessionView] = []
        func encodeLive(_ view: NSView, into encoder: iTermEncoderAdapter) -> Bool {
            if let split = view as? NSSplitView {
                encoder.setObject(VIEW_TYPE_SPLITTER, forKey: TAB_ARRANGEMENT_VIEW_TYPE)
                encoder.setObject(arrangementFrame(split.frame), forKey: TAB_ARRANGEMENT_SPLITTER_FRAME)
                encoder.setObject((split as? PTYSplitView)?.stringUniqueIdentifier(), forKey: TAB_ARRANGEMENT_SPLITTER_ID)
                encoder.setObject(split.isVertical, forKey: SPLITTER_IS_VERTICAL)
                let subviews: [NSView]
                if let onlySessionID {
                    guard let pane = sessionViewFinder(onlySessionID) else { return false }
                    subviews = [pane]
                } else {
                    subviews = split.subviews.filter { $0 is NSSplitView || $0 is SessionView }
                }
                return encodeSubviews(subviews, into: encoder) { view, index in
                    if view is NSSplitView { return (view as? PTYSplitView)?.stringUniqueIdentifier() ?? String(index) }
                    guard let pane = view as? SessionView else { return nil }
                    return sessionFinder(pane)?.stringUniqueIdentifier()
                } write: { encodeLive($0, into: $1) }
            }

            guard let pane = view as? SessionView, let session = sessionFinder(pane) else { return false }
            encoder.setObject(VIEW_TYPE_SESSIONVIEW, forKey: TAB_ARRANGEMENT_VIEW_TYPE)
            encoder.setObject(arrangementFrame(pane.frame), forKey: TAB_ARRANGEMENT_SESSIONVIEW_FRAME)
            encoder.setObject(session === activeSession || onlySessionID != nil, forKey: TAB_ARRANGEMENT_IS_ACTIVE)
            if constructIDMap {
                encoder.setObject(firstID + mappedPanes.count, forKey: TAB_ARRANGEMENT_ID)
                mappedPanes.append(pane)
            }
            return encoder.encodeDictionary(withKey: TAB_ARRANGEMENT_SESSION, generation: iTermGenerationAlwaysEncode) {
                session.encodeArrangement(withContents: contents, encoder: $0,
                                          replacementProfile: options?[PTYTabArrangementOptionsReplacementProfile] as? Arrangement,
                                          saveProgram: (options?[PTYTabArrangementOptionsReplacementSaveProgram] as? NSNumber)?.boolValue ?? true,
                                          pendingJumps: options?[PTYTabArrangementOptionsPendingJumps] as? [SSHReconnectionInfoObjC],
                                          options: options)
            }
        }

        let complete = encoder.encodeDictionary(withKey: TAB_ARRANGEMENT_ROOT, generation: iTermGenerationAlwaysEncode) {
            encodeLive(root, into: $0)
        }
        if complete, let idMap {
            for (offset, pane) in mappedPanes.enumerated() {
                pane.saveFrameSize()
                idMap[NSNumber(value: firstID + offset)] = pane
            }
        }
        return complete
    }
}
