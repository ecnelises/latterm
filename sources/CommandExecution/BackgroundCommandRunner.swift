//
//  BackgroundCommandRunner.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/20/20.
//

import Foundation
import os

private let backgroundCommandRunnerDidSelectNotificationName = "iTermBackgroundCommandRunnerDidSelectNotificationNotificationName"

private final class BackgroundCommandRunnerNotificationObserver: NSObject {
    static let shared = BackgroundCommandRunnerNotificationObserver()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didSelectNotification(_:)),
            name: Notification.Name(backgroundCommandRunnerDidSelectNotificationName),
            object: nil)
    }

    @objc private func didSelectNotification(_ notification: Notification) {
        guard let identifier = notification.userInfo?["identifier"] as? String else {
            RLog("Did select notification with identifier (null)")
            return
        }
        RLog("Did select notification with identifier \(identifier)")
        let maybeEntry: iTermScriptHistoryEntry? = iTermScriptHistory.sharedInstance().entry(withIdentifier: identifier)
        guard let entry = maybeEntry else {
            return
        }
        iTermScriptConsole.sharedInstance().revealTail(of: entry)
    }
}

/// Runs a command through `/bin/sh -c` and streams output to the Script Console, optionally posting
/// a user notification if it exits with a non-zero status.
@objc(iTermBackgroundCommandRunner)
class iTermBackgroundCommandRunner: NSObject, CommandRunnerProtocol {
    private static let activeRunners = OSAllocatedUnfairLock(initialState: [iTermBackgroundCommandRunner]())
    private static let rateLimit = iTermRateLimitedUpdate(name: "Background command runner", minimumInterval: 10)

    @objc var command: String = ""
    @objc var shell: String = ""
    @objc var title: String = ""
    @objc var notificationTitle: String?
    @objc var completion: ((Int32) -> Void)?

    private let pathLock = OSAllocatedUnfairLock<String?>(initialState: nil)
    @objc var path: String? {
        get { pathLock.withLock { $0 } }
        set { pathLock.withLock { $0 = newValue } }
    }

    private var running = false

    @objc override init() {
        super.init()
    }

    @objc(initWithCommand:shell:title:)
    convenience init(command: String?, shell: String?, title: String?) {
        self.init()
        self.command = command ?? ""
        self.shell = shell ?? ""
        self.title = title ?? ""
    }

    override var description: String {
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) command=\(command) shell=\(shell) title=\(title) path=\(path ?? "(null)") running=\(running)>"
    }

    private var redactedDescription: String {
        // Like description, with the command line replaced by its length so always-on ring logs do
        // not leak command text.
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) command=[redacted len=\(command.count)] shell=\(shell) title=\(title) path=\(path ?? "(null)") running=\(running)>"
    }

    @objc func run() {
        DLog("\(self)")
        if path != nil {
            reallyRun()
            return
        }
        DLog("Exfiltrate path")
        iTermSlowOperationGateway.sharedInstance().exfiltrateEnvironmentVariableNamed("PATH", shell: shell) { [weak self] value in
            guard let self else { return }
            self.path = value ?? ""
            DLog("\(self)")
            DispatchQueue.main.async {
                self.reallyRun()
            }
        }
    }

    private static func maybeNotify(_ block: @escaping (Int) -> Void) {
        rateLimit.performRateLimitedBlock {
            DLog("Called")
            block(Int(rateLimit.deferCount))
        }
    }

    private func reallyRun() {
        RLog("\(redacted: self, or: self.redactedDescription)")
        it_assert(!running)
        running = true

        let runner = iTermCommandRunner(command: "/bin/sh",
                                        withArguments: ["-c", command],
                                        path: FileManager.default.currentDirectoryPath)
        if let path, !path.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = path
            runner.environment = environment
        }

        let entry = iTermScriptHistoryEntry(name: title,
                                            fullPath: command,
                                            identifier: UUID().uuidString,
                                            relaunch: nil)
        iTermScriptHistory.sharedInstance().addEntry(entry)
        entry.addOutput("Run command:\n\(command)\n") {}

        Self.activeRunners.withLock { $0.append(self) }

        runner.outputHandler = { [weak self] data, handled in
            let string: String
            if let data {
                string = String(data: data, encoding: .utf8) ?? (data as NSData).it_hexEncoded()
            } else {
                string = ""
            }
            DLog("\(self?.description ?? "(null)"): add output \(string)")
            entry.addOutput(string, completion: handled)
        }
        runner.completion = { [weak self] status in
            DispatchQueue.main.async {
                self?.didComplete(withStatus: status, entry: entry)
            }
        }
        runner.run()
    }

    private func didComplete(withStatus status: Int32, entry: iTermScriptHistoryEntry) {
        RLog("\(redacted: self, or: self.redactedDescription)")
        Self.activeRunners.withLock { list in
            list.removeAll { $0 === self }
        }
        if status != 0 {
            entry.addOutput("\nFinished with status \(status)") {}
        }
        entry.stopRunning()
        running = false

        if let notificationTitle, status != 0 {
            RLog("\(redacted: self, or: self.redactedDescription) post notification with identifier \(entry.identifier)")
            _ = BackgroundCommandRunnerNotificationObserver.shared
            Self.maybeNotify { deferCount in
                var detail = "\nFinished with status \(status)"
                if deferCount > 1 {
                    let plural = deferCount > 2 ? "s" : ""
                    detail += ", plus \(deferCount - 1) other error\(plural) silenced."
                }
                iTermNotificationController.sharedInstance().postNotification(
                    withTitle: notificationTitle,
                    detail: detail,
                    callbackNotificationName: backgroundCommandRunnerDidSelectNotificationName,
                    callbackNotificationUserInfo: ["identifier": entry.identifier])
            }
        }
        completion?(status)
    }
}

/// Deferred background command runner returned by `iTermBackgroundCommandRunnerPool` until a slot opens.
@objc(iTermBackgroundCommandRunnerPromise)
class iTermBackgroundCommandRunnerPromise: iTermBackgroundCommandRunner {
    @objc var terminationBlock: ((iTermBackgroundCommandRunner, Int32) -> Void)?
    private var fulfilled = false

    @objc func fulfill() {
        guard !fulfilled else {
            return
        }
        fulfilled = true
        run()
    }

    override func run() {
        guard fulfilled else {
            return
        }
        super.run()
    }
}
