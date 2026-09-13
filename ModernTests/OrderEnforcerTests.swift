import XCTest
@testable import iTerm2SharedARC

final class OrderEnforcerTests: XCTestCase {
    func testObjectiveCRuntimeNamesRemainAvailable() {
        XCTAssertTrue(NSClassFromString("iTermOrderEnforcer") === iTermOrderEnforcer.self)
        XCTAssertEqual(NSStringFromProtocol(iTermOrderedToken.self), "iTermOrderedToken")
        let enforcer = iTermOrderEnforcer()
        XCTAssertEqual(NSStringFromClass(type(of: enforcer.newToken())), "iTermOrderedToken")
    }

    func testEveryCompletionOrderRejectsOnlyResultsOlderThanLatestCommit() {
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2],
                      [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            let enforcer = iTermOrderEnforcer()
            let tokens = (0..<3).map { _ in enforcer.newToken() }
            var latest = -1
            for index in order {
                let accepted = index > latest
                XCTAssertEqual(tokens[index].peek(), accepted, "Order: \(order)")
                XCTAssertEqual(tokens[index].commit(), accepted, "Order: \(order)")
                latest = max(index, latest)
                XCTAssertFalse(tokens[index].peek())
            }
        }
    }

    func testPeekDoesNotCommitOrInvalidateEarlierResults() {
        let enforcer = iTermOrderEnforcer()
        let first = enforcer.newToken()
        let second = enforcer.newToken()
        XCTAssertTrue(second.peek())
        XCTAssertTrue(second.peek())
        XCTAssertTrue(first.commit())
        XCTAssertTrue(second.peek())
        XCTAssertTrue(second.commit())
    }

    func testCreatingNewRequestDoesNotInvalidateCompletedResult() {
        let enforcer = iTermOrderEnforcer()
        let first = enforcer.newToken()
        let second = enforcer.newToken()
        XCTAssertTrue(first.commit())
        XCTAssertTrue(second.commit())
        let third = enforcer.newToken()
        XCTAssertTrue(third.peek())
        XCTAssertTrue(third.commit())
    }

    func testRejectedCommitDoesNotRewindLatestResult() {
        let enforcer = iTermOrderEnforcer()
        let oldest = enforcer.newToken()
        let middle = enforcer.newToken()
        let latest = enforcer.newToken()
        XCTAssertTrue(latest.commit())
        XCTAssertFalse(oldest.commit())
        XCTAssertFalse(middle.peek())
        XCTAssertFalse(middle.commit())
        XCTAssertTrue(enforcer.newToken().commit())
    }

    func testTokenDoesNotRetainEnforcer() {
        var enforcer: iTermOrderEnforcer? = iTermOrderEnforcer()
        weak var weakEnforcer = enforcer
        let token = enforcer!.newToken()
        XCTAssertTrue(token.peek())
        enforcer = nil
        XCTAssertNil(weakEnforcer)
        XCTAssertFalse(token.peek())
        XCTAssertFalse(token.commit())
    }

    func testIndependentEnforcersDoNotInvalidateEachOther() {
        let first = iTermOrderEnforcer()
        let second = iTermOrderEnforcer()
        let token = first.newToken()
        for _ in 0..<10 {
            XCTAssertTrue(second.newToken().commit())
        }
        XCTAssertTrue(token.commit())
    }

    func testConcurrentCompletionsLeaveNewestResultCommitted() {
        let enforcer = iTermOrderEnforcer()
        let tokens = (0..<256).map { _ in enforcer.newToken() }
        DispatchQueue.concurrentPerform(iterations: tokens.count) { index in
            _ = tokens[index].peek()
            _ = tokens[index].commit()
        }
        // Even the newest token must now be obsolete, regardless of callback order.
        XCTAssertTrue(tokens.allSatisfy { !$0.peek() })
        XCTAssertTrue(enforcer.newToken().commit())
    }

    func testConcurrentRequestsAndCompletions() {
        let enforcer = iTermOrderEnforcer()
        let lock = NSLock()
        var tokens: [iTermOrderedToken] = []
        DispatchQueue.concurrentPerform(iterations: 256) { _ in
            let token = enforcer.newToken()
            _ = token.commit()
            lock.lock()
            tokens.append(token)
            lock.unlock()
        }
        XCTAssertTrue(tokens.allSatisfy { !$0.peek() })
        XCTAssertTrue(enforcer.newToken().commit())
    }
}
