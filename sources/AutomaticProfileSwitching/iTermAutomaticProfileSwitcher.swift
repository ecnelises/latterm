//
//  iTermAutomaticProfileSwitcher.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/28/16.
//

import Foundation

/// Captures the profile state needed to restore a session after an automatic profile switch.
@objc(iTermSavedProfile)
class iTermSavedProfile: NSObject {
    private static let profileKey = "Profile"
    private static let originalProfileKey = "Original Profile"
    private static let overriddenFieldsKey = "Overridden Fields"

    @objc var profile: [AnyHashable: Any]?
    @objc var originalProfile: [AnyHashable: Any]?
    @objc var isDivorced: Bool = false
    @objc var overriddenFields: NSMutableSet?

    override init() {
        super.init()
    }

    /// Restores saved profile state from a restorable-state dictionary.
    @objc(initWithSavedState:)
    init(savedState state: [AnyHashable: Any]) {
        super.init()
        let cleaned = (state as NSDictionary).removingNullValues() ?? [:]
        profile = cleaned[Self.profileKey] as? [AnyHashable: Any]
        originalProfile = cleaned[Self.originalProfileKey] as? [AnyHashable: Any]
        // Overridden fields are serialized as an array (see savedState()) because NSSet is neither
        // a property-list type nor in the basic-classes allowlist used to decode restorable state,
        // which would otherwise drop the entire session arrangement on restore (issue 12866). Older
        // saved state may still hold a set, so accept both forms.
        if let array = cleaned[Self.overriddenFieldsKey] as? [Any] {
            overriddenFields = NSMutableSet(array: array)
        } else if let set = cleaned[Self.overriddenFieldsKey] as? NSSet {
            overriddenFields = NSMutableSet(array: set.allObjects)
        }
    }

    /// Serializes this saved profile into a property-list-safe restorable-state dictionary.
    @objc(savedState)
    func savedState() -> [AnyHashable: Any] {
        let sortedOverriddenFields: Any
        if let objects = overriddenFields?.allObjects {
            sortedOverriddenFields = (objects as NSArray).sortedArray(using: #selector(NSString.compare(_:)))
        } else {
            sortedOverriddenFields = NSNull()
        }
        return [
            Self.profileKey: profile ?? NSNull(),
            Self.originalProfileKey: originalProfile ?? NSNull(),
            // Serialize as a sorted array rather than an NSSet. See init(savedState:) (issue 12866).
            Self.overriddenFieldsKey: sortedOverriddenFields
        ]
    }
}

/// Delegate implemented by a session using automatic profile switching.
@objc(iTermAutomaticProfileSwitcherDelegate)
protocol iTermAutomaticProfileSwitcherDelegate: AnyObject {
    /// Applies `savedProfile` as the session's current profile, respecting overridden fields.
    @objc(automaticProfileSwitcherLoadProfile:)
    func automaticProfileSwitcherLoadProfile(_ savedProfile: iTermSavedProfile)

    /// Returns the current profile, including local changes.
    @objc(automaticProfileSwitcherCurrentProfile)
    func automaticProfileSwitcherCurrentProfile() -> [AnyHashable: Any]

    /// Returns the current profile snapshot; only the name and GUID are needed.
    @objc(automaticProfileSwitcherCurrentSavedProfile)
    func automaticProfileSwitcherCurrentSavedProfile() -> iTermSavedProfile

    /// Returns all profiles in user defaults. Exposed for testing.
    @objc(automaticProfileSwitcherAllProfiles)
    func automaticProfileSwitcherAllProfiles() -> [[AnyHashable: Any]]

    /// Returns the session's name for logging.
    @objc(automaticProfileSwitcherSessionName)
    func automaticProfileSwitcherSessionName() -> String
}

private func profilesEqual(_ lhs: [AnyHashable: Any]?, _ rhs: [AnyHashable: Any]?) -> Bool {
    guard let lhsGuid = lhs?[KEY_GUID] as? String,
          let rhsGuid = rhs?[KEY_GUID] as? String else {
        return false
    }
    return lhsGuid == rhsGuid
}

/// Evaluates automatic profile switching rules and manages the fallback profile stack.
@objc(iTermAutomaticProfileSwitcher)
class iTermAutomaticProfileSwitcher: NSObject {
    private static let stackKey = "Profile Stack"

    @objc weak var delegate: iTermAutomaticProfileSwitcherDelegate?

    private var profileStack: [iTermSavedProfile] = []
    private var lastHostname: String?
    private var lastUsername: String?
    private var lastPath: String?
    private var lastJob: String?
    private var lastCommandLine: String?
    private var lastProfileGUID: String?
    private var dirty: Bool = false
    private var switching: Bool = false

    /// Creates an automatic profile switcher bound to `delegate`.
    @objc(initWithDelegate:)
    init(delegate: iTermAutomaticProfileSwitcherDelegate) {
        self.delegate = delegate
        super.init()
        registerForProfileReloads()
    }

    /// Restores an automatic profile switcher and its stack from saved arrangement state.
    @objc(initWithDelegate:savedState:)
    convenience init(delegate: iTermAutomaticProfileSwitcherDelegate,
                     savedState: [AnyHashable: Any]) {
        self.init(delegate: delegate)
        if let stackDicts = savedState[Self.stackKey] as? [[AnyHashable: Any]] {
            for dict in stackDicts {
                profileStack.append(iTermSavedProfile(savedState: dict))
                DLog("Initialized automatic profile switcher \(self)")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func registerForProfileReloads() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadAllProfiles),
                                               name: NSNotification.Name(kReloadAllProfiles),
                                               object: nil)
    }

    @objc private func reloadAllProfiles() {
        apsLog("A profile has changed. This will cause APS to re-check its state.")
        dirty = true
    }

    /// Forces reevaluation on the next call to `setHostname(...)`.
    @objc(markDirty)
    func markDirty() {
        apsLog("markDirty \(Thread.callStackSymbols)")
        dirty = true
    }

    /// Updates session context and switches profiles if a better rule or stack entry matches.
    @objc(setHostname:username:path:job:commandLine:expressionValueProvider:)
    func setHostname(_ hostname: String?,
                     username: String?,
                     path: String?,
                     job: String?,
                     commandLine: String?,
                     expressionValueProvider: AutomaticProfileSwitchingExpressionScoreProvider?) {
        apsLog("APS: Updating configuration to hostname=\(hostname ?? "(null)"), username=\(username ?? "(null)"), path=\(path ?? "(null)"), job=\(job ?? "(null)"), commandLine=\(commandLine ?? "(null)")")
        if switching {
            apsLog("Already switching so ignore the change")
            return
        }
        let currentProfile = delegate?.automaticProfileSwitcherCurrentProfile()
        let guid = currentProfile?[KEY_GUID] as? String
        if !dirty &&
            hostname == lastHostname &&
            username == lastUsername &&
            path == lastPath &&
            job == lastJob &&
            commandLine == lastCommandLine &&
            lastProfileGUID == guid {
            // Preserve ObjC nil-receiver equality nuance: if both sides are nil, ObjC `[nil isEqualToString:nil]`
            // returned NO, whereas Swift `nil == nil` is true; check non-nil just for exact parity if needed.
            if hostname != nil && username != nil && path != nil && job != nil && commandLine != nil && guid != nil {
                apsLog("Nothing changed.")
                return
            }
        }
        lastHostname = hostname
        lastUsername = username
        lastPath = path
        lastJob = job
        lastCommandLine = commandLine
        lastProfileGUID = guid
        dirty = false

        let scoreForCurrentProfile = highestScore(for: currentProfile,
                                                  hostname: hostname,
                                                  username: username,
                                                  path: path,
                                                  job: job,
                                                  commandLine: commandLine,
                                                  expressionValueProvider: expressionValueProvider)
        let stackMatch = topmostSavedProfile(matchingHostname: hostname,
                                             username: username,
                                             path: path,
                                             job: job,
                                             commandLine: commandLine,
                                             expressionValueProvider: expressionValueProvider)
        let topmostMatchingSavedProfile = stackMatch?.profile
        let scoreForTopmostMatchingSavedProfile = stackMatch?.score ?? 0.0

        apsLog("The current profile is \(currentProfile?[KEY_NAME] ?? "(null)") with a score of \(String(format: "%0.2f", scoreForCurrentProfile)). The highest-ranking profile in the stack is \(topmostMatchingSavedProfile?.profile?[KEY_NAME] ?? "(null)"), with score of \(String(format: "%0.2f", scoreForTopmostMatchingSavedProfile))")

        if let topmostMatchingSavedProfile,
           !profilesEqual(topmostMatchingSavedProfile.originalProfile, currentProfile),
           scoreForTopmostMatchingSavedProfile > scoreForCurrentProfile {
            apsLog("Profile \(topmostMatchingSavedProfile.profile?[KEY_NAME] ?? "(null)") is in the stack and outranks the current profile. Will switch, but first, remove it and subsequent entries from the stack.")
            while let last = profileStack.last,
                  (last.originalProfile as AnyObject?) === (topmostMatchingSavedProfile.originalProfile as AnyObject?) {
                apsLog("Pop")
                profileStack.removeLast()
            }
            apsLog("Stack is now: \(profileStackString)")
            apsLog("Switch to saved profile from stack: \(topmostMatchingSavedProfile.profile?[KEY_NAME] ?? "(null)")")
            change(to: topmostMatchingSavedProfile)
            return
        }

        apsLog("No profile in the stack outranks the current profile. Check if any profile not in the stack outranks the current profile.")
        let bestMatch = highestScoringProfile(forHostname: hostname,
                                              username: username,
                                              path: path,
                                              job: job,
                                              commandLine: commandLine,
                                              expressionValueProvider: expressionValueProvider)
        let highestScoringProfile = bestMatch?.profile
        let scoreOfHighestScoringProfile = bestMatch?.score ?? 0.0
        let sticky = bestMatch?.isSticky ?? false

        apsLog("The highest scoring profile is \(highestScoringProfile?[KEY_NAME] ?? "(null)") with a score of \(scoreOfHighestScoringProfile)")

        if let highestScoringProfile, !profilesEqual(highestScoringProfile, currentProfile) {
            apsLog("Will switch to profile \(highestScoringProfile[KEY_NAME] ?? "(null)")")
            pushCurrentProfileIfNeeded()

            let newSavedProfile = iTermSavedProfile()
            newSavedProfile.originalProfile = highestScoringProfile
            apsLog("Switch to profile \(highestScoringProfile[KEY_NAME] ?? "(null)")")
            change(to: newSavedProfile)

            if sticky {
                apsLog("This profile's rule is sticky. Clearing the stack and pushing the new profile.")
                profileStack.removeAll()
                pushCurrentProfileIfNeeded()
            }
            apsLog("Stack is now: \(profileStackString)")
        } else if highestScoringProfile == nil && !profileStack.isEmpty {
            apsLog("No rule was matched by any profile, but the stack is not empty.")
            if profileStack.count > 1 {
                apsLog("Removing all but first profile in the stack since no rule was matched.")
                profileStack.removeSubrange(1..<profileStack.count)
                apsLog("Stack is now: \(profileStackString)")
            }
            if let first = profileStack.first, !profilesEqual(first.originalProfile, currentProfile) {
                apsLog("Switch to the topmost profile in the stack: \(first.profile?[KEY_NAME] ?? "(null)")")
                change(to: first)
            } else {
                apsLog("Not switching profiles because the topmost profile in the stack equals the current profile.")
            }
        } else {
            apsLog("Not doing anything. Can't improve on the status quo.")
        }
    }

    /// Serializes the profile stack for session arrangement restoration.
    @objc(savedState)
    func savedState() -> [AnyHashable: Any] {
        return [Self.stackKey: profileStack.map { $0.savedState() }]
    }

    // MARK: - Diagnostics

    override var description: String {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        return "<\(type(of: self)): \(ptr) stack=\(profileStackString)>"
    }

    @objc var profileStackString: String {
        return profileStack.map { "\($0.profile?[KEY_NAME] ?? "(null)") " }.joined()
    }

    // MARK: - Private

    private func apsLog(_ message: @autoclosure () -> String,
                        file: String = #file,
                        line: Int = #line,
                        function: String = #function) {
        let shouldDLog = gDebugLogging.boolValue
        let shouldHistoryLog = iTermUserDefaults.enableAutomaticProfileSwitchingLogging
        guard shouldDLog || shouldHistoryLog else {
            return
        }
        let evaluated = message()
        if shouldDLog {
            DLog(evaluated, file: file, line: line, function: function)
        }
        if shouldHistoryLog {
            iTermScriptHistory.sharedInstance().addAPSLoggingEntryIfNeeded()
            let sessionName = delegate?.automaticProfileSwitcherSessionName() ?? "(null)"
            let output = "[\(sessionName)] \(evaluated)\n"
            iTermScriptHistoryEntry.aps().addOutput(output) {}
        }
    }

    private func change(to profile: iTermSavedProfile) {
        it_assert(!switching)
        switching = true
        delegate?.automaticProfileSwitcherLoadProfile(profile)
        switching = false
    }

    private func highestScoringProfile(forHostname hostname: String?,
                                       username: String?,
                                       path: String?,
                                       job: String?,
                                       commandLine: String?,
                                       expressionValueProvider: AutomaticProfileSwitchingExpressionScoreProvider?) -> (profile: [AnyHashable: Any], isSticky: Bool, score: Double)? {
        guard let rawProfiles = delegate?.automaticProfileSwitcherAllProfiles() else {
            return nil
        }
        let map = ruleToProfileMap(profiles: rawProfiles.map { $0 as NSDictionary })
        var bestScore = 0.0
        var bestProfile: [AnyHashable: Any]?
        var bestSticky = false

        for (ruleString, profileDict) in map {
            guard let rule = iTermRule(string: ruleString) else {
                continue
            }
            let score = rule.score(forHostname: hostname,
                                   username: username,
                                   path: path,
                                   job: job,
                                   commandLine: commandLine,
                                   expressionValueProvider: expressionValueProvider)
            if score > bestScore {
                bestScore = score
                bestProfile = profileDict as? [AnyHashable: Any]
                bestSticky = rule.isSticky
            }
        }
        guard let bestProfile else {
            return nil
        }
        return (bestProfile, bestSticky, bestScore)
    }

    private func pushCurrentProfileIfNeeded() {
        let currentProfile = delegate?.automaticProfileSwitcherCurrentProfile()
        if !profilesEqual(profileStack.last?.originalProfile, currentProfile) {
            apsLog("Push profile on to stack: \(currentProfile?[KEY_NAME] ?? "(null)")")
            if let savedProfile = delegate?.automaticProfileSwitcherCurrentSavedProfile() {
                profileStack.append(savedProfile)
            }
            apsLog("Stack is now: \(profileStackString)")
        } else {
            apsLog("Not pushing profile \(currentProfile?[KEY_NAME] ?? "(null)") because it matches the top of the stack.")
        }
    }

    private func highestScore(for candidate: [AnyHashable: Any]?,
                              hostname: String?,
                              username: String?,
                              path: String?,
                              job: String?,
                              commandLine: String?,
                              expressionValueProvider: AutomaticProfileSwitchingExpressionScoreProvider?) -> Double {
        guard let rules = candidate?[KEY_BOUND_HOSTS] as? [String] else {
            return 0.0
        }
        var highestScore = 0.0
        for ruleString in rules {
            guard let rule = iTermRule(string: ruleString) else {
                continue
            }
            let score = rule.score(forHostname: hostname,
                                   username: username,
                                   path: path,
                                   job: job,
                                   commandLine: commandLine,
                                   expressionValueProvider: expressionValueProvider)
            highestScore = max(highestScore, score)
        }
        return highestScore
    }

    private func topmostSavedProfile(matchingHostname hostname: String?,
                                     username: String?,
                                     path: String?,
                                     job: String?,
                                     commandLine: String?,
                                     expressionValueProvider: AutomaticProfileSwitchingExpressionScoreProvider?) -> (profile: iTermSavedProfile, score: Double)? {
        for savedProfile in profileStack.reversed() {
            let score = highestScore(for: savedProfile.profile,
                                     hostname: hostname,
                                     username: username,
                                     path: path,
                                     job: job,
                                     commandLine: commandLine,
                                     expressionValueProvider: expressionValueProvider)
            if score > 0 {
                return (savedProfile, score)
            }
        }
        return nil
    }
}
