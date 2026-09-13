import Foundation

@objc(iTermOrderedToken) protocol iTermOrderedToken: NSObjectProtocol {
    func commit() -> Bool
    func peek() -> Bool
}

// Tokens follow request order, so an older asynchronous result cannot replace
// a newer result that has already committed. Safe to use from multiple threads.
@objc(iTermOrderEnforcer)
final class iTermOrderEnforcer: NSObject {
    private let lock = NSLock()
    private var generation = 0
    private var lastCommitted = -1

    @objc func newToken() -> iTermOrderedToken {
        lock.lock()
        let next = generation
        generation += 1
        lock.unlock()
        return OrderedToken(generation: next, enforcer: self)
    }

    fileprivate func commit(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation > lastCommitted else {
            DLog("Reject out of order token with generation \(generation)")
            return false
        }
        lastCommitted = generation
        return true
    }

    fileprivate func peek(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation > lastCommitted
    }
}

@objc(iTermOrderedToken)
private final class OrderedToken: NSObject, iTermOrderedToken {
    private let lock = NSLock()
    private let generation: Int
    private weak var enforcer: iTermOrderEnforcer?
    private var committed = false

    init(generation: Int, enforcer: iTermOrderEnforcer) {
        self.generation = generation
        self.enforcer = enforcer
        super.init()
    }

    override var description: String { String(generation) }

    func commit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        it_assert(!committed, "An ordered token may only be committed once")
        committed = true
        return enforcer?.commit(generation) ?? false
    }

    func peek() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enforcer?.peek(generation) ?? false
    }
}
