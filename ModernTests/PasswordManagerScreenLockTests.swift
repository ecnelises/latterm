import XCTest
@testable import iTerm2SharedARC

final class PasswordManagerScreenLockTests: XCTestCase {
    func testLockRevokesAuthenticationWithoutOpeningAWindow() {
        let center = NotificationCenter()
        let provider = PasswordManagerDataSourceProvider(screenLockNotificationCenter: center,
                                                        requiresAuthenticationAfterScreenLock: { true })
        provider.markAuthenticatedForTesting()
        XCTAssertTrue(provider.authenticated)
        center.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertFalse(provider.authenticated)
        XCTAssertNil(provider.dataSource)
    }

    func testLockPreservesAuthenticationWhenUserDisabledReauthentication() {
        let center = NotificationCenter()
        let provider = PasswordManagerDataSourceProvider(screenLockNotificationCenter: center,
                                                        requiresAuthenticationAfterScreenLock: { false })
        provider.markAuthenticatedForTesting()
        center.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        XCTAssertTrue(provider.authenticated)
    }
}
