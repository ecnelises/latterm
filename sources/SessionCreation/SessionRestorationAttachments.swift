import Foundation

/// Restoring the PTY task must reuse the manager and serial queue that opened the connection.
private final class RestoredJobAttachment: NSObject, iTermPartialAttachment {
    var partialResult: iTermJobManagerPartialResult!
    var jobManager: iTermJobManager!
    var queue: DispatchQueue!

    init(result: iTermJobManagerPartialResult, manager: iTermJobManager, queue: DispatchQueue) {
        partialResult = result
        jobManager = manager
        self.queue = queue
    }
}

typealias RestorationAttachments = [NSDictionary: iTermPartialAttachment]

extension PTYSession {
    @objc(openPartialAttachmentsForArrangement:completion:)
    static func openPartialAttachments(forArrangement arrangement: PTYTab.Arrangement,
                                       completion: @escaping (RestorationAttachments) -> Void) {
        guard arrangement[SESSION_ARRANGEMENT_TMUX_PANE] == nil,
              iTermAdvancedSettingsModel.runJobsInServers(),
              iTermMultiServerJobManager.available(),
              let identifier = arrangement[SESSION_ARRANGEMENT_SERVER_DICT] as? PTYTab.Arrangement else {
            completion([:])
            return
        }
        openJobAttachment(for: identifier, makeManager: iTermMultiServerJobManager.init(queue:), completion: completion)
    }

    static func openJobAttachment(for identifier: [AnyHashable: Any],
                                  makeManager: (DispatchQueue) -> iTermMultiServerJobManager?,
                                  completion: @escaping (RestorationAttachments) -> Void) {
        var connection = iTermGeneralServerConnection()
        guard iTermMultiServerJobManager.getGeneralConnection(&connection, fromRestorationIdentifier: identifier),
              connection.type == .multi else {
            completion([:])
            return
        }
        let pid = NSNumber(value: connection.multi.pid)
        let queue = DispatchQueue(label: iTermThread<AnyObject>.uniqueQueueLabel(withName: "com.iterm2.job-manager"))
        guard let manager = makeManager(queue) else {
            completion([:])
            return
        }
        DLog("Requesting partial attachment for pid \(pid)")
        manager.asyncPartialAttach(toServer: connection, withProcessID: pid) { result in
            RLog("Received partial attachment for pid \(pid)")
            completion([identifier as NSDictionary: RestoredJobAttachment(result: result, manager: manager, queue: queue)])
        }
    }
}

extension PTYTab {
    /// A tab is restored as a unit. Deliver its complete map on the main queue even when a
    /// legacy layout has a session at the root and its job manager calls back on a worker.
    @objc(openPartialAttachmentsForArrangement:completion:)
    static func openPartialAttachments(forArrangement arrangement: Arrangement,
                                       completion: @escaping (RestorationAttachments) -> Void) {
        var sessions = [Arrangement]()
        if let root = arrangement[TAB_ARRANGEMENT_ROOT] as? Arrangement {
            visitSessionLeaves(in: root) { session in
                if let session { sessions.append(session) }
                return true
            }
        }
        let batch = RestorationAttachmentBatch(count: sessions.count, completion: completion)
        for session in sessions {
            PTYSession.openPartialAttachments(forArrangement: session) { attachments in
                DispatchQueue.main.async { batch.receive(attachments) }
            }
        }
    }
}

/// A tab collects sessions and a window collects tabs. Only the window can finish
/// early at a deadline. All deliveries and deadline callbacks run on the main queue.
final class RestorationAttachmentBatch {
    private var remaining: Int
    private var pending = RestorationAttachments()
    private var completion: ((RestorationAttachments) -> Void)?
    private let late: (([iTermPartialAttachment]) -> Void)?

    init(count: Int, completion: @escaping (RestorationAttachments) -> Void,
         late: (([iTermPartialAttachment]) -> Void)? = nil) {
        remaining = count
        self.completion = completion
        self.late = late
        if count == 0 { DispatchQueue.main.async { self.finish() } }
    }

    func receive(_ attachments: RestorationAttachments) {
        guard completion != nil else {
            late?(Array(attachments.values))
            return
        }
        pending.merge(attachments) { _, new in new }
        remaining -= 1
        if remaining == 0 { finish() }
    }

    func finish() {
        guard let completion else { return }
        self.completion = nil
        let result = pending
        pending.removeAll()
        completion(result)
    }
}

extension PseudoTerminal {
    @objc(openPartialAttachmentsForArrangement:timeout:completion:)
    func openPartialAttachments(forArrangement arrangement: PTYTab.Arrangement,
                                timeout: @escaping ([iTermPartialAttachment]) -> Void,
                                completion: @escaping (RestorationAttachments) -> Void) {
        let tabs = arrangement[TERMINAL_ARRANGEMENT_TABS] as? [PTYTab.Arrangement] ?? []
        let batch = RestorationAttachmentBatch(count: tabs.count, completion: completion, late: timeout)
        for tab in tabs {
            PTYTab.openPartialAttachments(forArrangement: tab, completion: batch.receive)
        }
        let deadline = DispatchTime.now() + iTermAdvancedSettingsModel.timeoutForDaemonAttachment()
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: batch.finish)
    }
}
