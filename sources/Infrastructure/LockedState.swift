import Foundation

// Shared mutable state with synchronous, exclusive access on macOS 12 and later.
// References protected by this lock must not escape the access closure.
final class LockedState<State>: @unchecked Sendable {
    private let mutex = Mutex()
    private var state: State

    init(initialState: State) {
        state = initialState
    }

    @discardableResult
    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        try mutex.sync { try body(&state) }
    }
}
