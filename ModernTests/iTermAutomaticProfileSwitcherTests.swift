//
//  iTermAutomaticProfileSwitcherTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class iTermAutomaticProfileSwitcherTests: XCTestCase {
    private final class MockAPSDelegate: NSObject, iTermAutomaticProfileSwitcherDelegate {
        var currentProfile: [AnyHashable: Any] = [:]
        var allProfiles: [[AnyHashable: Any]] = []
        var loadProfileCount = 0

        func automaticProfileSwitcherLoadProfile(_ savedProfile: iTermSavedProfile) {
            loadProfileCount += 1
            if let original = savedProfile.originalProfile {
                currentProfile = original
            }
        }

        func automaticProfileSwitcherCurrentProfile() -> [AnyHashable: Any] {
            return currentProfile
        }

        func automaticProfileSwitcherCurrentSavedProfile() -> iTermSavedProfile {
            let saved = iTermSavedProfile()
            saved.originalProfile = currentProfile
            saved.profile = currentProfile
            return saved
        }

        func automaticProfileSwitcherAllProfiles() -> [[AnyHashable: Any]] {
            return allProfiles
        }

        func automaticProfileSwitcherSessionName() -> String {
            return "TestSession"
        }
    }

    private var delegate: MockAPSDelegate!
    private var aps: iTermAutomaticProfileSwitcher!

    private let profileHostA: [AnyHashable: Any] = [KEY_NAME: "host=a", KEY_GUID: "1", KEY_BOUND_HOSTS: ["a"]]
    private let profileHostB: [AnyHashable: Any] = [KEY_NAME: "host=b", KEY_GUID: "2", KEY_BOUND_HOSTS: ["b"]]
    private let profilePathDir1: [AnyHashable: Any] = [KEY_NAME: "path=dir1", KEY_GUID: "3", KEY_BOUND_HOSTS: ["/dir1"]]
    private let profilePathDir1AndSubs: [AnyHashable: Any] = [KEY_NAME: "path=dir1AndSubs", KEY_GUID: "3", KEY_BOUND_HOSTS: ["/dir1/*"]]
    private let profilePathDir2: [AnyHashable: Any] = [KEY_NAME: "path=dir2", KEY_GUID: "4", KEY_BOUND_HOSTS: ["/dir2"]]
    private let profileUserX: [AnyHashable: Any] = [KEY_NAME: "user=x", KEY_GUID: "5", KEY_BOUND_HOSTS: ["x@"]]
    private let profileUserY: [AnyHashable: Any] = [KEY_NAME: "user=y", KEY_GUID: "6", KEY_BOUND_HOSTS: ["y@"]]
    private let profileUserGeorgeHostItermPathHome: [AnyHashable: Any] = [
        KEY_NAME: "user=george host=iterm2.com path=home",
        KEY_GUID: "7",
        KEY_BOUND_HOSTS: ["george@iterm2.com:/home"]
    ]
    private let profileUserGeorgePathHome: [AnyHashable: Any] = [
        KEY_NAME: "user=george path=home",
        KEY_GUID: "8",
        KEY_BOUND_HOSTS: ["george@:/home"]
    ]
    private let profileUserGeorgeHostIterm: [AnyHashable: Any] = [
        KEY_NAME: "user=george host=iterm2.com",
        KEY_GUID: "9",
        KEY_BOUND_HOSTS: ["george@iterm2.com"]
    ]
    private let profileHostItermPathHome: [AnyHashable: Any] = [
        KEY_NAME: "host=iterm2.com path=home",
        KEY_GUID: "10",
        KEY_BOUND_HOSTS: ["iterm2.com:/home"]
    ]
    private let profileHostIterm: [AnyHashable: Any] = [
        KEY_NAME: "host=iterm2.com",
        KEY_GUID: "11",
        KEY_BOUND_HOSTS: ["iterm2.com"]
    ]
    private let profileUserGeorge: [AnyHashable: Any] = [
        KEY_NAME: "user=george",
        KEY_GUID: "12",
        KEY_BOUND_HOSTS: ["george@"]
    ]
    private let profilePathHome: [AnyHashable: Any] = [
        KEY_NAME: "path=home",
        KEY_GUID: "13",
        KEY_BOUND_HOSTS: ["/home"]
    ]
    private let profileHostAllDotCom: [AnyHashable: Any] = [
        KEY_NAME: "host=*.com",
        KEY_GUID: "14",
        KEY_BOUND_HOSTS: ["*.com"]
    ]
    private let profileAllPaths: [AnyHashable: Any] = [
        KEY_NAME: "path=/*",
        KEY_GUID: "15",
        KEY_BOUND_HOSTS: ["/*"]
    ]
    private let profileJobX: [AnyHashable: Any] = [
        KEY_NAME: "job=x",
        KEY_GUID: "16",
        KEY_BOUND_HOSTS: ["&x"]
    ]
    private let profileJobY: [AnyHashable: Any] = [
        KEY_NAME: "job=y",
        KEY_GUID: "17",
        KEY_BOUND_HOSTS: ["&y"]
    ]
    private let profileHostAll: [AnyHashable: Any] = [
        KEY_NAME: "host=*",
        KEY_GUID: "18",
        KEY_BOUND_HOSTS: ["*"]
    ]
    private let profileWithoutBoundHosts: [AnyHashable: Any] = [
        KEY_NAME: "Boring",
        KEY_GUID: "19"
    ]

    override func setUp() {
        super.setUp()
        delegate = MockAPSDelegate()
        delegate.currentProfile = [KEY_NAME: "Initial Profile", KEY_GUID: "initial"]
        aps = iTermAutomaticProfileSwitcher(delegate: delegate)
    }

    private func guid(_ profile: [AnyHashable: Any]) -> String? {
        return profile[KEY_GUID] as? String
    }

    private func update(hostname: String? = "whatever",
                        username: String? = "whatever",
                        path: String? = "whatever",
                        job: String? = "whatever",
                        commandLine: String? = nil) {
        aps.setHostname(hostname,
                        username: username,
                        path: path,
                        job: job,
                        commandLine: commandLine,
                        expressionValueProvider: nil)
    }

    func testSwitchesOnHostName() {
        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostA, profileHostB]
        update(hostname: "b")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostB))
    }

    func testSwitchesOnUserName() {
        delegate.currentProfile = profileUserX
        delegate.allProfiles = [profileUserX, profileUserY]
        update(username: "y")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserY))
    }

    func testSwitchesOnPath() {
        delegate.currentProfile = profilePathDir1
        delegate.allProfiles = [profilePathDir1, profilePathDir2]
        update(path: "/dir2")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profilePathDir2))
    }

    func testSwitchesOnWildcard() {
        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostA, profileHostAllDotCom]
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostAllDotCom))
    }

    func testSwitchesOnJob() {
        delegate.currentProfile = profileJobX
        delegate.allProfiles = [profileJobX, profileJobY]
        update(job: "y")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileJobY))
    }

    func testMatchAll() {
        delegate.currentProfile = profileWithoutBoundHosts
        delegate.allProfiles = [profileWithoutBoundHosts, profileHostAll]
        update()
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostAll))
    }

    func testPriorityOrder() {
        delegate.currentProfile = profileHostA

        delegate.allProfiles = [profileUserGeorgeHostItermPathHome, profileUserGeorgeHostIterm]
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorgeHostItermPathHome))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileUserGeorgeHostIterm, profileUserGeorgePathHome]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorgeHostIterm))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileJobX, profileUserGeorgePathHome]
        aps.markDirty()
        update(username: "george", path: "/home", job: "x")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileJobX))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostItermPathHome, profileUserGeorgePathHome]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostItermPathHome))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostItermPathHome, profileHostIterm]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostItermPathHome))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostIterm, profileUserGeorge]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostIterm))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileUserGeorge, profilePathHome]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorge))

        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostIterm, profileHostAllDotCom]
        aps.markDirty()
        update(hostname: "iterm2.com", username: "george", path: "/home")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostIterm))
    }

    func testPreferSpecificRuleEvenIfStackHasMatch() {
        delegate.currentProfile = profileAllPaths
        delegate.allProfiles = [profileAllPaths, profilePathDir1AndSubs]

        update(hostname: "iterm2.com", username: "george", path: "/", job: "job")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileAllPaths))

        update(hostname: "iterm2.com", username: "george", path: "/dir1/foo", job: "job")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profilePathDir1AndSubs))

        update(hostname: "iterm2.com", username: "george", path: "/dir1/foo/temp", job: "job")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profilePathDir1AndSubs))
    }

    func testWalkUpStack() {
        delegate.currentProfile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]

        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "job")
        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorgeHostIterm))
    }

    func testDontChangeProfileIfSame() {
        delegate.currentProfile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profilePathDir1]
        update(hostname: "iterm2.com", username: "george", path: "/", job: "job")
        XCTAssertEqual(delegate.loadProfileCount, 0)
    }

    func testRestoreOriginalProfileWhenNothingMatches() {
        delegate.currentProfile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]

        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")
        update(hostname: "iterm2.com", username: "george", path: "/home", job: "job")
        update(hostname: "qwerty", username: "uiop", path: "asdf", job: "job")
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostIterm))
    }

    func testSaveAndRestore() {
        delegate.currentProfile = profileHostIterm
        delegate.allProfiles = [profileHostIterm, profileUserGeorgeHostIterm, profileUserGeorgeHostItermPathHome]
        update(hostname: "iterm2.com", username: "george", path: "bogus path", job: "job")

        let state = aps.savedState()
        let aps2 = iTermAutomaticProfileSwitcher(delegate: delegate, savedState: state)
        XCTAssertEqual(aps.profileStackString, aps2.profileStackString)

        aps2.setHostname("iterm2.com", username: "george", path: "/home", job: "job", commandLine: nil, expressionValueProvider: nil)
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorgeHostItermPathHome))

        aps2.setHostname("iterm2.com", username: "george", path: "asdf", job: "job", commandLine: nil, expressionValueProvider: nil)
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileUserGeorgeHostIterm))

        aps2.setHostname("qwerty", username: "uiop", path: "asdf", job: "job", commandLine: nil, expressionValueProvider: nil)
        XCTAssertEqual(guid(delegate.currentProfile), guid(profileHostIterm))
    }

    func testStickyRuleClearsStack() {
        let stickyProfile: [AnyHashable: Any] = [
            KEY_NAME: "sticky",
            KEY_GUID: "sticky-guid",
            KEY_BOUND_HOSTS: ["!sticky.host"]
        ]
        delegate.currentProfile = profileHostA
        delegate.allProfiles = [profileHostA, stickyProfile]

        update(hostname: "sticky.host", username: "user", path: "/", job: "zsh")
        XCTAssertEqual(guid(delegate.currentProfile), "sticky-guid")
        XCTAssertEqual(aps.profileStackString, "sticky ")

        update(hostname: "unmatched.host", username: "user", path: "/", job: "zsh")
        XCTAssertEqual(guid(delegate.currentProfile), "sticky-guid")
    }

    func testUserNameWithAtSign() {
        let profile: [AnyHashable: Any] = [KEY_NAME: "Default", KEY_GUID: "200", KEY_BOUND_HOSTS: ["hostname*"]]
        delegate.allProfiles = [profileUserGeorge, profile]
        update(hostname: "hostname.com", username: "user@example.com", path: "/")
        XCTAssertEqual(guid(delegate.currentProfile), "200")
    }
}
