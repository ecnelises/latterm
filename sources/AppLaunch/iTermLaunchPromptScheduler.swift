import Foundation

@objc enum iTermLaunchExperienceChoice: Int {
    case none
    case defaultPasteBehaviorChangeWarning
    case tipOfTheDay
}

// Selects one launch prompt and persists its cooldown independently of AppKit UI.
@objc(iTermLaunchPromptScheduler)
final class iTermLaunchPromptScheduler: NSObject {
    private static let nextPromptTimeKey = "NoSyncNextAnnoyanceTime"
    private static let eligibilityBeganKey = "NoSyncTipOfTheDayEligibilityBeganTime"
    private static let day: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    @objc let choice: iTermLaunchExperienceChoice

    @objc(initWithUserDefaults:preferredChoice:)
    convenience init(userDefaults: UserDefaults, preferredChoice: () -> iTermLaunchExperienceChoice) {
        self.init(userDefaults: userDefaults, now: Date.init, preferredChoice: preferredChoice)
    }

    init(userDefaults: UserDefaults,
         now: @escaping () -> Date,
         preferredChoice: () -> iTermLaunchExperienceChoice) {
        defaults = userDefaults
        self.now = now
        let date = now()
        if defaults.double(forKey: Self.nextPromptTimeKey) > date.timeIntervalSinceReferenceDate {
            // Do not evaluate prompt eligibility while prompts are suppressed.
            choice = .none
        } else {
            let preferred = preferredChoice()
            if preferred == .tipOfTheDay && defaults.object(forKey: Self.eligibilityBeganKey) == nil {
                defaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.eligibilityBeganKey)
                defaults.set(date.addingTimeInterval(2 * Self.day).timeIntervalSinceReferenceDate,
                             forKey: Self.nextPromptTimeKey)
                choice = .none
            } else {
                choice = preferred
            }
        }
        super.init()
        DLog("Launch prompt choice: \(choice.rawValue)")
    }

    @objc var permissionPromptAllowed: Bool { choice == .tipOfTheDay }

    // Called when startup activities actually run, not when the choice is made.
    @objc func prepareForStartupActivities() -> Date {
        let date = now()
        switch choice {
        case .tipOfTheDay:
            suppressPrompts(until: date.addingTimeInterval(Self.day))
            return date
        case .defaultPasteBehaviorChangeWarning:
            // Already-authorized tips may resume one day after this warning.
            return date.addingTimeInterval(Self.day)
        case .none:
            return date
        }
    }

    @objc func prepareToShowPasteWarning() -> Bool {
        guard choice == .defaultPasteBehaviorChangeWarning else { return false }
        suppressPrompts(until: now().addingTimeInterval(Self.day))
        return true
    }

    private func suppressPrompts(until date: Date) {
        DLog("Suppress launch prompts until \(date)")
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.nextPromptTimeKey)
    }
}
