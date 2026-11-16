//
//  CommandRunner.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

import Cocoa
import Darwin
import Foundation
import os

/// Common interface implemented by command-runner classes managed by `iTermCommandRunnerPool`.
@objc(iTermCommandRunner)
protocol CommandRunnerProtocol: NSObjectProtocol {
    @objc var completion: ((Int32) -> Void)? { get set }
    @objc func run()
}

/// Runs an external process asynchronously or synchronously with streaming I/O and timeout support.
@objc(iTermCommandRunner)
class iTermCommandRunner: NSObject, CommandRunnerProtocol {
    private static let errorDomain = "com.iterm2.command-runner"

    @objc var command: String = ""
    @objc var arguments: [String] = []
    @objc var currentDirectoryPath: String = ""
    @objc var completion: ((Int32) -> Void)?
    /// Invoked with each output chunk; call its nested closure once processing finishes to apply backpressure.
    @objc var outputHandler: ((Data?, @escaping () -> Void) -> Void)?
    @objc var environment: [String: String]?
    @objc var callbackQueue: DispatchQueue? = DispatchQueue.main

    private var task: Process? = Process()
    private let pipe = Pipe()
    private let inputPipe = Pipe()
    private let readingQueue = DispatchQueue(label: "com.iterm2.crun-reading")
    private let writingQueue = DispatchQueue(label: "com.iterm2.crun-writing")
    private let waitingQueue = DispatchQueue(label: "com.iterm2.crun-waiting")
    private let stateLock = OSAllocatedUnfairLock(initialState: (running: false, terminateAfterLaunch: false))

    private var isRunning: Bool {
        get { stateLock.withLock { $0.running } }
        set { stateLock.withLock { $0.running = newValue } }
    }

    private var shouldTerminateAfterLaunch: Bool {
        get { stateLock.withLock { $0.terminateAfterLaunch } }
        set { stateLock.withLock { $0.terminateAfterLaunch = newValue } }
    }

    @objc override init() {
        super.init()
    }

    @objc(initWithCommand:withArguments:path:)
    convenience init(command: String, withArguments arguments: [String], path currentDirectoryPath: String) {
        self.init()
        self.command = command
        self.arguments = arguments
        self.currentDirectoryPath = currentDirectoryPath
        self.callbackQueue = DispatchQueue.main
    }

    override var description: String {
        let pid = task?.processIdentifier ?? 0
        return "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) pid=\(pid)>"
    }

    /// Unzips `zipURL` into `destination` using `/usr/bin/unzip`.
    @objc(unzipURL:withArguments:destination:callbackQueue:completion:)
    static func unzipURL(_ zipURL: URL,
                         withArguments arguments: [String],
                         destination: String,
                         callbackQueue: DispatchQueue?,
                         completion: @escaping (Error?) -> Void) {
        RLog("zipURL=\(zipURL) arguments=\(redacted: arguments, or: "[\(arguments.count) args]") destination=\(destination)")

        let fullArgs = arguments + [zipURL.path]
        let runner = iTermCommandRunner(command: "/usr/bin/unzip",
                                        withArguments: fullArgs,
                                        path: destination)
        var errorText = ""
        runner.outputHandler = { data, handled in
            if let data, let string = String(data: data, encoding: .utf8) {
                DLog("output: \(string)")
                errorText.append(string)
            } else {
                DLog("output: (non-UTF-8)")
                errorText.append("\n[non-UTF-8 output]\n")
            }
            let maxLength = 1024 * 1024
            if errorText.count > maxLength {
                errorText.removeFirst(errorText.count - maxLength)
            }
            handled()
        }
        runner.completion = { status in
            RLog("completed status=\(status)")
            if status == 0 {
                completion(nil)
                return
            }
            let error = NSError(domain: errorDomain,
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: errorText])
            completion(error)
        }
        runner.callbackQueue = callbackQueue ?? DispatchQueue.main
        runner.run()
    }

    /// Async wrapper for `unzipURL(_:withArguments:destination:callbackQueue:completion:)`.
    static func unzipURL(_ zipURL: URL,
                         withArguments arguments: [String],
                         destination: String,
                         callbackQueue: DispatchQueue?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unzipURL(zipURL,
                     withArguments: arguments,
                     destination: destination,
                     callbackQueue: callbackQueue) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Compresses `URLs` into `zipURL` relative to `baseURL` using `/usr/bin/zip`.
    @objc(zipURLs:arguments:toZipURL:relativeTo:callbackQueue:completion:)
    static func zipURLs(_ urls: [URL],
                        arguments: [String],
                        toZipURL zipURL: URL,
                        relativeTo baseURL: URL,
                        callbackQueue: DispatchQueue?,
                        completion: @escaping (Bool) -> Void) {
        let fullArgs = arguments + [zipURL.path] + urls.map { $0.relativePath }
        let runner = iTermCommandRunner(command: "/usr/bin/zip",
                                        withArguments: fullArgs,
                                        path: baseURL.path)
        if let callbackQueue {
            runner.callbackQueue = callbackQueue
        }
        runner.completion = { status in
            completion(status == 0)
        }
        runner.outputHandler = { data, handled in
            if let data {
                DLog("\(String(data: data, encoding: .utf8) ?? "")")
            }
            handled()
        }
        RLog("Running \(runner.command) \(redacted: runner.arguments.joined(separator: " "), or: "[\(runner.arguments.count) args]")")
        runner.run()
    }

    @objc func run() {
        readingQueue.async {
            self.runSynchronously()
        }
    }

    @objc func blockingRun() -> Int32 {
        callbackQueue = DispatchQueue.global(qos: .default)
        let group = DispatchGroup()
        group.enter()
        var exitCode: Int32 = -1
        completion = { code in
            exitCode = code
            group.leave()
        }
        run()
        group.wait()
        return exitCode
    }

    @objc(runWithTimeout:)
    func run(withTimeout timeout: TimeInterval) {
        guard let launchedTask = launchTask() else {
            return
        }
        readingQueue.async {
            self.readAndWait(launchedTask)
        }
        let queue = callbackQueue ?? DispatchQueue.main
        queue.asyncAfter(deadline: .now() + timeout) {
            if self.isRunning {
                launchedTask.terminate()
                self.task = nil
            }
        }
    }

    @objc func terminate() {
        shouldTerminateAfterLaunch = true
        let pid = task?.processIdentifier ?? 0
        if pid != 0 {
            let rc = Darwin.kill(pid, SIGKILL)
            RLog("kill -\(SIGKILL) \(pid) returned \(rc)")
        } else {
            DLog("command runner \(self) process ID is 0. Should terminate after launch.")
        }
    }

    @objc(write:completion:)
    func write(_ data: Data, completion: ((Int, Int32) -> Void)?) {
        let fd = inputPipe.fileHandleForWriting.fileDescriptor
        DLog("Planning to write \(data.count) bytes to \(self)")
        let queue = callbackQueue ?? DispatchQueue.main
        data.withUnsafeBytes { rawBuffer in
            let dispatchData: DispatchData
            if rawBuffer.count > 0 {
                dispatchData = DispatchData(bytes: rawBuffer)
            } else {
                dispatchData = DispatchData.empty
            }
            DispatchIO.write(toFileDescriptor: fd,
                             data: dispatchData,
                             runningHandlerOn: writingQueue) { remainingData, error in
                if let completion {
                    let remainingSize = remainingData?.count ?? 0
                    queue.async {
                        completion(remainingSize, error)
                    }
                }
            }
        }
    }

    func didReadData(_ data: Data, completion: @escaping () -> Void) {
        guard let outputHandler else {
            completion()
            return
        }
        let queue = callbackQueue ?? DispatchQueue.main
        queue.async {
            outputHandler(data, completion)
        }
    }

    // MARK: - Private

    @discardableResult
    private func launchTask() -> Process? {
        guard let task else {
            return nil
        }
        if let environment {
            task.environment = environment
        }
        task.standardInput = inputPipe
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: command)
        if !currentDirectoryPath.isEmpty {
            task.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }
        task.arguments = arguments
        DLog("runCommand: Launching \(task)")
        do {
            DLog("In \(task.currentDirectoryURL?.path ?? "") run: \(task.executableURL?.path ?? "") \(task.arguments ?? [])")
            try task.run()
            DLog("Launched \(self)")
        } catch {
            NSLog("Task failed with %@. launchPath=%@, pwd=%@, args=%@",
                  error.localizedDescription,
                  command,
                  currentDirectoryPath,
                  arguments)
            RLog("Task failed with \(error). launchPath=\(command), pwd=\(currentDirectoryPath), args=\(redacted: arguments, or: "[\(arguments.count) args]")")
            if let completion {
                let queue = callbackQueue ?? DispatchQueue.main
                queue.async {
                    completion(-1)
                }
            }
            return nil
        }
        isRunning = true
        if shouldTerminateAfterLaunch {
            DLog("terminate after launch \(self)")
            terminate()
        }
        return task
    }

    private func runSynchronously() {
        guard let launchedTask = launchTask() else {
            return
        }
        readAndWait(launchedTask)
    }

    private func readAndWait(_ task: Process) {
        let pipe = self.pipe
        let sema = DispatchSemaphore(value: 0)
        DLog("\(task) readAndWait starting")
        waitingQueue.async {
            DLog("\(task) readAndWait waiting for exit")
            let path = task.executableURL?.path ?? ""
            DLog("Wait for \(path)")
            let group = DispatchGroup()
            group.enter()
            task.terminationHandler = { finishedTask in
                DLog("Termination handler run for \(finishedTask.executableURL?.path ?? "")")
                group.leave()
            }
            group.wait()
            DLog("Resuming after termination of \(path)")
            pipe.fileHandleForReading.readabilityHandler = nil
            DLog("\(task) readAndWait signal sema")
            sema.signal()
            DLog("\(task) readAndWait done signaling sema")
        }

        let readHandle = pipe.fileHandleForReading
        DLog("runCommand: Reading")
        withExtendedLifetime(pipe) {
            while let inData = readAvailableChunk(from: readHandle), !inData.isEmpty {
                autoreleasepool {
                    DLog("runCommand: Read \(inData)")
                    let group = DispatchGroup()
                    group.enter()
                    didReadData(inData) {
                        group.leave()
                    }
                    group.wait()
                    if outputHandler == nil {
                        let argsDesc = (task.arguments ?? []).joined(separator: " ")
                        DLog("\(argsDesc): \(String(data: inData, encoding: .utf8) ?? "")")
                    }
                    DLog("runCommand: Reading")
                }
            }
        }

        DLog("runCommand: Done reading. Wait")
        DLog("\(task) readAndWait wait on sema")
        sema.wait()
        DLog("\(task) readAndWait done waiting on sema")

        isRunning = false
        if let completion {
            let queue = callbackQueue ?? DispatchQueue.main
            queue.async {
                completion(task.terminationStatus)
            }
        }
    }

    private func readAvailableChunk(from handle: FileHandle) -> Data? {
        let fd = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let bytesRead = Darwin.read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                return Data(buffer.prefix(Int(bytesRead)))
            }
            if bytesRead == 0 {
                return nil
            }
            if errno == EINTR {
                continue
            }
            return nil
        }
    }
}

/// Command runner subclass that captures stdout/stderr up to an optional byte limit.
@objc(iTermBufferedCommandRunner)
class iTermBufferedCommandRunner: iTermCommandRunner {
    private static let activeRunners = OSAllocatedUnfairLock(initialState: [iTermBufferedCommandRunner]())

    private var bufferedOutput: NSMutableData?
    @objc var maximumOutputSize: NSNumber?
    @objc private(set) var truncated: Bool = false

    @objc var output: Data? {
        return bufferedOutput as Data?
    }

    /// Runs a command in the background and shows a modal warning if it exits non-zero.
    @objc(runCommandWithPath:arguments:window:)
    static func runCommand(withPath path: String, arguments: [String], window: NSWindow?) {
        let runner = iTermBufferedCommandRunner(command: path,
                                                withArguments: arguments,
                                                path: FileManager.default.currentDirectoryPath)
        RLog("Launch \(path) \(redacted: arguments, or: "[\(arguments.count) args]") in runner \(runner)")
        runner.maximumOutputSize = NSNumber(value: 1024 * 10)
        runner.completion = { [weak runner] status in
            DLog("Command finished")
            guard let runner else { return }
            activeRunners.withLock { list in
                list.removeAll { $0 === runner }
            }
            runnerDidFinish(runner, withStatus: status)
        }
        activeRunners.withLock { $0.append(runner) }
        runner.run()
    }

    private static func runnerDidFinish(_ runner: iTermBufferedCommandRunner, withStatus status: Int32) {
        let remaining = activeRunners.withLock { list -> Int in
            list.removeAll { $0 === runner }
            return list.count
        }
        RLog("Runner \(runner) finished with status \(status). There are now \(remaining) runners.")
        guard status != 0 else {
            return
        }

        let warning = iTermWarning()
        warning.title = "The following command returned a non-zero exit code:\n\n“\(runner.command) \(runner.arguments.joined(separator: " "))”"
        warning.heading = "Command Failed"
        let inject = (runner.output as NSData?)?.mutableCopy() as? NSMutableData ?? NSMutableData()
        let truncationWarning = "\n\u{1B}[m;[output truncated]\n"
        if runner.truncated, let data = truncationWarning.data(using: .utf8) {
            inject.append(data)
        }
        inject.it_replaceOccurrences(of: Data([0x0A]), with: Data([0x0D, 0x0A]))
        let injectData = inject as Data
        warning.warningActions = [
            iTermWarningAction(label: "OK", block: nil),
            iTermWarningAction(label: "View", block: { _ in
                iTermController.sharedInstance().openSingleUseWindow(
                    withCommand: "/usr/bin/true",
                    arguments: nil,
                    inject: injectData,
                    environment: nil,
                    pwd: "/",
                    options: .shortLived,
                    didMakeSession: nil,
                    completion: nil)
            })
        ]
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        let name: String
        if runner.command == "/bin/sh",
           runner.arguments.first == "-c",
           runner.arguments.count > 1 {
            name = runner.arguments[1]
        } else {
            name = runner.command
        }
        warning.identifier = "NoSyncCommandFailed_" + name
        warning.runModal()
    }

    override func didReadData(_ data: Data, completion: @escaping () -> Void) {
        let queue = callbackQueue ?? DispatchQueue.main
        queue.async {
            self.saveData(data)
            guard let outputHandler = self.outputHandler else {
                completion()
                return
            }
            outputHandler(data, completion)
        }
    }

    private func saveData(_ data: Data) {
        if bufferedOutput == nil {
            bufferedOutput = NSMutableData()
        }
        guard !truncated, let bufferedOutput else {
            return
        }
        bufferedOutput.append(data)
        if let maxSize = maximumOutputSize?.intValue, bufferedOutput.length > maxSize {
            bufferedOutput.length = maxSize
            truncated = true
        }
    }
}
