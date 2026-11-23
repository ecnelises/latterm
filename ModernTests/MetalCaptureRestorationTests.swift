import XCTest
@testable import iTerm2SharedARC

final class MetalCaptureRestorationTests: XCTestCase {
    func testPendingCaptureHoldsRestorationUntilDriverIsReady() {
        var pending = true
        var restored = 0
        weak var weakToken: NSObject?
        autoreleasepool {
            var timer: Timer?
            autoreleasepool {
                let token = NSObject()
                weakToken = token
                timer = MetalCaptureRestoration.restorationTimer(isPending: { pending }) {
                    XCTAssertTrue(weakToken === token)
                    restored += 1
                }
            }
            timer?.fire()
            XCTAssertNotNil(weakToken)
            XCTAssertEqual(restored, 0)
            pending = false
            timer?.fire()
            timer?.fire()
            XCTAssertEqual(restored, 1)
            XCTAssertEqual(timer?.isValid, false)
        }
        XCTAssertNil(weakToken)
    }
}
