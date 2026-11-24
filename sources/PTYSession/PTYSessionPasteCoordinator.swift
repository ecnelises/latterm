//
//  PTYSessionPasteCoordinator.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa

enum PTYSessionPastePolicy {
    struct RemoteSCPTarget: Equatable {
        let hostname: String
        let username: String?
        let path: String
    }

    static func resolveNonTextPasteDestination(hasDestination: Bool,
                                               hasConductor: Bool,
                                               isLocalityVerified: Bool) -> iTermNonTextPasteDestination {
        guard hasDestination else {
            return .local
        }
        if hasConductor {
            return .verifiedRemote
        }
        return isLocalityVerified ? .verifiedRemote : .unverifiedRemote
    }

    static func shouldUseGatewayConductor(isTmuxClient: Bool,
                                          serverIsLocal: Bool,
                                          hasDistinctGateway: Bool) -> Bool {
        return isTmuxClient && !serverIsLocal && hasDistinctGateway
    }

    static func resolveRemoteTarget(hasRemoteHost: Bool,
                                    username: String?,
                                    hostname: String?,
                                    isLocalhost: Bool,
                                    workingDirectory: String?,
                                    hasConductor: Bool,
                                    conductorHostname: String?,
                                    conductorUsername: String?,
                                    conductorHomeDirectory: String?,
                                    canTransferToIdentity: Bool) -> RemoteSCPTarget? {
        // SSH integration knows the destination even before shell integration has
        // reported a host or working directory (including inside ordinary tmux).
        if !hasRemoteHost, hasConductor {
            guard let host = conductorHostname,
                  let home = conductorHomeDirectory,
                  !home.isEmpty else {
                return nil
            }
            return RemoteSCPTarget(hostname: host, username: conductorUsername, path: home)
        }
        guard hasRemoteHost,
              let user = username,
              let host = hostname,
              !isLocalhost else {
            return nil
        }
        var directory = workingDirectory
        if (directory?.isEmpty ?? true) && canTransferToIdentity {
            directory = conductorHomeDirectory
        }
        guard let resolvedDirectory = directory, !resolvedDirectory.isEmpty else {
            return nil
        }
        return RemoteSCPTarget(hostname: host, username: user, path: resolvedDirectory)
    }

    static func buildRemoteUploadPath(directory: String,
                                      localPath: String,
                                      hostname: String?,
                                      username: String?) -> SCPPath {
        let scpPath = SCPPath()
        scpPath.hostname = hostname ?? ""
        scpPath.username = username ?? ""
        let filename = (localPath as NSString).lastPathComponent
        scpPath.path = (directory as NSString).appendingPathComponent(filename)
        return scpPath
    }

    static func uploadIndicatorLabel(fileCount: Int, firstPath: String?) -> String {
        if fileCount <= 1, let firstPath {
            return (firstPath as NSString).lastPathComponent
        }
        let format = Bundle.main.localizedString(
            forKey: "PTYSession.UploadingFileCount",
            value: "%ld files",
            table: nil
        )
        return String.localizedStringWithFormat(format, fileCount)
    }

    static func shouldWatchForBracketedPasteOopsie(bytesWritten: Int,
                                                   flags: iTermPasteFlags,
                                                   terminalBracketedPasteMode: Bool) -> Bool {
        return bytesWritten == 0 && flags.contains(.pasteFlagsBracket) && terminalBracketedPasteMode
    }

    static func shouldPasteAfterUpload(sessionExited: Bool,
                                       conductorMatches: Bool,
                                       currentHostname: String?,
                                       currentUsername: String?,
                                       destinationHostname: String?,
                                       destinationUsername: String?,
                                       canTransferToDestination: Bool,
                                       canTransferToCurrent: Bool) -> Bool {
        if sessionExited || !conductorMatches {
            return false
        }
        let sameName = (currentHostname == destinationHostname) && (currentUsername == destinationUsername)
        let sameConductorHost = currentHostname != nil && canTransferToDestination && canTransferToCurrent
        return sameName || sameConductorHost
    }

    static func formatUploadedPathsForPaste(_ remotePaths: [String?],
                                            escapePath: (String) -> String) -> String? {
        let escaped = remotePaths.compactMap { path -> String? in
            guard let path, !path.isEmpty else {
                return nil
            }
            return escapePath(path)
        }
        guard !escaped.isEmpty else {
            return nil
        }
        return escaped.joined(separator: " ")
    }
}

struct PTYSessionUploadBatchState {
    private(set) var generation: Int = 0
    private var transfers: [TransferrableFile] = []
    private var remotePaths: [String?] = []
    private var expectedCount: Int = 0
    private var completedCount: Int = 0
    private var allStarted: Bool = false

    var isUploading: Bool {
        return !transfers.isEmpty
    }

    var activeTransferCount: Int {
        return transfers.count
    }

    mutating func beginGroup(fileCount: Int) -> Int {
        generation += 1
        transfers = []
        remotePaths = [String?](repeating: nil, count: max(0, fileCount))
        expectedCount = max(0, fileCount)
        completedCount = 0
        allStarted = false
        return generation
    }

    mutating func addTransfer(_ transfer: TransferrableFile, generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }
        transfers.append(transfer)
    }

    mutating func recordCompletion(generation expectedGeneration: Int,
                                 index: Int,
                                 success: Bool,
                                 remotePath: String?) -> [String?]? {
        guard generation == expectedGeneration else {
            return nil
        }
        if success, let remotePath, !remotePath.isEmpty, index >= 0, index < remotePaths.count {
            remotePaths[index] = remotePath
        }
        completedCount += 1
        return readyRemotePathsIfDone()
    }

    mutating func markAllStarted(generation expectedGeneration: Int) -> [String?]? {
        guard generation == expectedGeneration else {
            return nil
        }
        allStarted = true
        return readyRemotePathsIfDone()
    }

    mutating func finishCompletedGroup(generation expectedGeneration: Int) {
        guard generation == expectedGeneration else {
            return
        }
        generation += 1
        transfers = []
        remotePaths = []
        expectedCount = 0
        completedCount = 0
        allStarted = false
    }

    mutating func cancel() -> [TransferrableFile] {
        let active = transfers
        // Bump first so completions provoked by -stop find their group gone and do not paste.
        generation += 1
        transfers = []
        remotePaths = []
        expectedCount = 0
        completedCount = 0
        allStarted = false
        return active
    }

    private func readyRemotePathsIfDone() -> [String?]? {
        guard allStarted && completedCount >= expectedCount else {
            return nil
        }
        return remotePaths
    }
}

@objc
final class PTYSessionPasteCoordinator: NSObject, iTermPasteHelperDelegate, iTermNonTextPasteHelperDelegate {
    private weak var session: PTYSession?
    private var nonTextPasteHelperInstance: iTermNonTextPasteHelper?
    private var uploadBatch = PTYSessionUploadBatchState()

    @objc(initWithSession:)
    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    deinit {
        nonTextPasteHelperInstance?.delegate = nil
    }

    @objc
    var nonTextPasteHelper: iTermNonTextPasteHelper {
        if let existing = nonTextPasteHelperInstance {
            return existing
        }
        let helper = iTermNonTextPasteHelper()
        helper.delegate = self
        nonTextPasteHelperInstance = helper
        return helper
    }

    @objc
    func detach() {
        nonTextPasteHelperInstance?.delegate = nil
        cancelUploadAndPaste()
    }

    @objc
    func attemptNonTextPaste() {
        DLog("attemptNonTextPaste")
        let handled = nonTextPasteHelper.pasteNonTextContent()
        DLog("pasteNonTextContent returned \(handled)")
    }

    @objc(showPasteOptionsForDroppedFiles:)
    func showPasteOptions(forDroppedFiles filenames: [String]) {
        DLog("textViewShowPasteOptionsForDroppedFiles: \(filenames)")
        nonTextPasteHelper.showPasteOptionsForFiles(filenames)
    }

    @objc(uploadFiles:toPath:)
    func uploadFiles(_ localFilenames: [String], to destinationPath: SCPPath) {
        RLog("uploadFiles:\(localFilenames.count) toPath:\(destinationPath.path?.count ?? 0)")

        let conductor = nonTextPasteConductor()
        var previous: SCPFile?
        for file in localFilenames {
            let path = PTYSessionPastePolicy.buildRemoteUploadPath(
                directory: destinationPath.path ?? "",
                localPath: file,
                hostname: destinationPath.hostname,
                username: destinationPath.username
            )
            DLog("Will upload local:\(file) to remote:\(path.path ?? "")")

            if let conductor,
               MainActor.assumeIsolated({ conductor.canTransferFilesTo(path) }) {
                // Each upload is independent; hand off every file in the batch.
                DLog("Using conductor for upload")
                MainActor.assumeIsolated {
                    conductor.upload(file: file, to: path)
                }
                continue
            }

            DLog("Using SCPFile for upload")
            let scpFile = SCPFile()
            scpFile.path = path
            scpFile.setLocalPath(file)
            DLog("SCPFile localPath=\(file) remotePath=\(scpFile.path.path ?? "")")

            if let previous {
                previous.successor = scpFile
            }
            previous = scpFile
            scpFile.upload()
        }
    }

    @objc
    func cancelUploadAndPaste() {
        let transfers = uploadBatch.cancel()
        if !transfers.isEmpty {
            DLog("Cancelling \(transfers.count) upload and paste transfer(s)")
            for transfer in transfers {
                transfer.stop()
            }
        }
        session?.view?.hideUploadIndicator()
    }

    // MARK: - iTermPasteHelperDelegate

    func pasteHelperWrite(_ string: String!) {
        guard let session, let string else {
            return
        }
        if let context = session.pasteHelper?.pasteContext,
           let pasteEvent = context.pasteEvent,
           PTYSessionPastePolicy.shouldWatchForBracketedPasteOopsie(
               bytesWritten: context.bytesWritten,
               flags: pasteEvent.flags,
               terminalBracketedPasteMode: session.screen.terminalBracketedPasteMode
           ) {
            DLog("Will write first chunk of bracketed paste: \(string)")
            let prefix = ((pasteEvent.originalString ?? "") as NSString).it_substring(to: 4)
            session.watchForPasteBracketingOopsie(withPrefix: prefix, andWrite: string)
        } else {
            DLog("Writing regular chunk")
            session.writeTask(string)
        }
    }

    func pasteHelperKeyDown(_ event: NSEvent!) {
        guard let event else {
            return
        }
        session?.textview?.keyDown(with: event)
    }

    func pasteHelperShouldBracket() -> Bool {
        return session?.screen.terminalBracketedPasteMode ?? false
    }

    func pasteHelperEncoding() -> UInt {
        return session?.screen.terminalEncoding ?? String.Encoding.utf8.rawValue
    }

    func pasteHelperViewForIndicator() -> NSView! {
        return session?.view
    }

    func pasteHelperStatusBarViewController() -> iTermStatusBarViewController! {
        return session?.statusBarViewController
    }

    func pasteHelperShouldWaitForPrompt() -> Bool {
        guard let session else {
            return false
        }
        if !session.screen.shouldExpectPromptMarks() {
            DLog("Shell integration is not installed. We may never get a command prompt so waiting is not advisable.")
            return false
        }
        DLog("currentCommand=\(String(describing: session.currentCommand))")
        // currentCommand is nil when executing a command. If you are at a shell prompt it is
        // a nonnil string with the command that the user has typed so far (which could be an
        // empty string). Return true if we are not at a shell prompt.
        return session.currentCommand == nil
    }

    func pasteHelperIsAtShellPrompt() -> Bool {
        return session?.currentCommand != nil
    }

    func pasteHelperCanWaitForPrompt() -> Bool {
        return session?.screen.shouldExpectPromptMarks() ?? false
    }

    func pasteHelperPasteViewVisibilityDidChange() {
        session?.delegate?.sessionUpdateMetalAllowed()
    }

    func pasteHelperScope() -> iTermVariableScope! {
        return session?.genericScope
    }

    // MARK: - iTermNonTextPasteHelperDelegate

    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, pasteString string: String) {
        session?.paste(string, flags: [])
    }

    func nonTextPasteHelperWindow(_ sender: iTermNonTextPasteHelper) -> NSWindow? {
        return session?.view?.window
    }

    func nonTextPasteHelperDestination(_ sender: iTermNonTextPasteHelper) -> iTermNonTextPasteDestination {
        // Can upload if we have SSH integration (our own conductor or, in a tmux
        // integration pane, the gateway's) in framing mode, or if shell integration
        // detected we're on a remote host. Only the latter can be a wrong guess, and
        // only when nothing proved it (see issue 13117). Either way there must be
        // somewhere to upload to.
        let host = session?.currentHost
        let conductor = nonTextPasteConductor()
        let destination = scpPathForCurrentRemoteHost()
        DLog("nonTextPasteHelperDestination: conductor=\(String(describing: conductor)) currentHost=\(String(describing: host)) isLocalhost=\(host?.isLocalhost ?? false) destination=\(String(describing: destination))")
        return PTYSessionPastePolicy.resolveNonTextPasteDestination(
            hasDestination: destination != nil,
            hasConductor: conductor != nil,
            isLocalityVerified: host?.localityVerified ?? false
        )
    }

    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFiles paths: [String]) {
        DLog("nonTextPasteHelper:uploadFiles: paths=\(paths)")
        for path in paths {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            DLog("File \(path) attributes: size=\(String(describing: attrs?[.size])), type=\(String(describing: attrs?[.type]))")
        }
        guard let scpPath = scpPathForCurrentRemoteHost() else {
            DLog("No scpPath, aborting upload")
            return
        }
        uploadFiles(paths, to: scpPath)
    }

    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFileAndPastePath path: String) {
        DLog("nonTextPasteHelper:uploadFileAndPastePath: localPath=\(path)")
        uploadFilesAndPastePaths([path])
    }

    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFilesAndPastePaths paths: [String]) {
        uploadFilesAndPastePaths(paths)
    }

    // MARK: - Private

    // A control-mode pane has no conductor of its own. Its gateway owns the SSH
    // connection, but pasted input must still go to this pane.
    private func nonTextPasteConductor() -> Conductor? {
        var visited = Set<ObjectIdentifier>()
        var current: PTYSession? = session
        while let candidate = current {
            let identifier = ObjectIdentifier(candidate)
            if visited.contains(identifier) {
                return nil
            }
            visited.insert(identifier)

            if let conductor = candidate.conductor {
                let isFraming = MainActor.assumeIsolated { conductor.framing }
                return isFraming ? conductor : nil
            }
            let gateway = candidate.tmuxGateway
            let serverIsLocal = candidate.tmuxController?.serverIsLocal ?? false
            if PTYSessionPastePolicy.shouldUseGatewayConductor(
                isTmuxClient: candidate.isTmuxClient,
                serverIsLocal: serverIsLocal,
                hasDistinctGateway: gateway != nil && gateway !== candidate
            ) {
                current = gateway
                continue
            }
            return nil
        }
        return nil
    }

    // Returns an SCPPath for the current remote host and working directory, or nil if not available.
    private func scpPathForCurrentRemoteHost() -> SCPPath? {
        guard let session else {
            return nil
        }
        let remoteHost = session.currentHost
        let conductor = nonTextPasteConductor()
        DLog("scpPathForCurrentRemoteHost: remoteHost=\(String(describing: remoteHost))")

        let (canTransferToIdentity, conductorHostname, conductorUsername, conductorHomeDirectory) = MainActor.assumeIsolated { () -> (Bool, String?, String?, String?) in
            var canTransfer = false
            if let remoteHost,
               let hostname = remoteHost.hostname,
               let username = remoteHost.username,
               let conductor {
                let identityPath = SCPPath()
                identityPath.hostname = hostname
                identityPath.username = username
                canTransfer = conductor.canTransferFilesTo(identityPath)
            }
            return (
                canTransfer,
                conductor?.sshIdentity.hostname,
                conductor?.sshIdentity.username,
                conductor?.homeDirectory
            )
        }

        let workingDirectory = session.genericScope.value(forVariableName: iTermVariableKeySessionPath) as? String
        guard let target = PTYSessionPastePolicy.resolveRemoteTarget(
            hasRemoteHost: remoteHost != nil,
            username: remoteHost?.username,
            hostname: remoteHost?.hostname,
            isLocalhost: remoteHost?.isLocalhost ?? false,
            workingDirectory: workingDirectory,
            hasConductor: conductor != nil,
            conductorHostname: conductorHostname,
            conductorUsername: conductorUsername,
            conductorHomeDirectory: conductorHomeDirectory,
            canTransferToIdentity: canTransferToIdentity
        ) else {
            if remoteHost == nil {
                DLog("No remote host or missing username/hostname")
            } else if remoteHost?.isLocalhost == true {
                DLog("Is localhost, returning nil")
            } else if (workingDirectory?.isEmpty ?? true) {
                DLog("No working directory")
            }
            return nil
        }

        let scpPath = SCPPath()
        scpPath.path = target.path
        scpPath.hostname = target.hostname
        scpPath.username = target.username ?? ""
        DLog("Returning scpPath: hostname=\(scpPath.hostname ?? "") username=\(scpPath.username ?? "") path=\(scpPath.path ?? "")")
        return scpPath
    }

    private func uploadFilesAndPastePaths(_ localPaths: [String]) {
        guard !localPaths.isEmpty, let session else {
            return
        }
        if uploadBatch.isUploading {
            DLog("Upload already in progress, blocking new upload")
            let alert = NSAlert()
            alert.messageText = "Upload in Progress"
            alert.informativeText = "Please wait for the current upload to complete or cancel it before starting another."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = session.view?.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return
        }
        guard let scpPath = scpPathForCurrentRemoteHost() else {
            DLog("No scpPath, aborting upload")
            return
        }

        let label = PTYSessionPastePolicy.uploadIndicatorLabel(
            fileCount: localPaths.count,
            firstPath: localPaths.first
        )
        let conductor = nonTextPasteConductor()
        session.view?.showUploadIndicator(withFilename: label) { [weak self] in
            DLog("Upload cancelled by user")
            self?.cancelUploadAndPaste()
        }

        let generation = uploadBatch.beginGroup(fileCount: localPaths.count)
        for (index, localPath) in localPaths.enumerated() {
            let transfer = uploadFile(localPath, to: scpPath) { [weak self] success, error, remotePath in
                DLog("Upload of \(localPath) completed: success=\(success) error=\(String(describing: error)) remotePath=\(String(describing: remotePath))")
                guard let self else {
                    return
                }
                guard let finishedPaths = self.uploadBatch.recordCompletion(
                    generation: generation,
                    index: index,
                    success: success,
                    remotePath: remotePath
                ) else {
                    if self.uploadBatch.generation != generation {
                        DLog("Ignoring completion from a cancelled or superseded upload group")
                    }
                    return
                }
                self.finishUploadAndPaste(
                    remotePaths: finishedPaths,
                    destination: scpPath,
                    conductor: conductor,
                    generation: generation
                )
            }
            if let transfer {
                uploadBatch.addTransfer(transfer, generation: generation)
            }
        }

        if let finishedPaths = uploadBatch.markAllStarted(generation: generation) {
            finishUploadAndPaste(
                remotePaths: finishedPaths,
                destination: scpPath,
                conductor: conductor,
                generation: generation
            )
        }
    }

    // Pastes the paths of the uploads that succeeded. A file that failed contributes nothing: its
    // name would point at something that is not there, and the failure is already reported in the
    // file transfers window. Pasting nothing at all is the right outcome when every one failed.
    // Nothing is pasted if, while uploading, the session ended or moved to another host or ssh
    // connection, since the paths would name files that are not there.
    private func finishUploadAndPaste(remotePaths: [String?],
                                      destination: SCPPath,
                                      conductor: Conductor?,
                                      generation: Int) {
        uploadBatch.finishCompletedGroup(generation: generation)
        session?.view?.hideUploadIndicator()

        guard let session else {
            return
        }
        let currentConductor = nonTextPasteConductor()
        let currentPath = scpPathForCurrentRemoteHost()
        let (canTransferToDestination, canTransferToCurrent) = MainActor.assumeIsolated {
            let toDest = (currentPath != nil && (conductor?.canTransferFilesTo(destination) ?? false))
            let toCurrent = (currentPath.map { conductor?.canTransferFilesTo($0) ?? false } ?? false)
            return (toDest, toCurrent)
        }
        let shouldPaste = PTYSessionPastePolicy.shouldPasteAfterUpload(
            sessionExited: session.exited,
            conductorMatches: currentConductor === conductor,
            currentHostname: currentPath?.hostname,
            currentUsername: currentPath?.username,
            destinationHostname: destination.hostname,
            destinationUsername: destination.username,
            canTransferToDestination: canTransferToDestination,
            canTransferToCurrent: canTransferToCurrent
        )
        guard shouldPaste else {
            if session.exited || currentConductor !== conductor {
                DLog("Session exited or its ssh connection changed during upload, so not pasting")
            } else {
                DLog("Host changed during upload from \(destination) to \(String(describing: currentPath)), so not pasting")
            }
            return
        }

        guard let string = PTYSessionPastePolicy.formatUploadedPathsForPaste(
            remotePaths,
            escapePath: { iTermNonTextPasteHelper.escapedPathForPaste($0) }
        ) else {
            DLog("Every upload failed, so nothing to paste")
            return
        }
        DLog("Pasting escaped uploaded path(s)")
        session.paste(string, flags: [])
    }

    // The completion reports where the file actually landed, which is not always the path computed
    // here: an upload over ssh integration never overwrites, so if the name is taken on the far host
    // it uploads as "name (2)" and records that. Pasting the requested path instead would name the
    // pre-existing file, which is a different file. -destination is the transfer's own answer once it
    // has finished, so ask it rather than predicting.
    private func uploadFile(_ localPath: String,
                            to destinationPath: SCPPath,
                            completion: @escaping (Bool, String?, String?) -> Void) -> TransferrableFile? {
        DLog("uploadFile:\(localPath) toPath:\(destinationPath.path ?? "") with completion")

        let path = PTYSessionPastePolicy.buildRemoteUploadPath(
            directory: destinationPath.path ?? "",
            localPath: localPath,
            hostname: destinationPath.hostname,
            username: destinationPath.username
        )
        DLog("Will upload local:\(localPath) to remote:\(path.path ?? "")")

        // Assigned before any completion can run: the conductor finishes on a later turn of the run
        // loop, and the SCPFile branch assigns before starting the upload. The one case that reports
        // synchronously (an archive that could not be built) reports failure, where the path is unused.
        weak var pendingTransfer: TransferrableFile?
        let predictedPath = path.path
        let wrapper: (Bool, String?) -> Void = { success, error in
            completion(success, error, pendingTransfer?.destination() ?? predictedPath)
        }

        if let conductor = nonTextPasteConductor(),
           MainActor.assumeIsolated({ conductor.canTransferFilesTo(path) }) {
            DLog("Using conductor for upload with completion")
            let transfer = MainActor.assumeIsolated {
                conductor.upload(file: localPath, to: path, completion: wrapper)
            }
            pendingTransfer = transfer
            return transfer
        }

        DLog("Using SCPFile for upload with completion")
        let scpFile = SCPFile()
        scpFile.path = path
        scpFile.setLocalPath(localPath)
        scpFile.completionBlock = wrapper
        DLog("SCPFile localPath=\(localPath) remotePath=\(scpFile.path.path ?? "")")
        pendingTransfer = scpFile
        scpFile.upload()
        return scpFile
    }
}
