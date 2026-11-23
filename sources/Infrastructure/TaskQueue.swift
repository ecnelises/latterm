//
//  TaskQueue.swift
//  Latterm
//

import Foundation
import Synchronization

/// Fast thread-safe FIFO task queue with atomic flag signaling for `TokenExecutor`.
final class iTermTaskQueue: CustomStringConvertible, @unchecked Sendable {
    typealias Task = () -> Void

    private struct State {
        // Drain one batch while producers append to the next. Clear consumed
        // slots immediately so captured sessions can be released after execution.
        private var draining: [Task?] = []
        private var pending: [Task?] = []
        private var head = 0

        var count: Int { draining.count - head + pending.count }

        mutating func append(_ task: @escaping Task) {
            pending.append(task)
        }

        mutating func appendTasks(_ tasks: [Task]) {
            pending.append(contentsOf: tasks)
        }

        mutating func dequeue() -> Task? {
            if head == draining.count {
                guard !pending.isEmpty else { return nil }
                draining.removeAll(keepingCapacity: true)
                swap(&draining, &pending)
                head = 0
            }
            let task = draining[head]
            draining[head] = nil
            head += 1
            return task
        }
    }

    private let state = Synchronization.Mutex(State())
    private let flags = Atomic<Int64>(0)

    var count: Int {
        state.withLock { $0.count }
    }

    func append(_ task: @escaping Task) {
        state.withLock { $0.append(task) }
    }

    func appendTasks(_ tasks: [Task]) {
        state.withLock { $0.appendTasks(tasks) }
    }

    func dequeue() -> Task? {
        state.withLock { $0.dequeue() }
    }

    @discardableResult
    func setFlag(_ flag: Int64) -> Int64 {
        flags.bitwiseOr(flag, ordering: .acquiringAndReleasing).oldValue
    }

    func resetFlags() -> Int64 {
        flags.exchange(0, ordering: .acquiringAndReleasing)
    }

    var description: String {
        "<iTermTaskQueue: \(Unmanaged.passUnretained(self).toOpaque()) count=\(count)>"
    }
}
