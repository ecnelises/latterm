import XCTest
@testable import iTerm2SharedARC

final class LaunchPromptSchedulerTests: XCTestCase {
    private let nextPromptKey = "NoSyncNextAnnoyanceTime"
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
    }

    func testCooldownExpiresAtExactBoundary() {
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: nextPromptKey)
        XCTAssertEqual(makeScheduler(.defaultPasteBehaviorChangeWarning).choice,
                       .defaultPasteBehaviorChangeWarning)
    }

    func testPasteWarningCooldownStartsAtDisplayTimeAndPersistsAcrossLaunches() {
        let scheduler = makeScheduler(.defaultPasteBehaviorChangeWarning)
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
        date.addTimeInterval(20)
        XCTAssertTrue(scheduler.prepareToShowPasteWarning())
        let cooldown = date.addingTimeInterval(day).timeIntervalSinceReferenceDate
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), cooldown)
        XCTAssertEqual(makeScheduler(.defaultPasteBehaviorChangeWarning).choice, .none)
        date.addTimeInterval(day)
        XCTAssertEqual(makeScheduler(.defaultPasteBehaviorChangeWarning).choice,
                       .defaultPasteBehaviorChangeWarning)
    }

    func testNoPromptLeavesPersistentStateUntouched() {
        let scheduler = makeScheduler(.none)
        XCTAssertFalse(scheduler.prepareToShowPasteWarning())
        XCTAssertNil(defaults.object(forKey: nextPromptKey))
    }

    func testChoiceRemainsLatchedForCurrentLaunch() {
        let scheduler = makeScheduler(.defaultPasteBehaviorChangeWarning)
        defaults.set(date.addingTimeInterval(10 * day).timeIntervalSinceReferenceDate, forKey: nextPromptKey)
        XCTAssertEqual(scheduler.choice, .defaultPasteBehaviorChangeWarning)
        XCTAssertTrue(scheduler.prepareToShowPasteWarning())
        XCTAssertEqual(defaults.double(forKey: nextPromptKey), date.addingTimeInterval(day).timeIntervalSinceReferenceDate)
    }
}
