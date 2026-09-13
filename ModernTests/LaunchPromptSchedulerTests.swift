import XCTest
@testable import iTerm2SharedARC

final class LaunchPromptSchedulerTests: XCTestCase {
    private let nextPromptKey = "NoSyncNextAnnoyanceTime"
    private let eligibilityKey = "NoSyncTipOfTheDayEligibilityBeganTime"
    private let day: TimeInterval = 24 * 60 * 60
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var date = Date(timeIntervalSinceReferenceDate: 1_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "Latterm.LaunchPromptSchedulerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    private func makeScheduler(_ choice: iTermLaunchExperienceChoice) -> iTermLaunchPromptScheduler {
        iTermLaunchPromptScheduler(userDefaults: defaults, now: { [unowned self] in self.date }) { choice }
    }

    func testCooldownSkipsEligibilityEvaluation() {
        defaults.set(date.timeIntervalSinceReferenceDate + 1, forKey: nextPromptKey)
        var evaluated = false
        let scheduler = iTermLaunchPromptScheduler(userDefaults: defaults, now: { self.date }) {
            evaluated = true
            return .defaultPasteBehaviorChangeWarning
        }
        XCTAssertFalse(evaluated)
        XCTAssertEqual(scheduler.choice, .none)
        XCTAssertFalse(scheduler.prepareToShowPasteWarning())
        XCTAssertNil(defaults.object(forKey: eligibilityKey))
    }

    func testCooldownExpiresAtExactBoundary() {
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: nextPromptKey)
        defaults.set(1, forKey: eligibilityKey)
        XCTAssertEqual(makeScheduler(.tipOfTheDay).choice, .tipOfTheDay)
    }

    func testFirstTipEligibilityStartsTwoDayGracePeriod() {
        let scheduler = makeScheduler(.tipOfTheDay)
        XCTAssertEqual(scheduler.choice, .none)
        XCTAssertFalse(scheduler.permissionPromptAllowed)
        XCTAssertEqual(defaults.double(forKey: eligibilityKey), date.timeIntervalSinceReferenceDate)
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), date.addingTimeInterval(2 * day).timeIntervalSinceReferenceDate)
        date.addTimeInterval(30)
        XCTAssertEqual(scheduler.prepareForStartupActivities(), date)
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), date.addingTimeInterval(2 * day - 30).timeIntervalSinceReferenceDate)
    }

    func testExistingZeroEligibilityTimestampIsNotTreatedAsMissing() {
        defaults.set(0, forKey: eligibilityKey)
        let scheduler = makeScheduler(.tipOfTheDay)
        XCTAssertEqual(scheduler.choice, .tipOfTheDay)
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
    }

    func testTipCooldownStartsWhenStartupActivitiesRun() {
        defaults.set(1, forKey: eligibilityKey)
        let scheduler = makeScheduler(.tipOfTheDay)
        XCTAssertTrue(scheduler.permissionPromptAllowed)
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
        date.addTimeInterval(60)
        XCTAssertEqual(scheduler.prepareForStartupActivities(), date)
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), date.addingTimeInterval(day).timeIntervalSinceReferenceDate)
        XCTAssertFalse(scheduler.prepareToShowPasteWarning())
    }

    func testPasteWarningUsesItsOwnDisplayTimeAndDelaysTips() {
        let scheduler = makeScheduler(.defaultPasteBehaviorChangeWarning)
        XCTAssertFalse(scheduler.permissionPromptAllowed)
        XCTAssertNil(defaults.object(forKey: eligibilityKey))
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
        date.addTimeInterval(20)
        XCTAssertTrue(scheduler.prepareToShowPasteWarning())
        let cooldown = date.addingTimeInterval(day).timeIntervalSinceReferenceDate
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), cooldown)
        date.addTimeInterval(40)
        XCTAssertEqual(scheduler.prepareForStartupActivities(), date.addingTimeInterval(day))
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), cooldown)
    }

    func testPreparingTipsDoesNotMarkPasteWarningAsShown() {
        let scheduler = makeScheduler(.defaultPasteBehaviorChangeWarning)
        XCTAssertEqual(scheduler.prepareForStartupActivities(), date.addingTimeInterval(day))
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
    }

    func testNoPromptLeavesPersistentStateUntouched() {
        let scheduler = makeScheduler(.none)
        XCTAssertFalse(scheduler.permissionPromptAllowed)
        XCTAssertFalse(scheduler.prepareToShowPasteWarning())
        XCTAssertEqual(scheduler.prepareForStartupActivities(), date)
        XCTAssertNil(defaults.object(forKey: eligibilityKey))
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
    }

    func testGracePeriodAndCooldownPersistAcrossLaunches() {
        XCTAssertEqual(makeScheduler(.tipOfTheDay).choice, .none)
        let eligibilityTime = defaults.double(forKey: eligibilityKey)
        date.addTimeInterval(day)
        XCTAssertEqual(makeScheduler(.tipOfTheDay).choice, .none)
        date.addTimeInterval(day)
        let eligible = makeScheduler(.tipOfTheDay)
        XCTAssertEqual(eligible.choice, .tipOfTheDay)
        _ = eligible.prepareForStartupActivities()
        XCTAssertEqual(makeScheduler(.tipOfTheDay).choice, .none)
        date.addTimeInterval(day)
        XCTAssertEqual(makeScheduler(.tipOfTheDay).choice, .tipOfTheDay)
        XCTAssertEqual(defaults.double(forKey: eligibilityKey), eligibilityTime)
    }

    func testChoiceRemainsLatchedForCurrentLaunch() {
        defaults.set(1, forKey: eligibilityKey)
        let scheduler = makeScheduler(.tipOfTheDay)
        defaults.set(date.addingTimeInterval(10 * day).timeIntervalSinceReferenceDate, forKey: nextPromptKey)
        XCTAssertTrue(scheduler.permissionPromptAllowed)
        _ = scheduler.prepareForStartupActivities()
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), date.addingTimeInterval(day).timeIntervalSinceReferenceDate)
    }
}
