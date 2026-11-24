//
//  PTYSessionSSHBridge.swift
//  iTerm2SharedARC
//
//  Extracted from PTYSession.m for Stage 3.1 God-class decomposition.
//

import Cocoa

/// Computed session scope variable values derived from the current SSH conductor state.
struct PTYSessionSSHVariableSnapshot: Equatable {
    let sshIntegrationActive: Bool
    let sshIntegrationLevel: Int
    let homeDirectory: String?
    let shell: String?
    let uname: String?

    static func compute(hasConductor: Bool,
                        conductorFraming: Bool,
                        conductorHomeDirectory: String?,
                        conductorShell: String?,
                        conductorUName: String?,
                        localHomeDirectory: String,
                        localShell: String?,
                        localUName: String?,
                        isOnLocalhost: Bool) -> PTYSessionSSHVariableSnapshot {
        if !hasConductor {
            return PTYSessionSSHVariableSnapshot(
                sshIntegrationActive: false,
                sshIntegrationLevel: 0,
                homeDirectory: localHomeDirectory,
                shell: localShell,
                uname: localUName
            )
        }
        if conductorFraming {
            return PTYSessionSSHVariableSnapshot(
                sshIntegrationActive: true,
                sshIntegrationLevel: 2,
                homeDirectory: conductorHomeDirectory,
                shell: conductorShell,
                uname: conductorUName
            )
        }
        // Level 1: SSH'ed without framer integration, so host env details are unavailable.
        _ = isOnLocalhost
        return PTYSessionSSHVariableSnapshot(
            sshIntegrationActive: true,
            sshIntegrationLevel: 1,
            homeDirectory: nil,
            shell: nil,
            uname: nil
        )
    }
}

/// Start strategy when hooking a new SSH conductor.
enum PTYSessionSSHStartAction: Equatable {
    case startPendingJumps
    case startPreviousSubsequentJumps
    case startNormally
}

/// Pure policy decisions for SSH conductor lifecycle, jumps, and framer recovery.
struct PTYSessionSSHPolicy {
    static func initialDirectoryForHook(isSSHProfileState: Bool,
                                        hasExistingConductor: Bool,
                                        environmentPWD: String?,
                                        nextPendingJumpDirectory: String?) -> String? {
        if let nextPendingJumpDirectory {
            return nextPendingJumpDirectory
        }
        if isSSHProfileState && !hasExistingConductor {
            return environmentPWD
        }
        return nil
    }

    static func startAction(hasPreviousConductor: Bool,
                            remainingPendingJumpsCount: Int,
                            previousSubsequentJumpsCount: Int) -> PTYSessionSSHStartAction {
        if !hasPreviousConductor && remainingPendingJumpsCount > 0 {
            return .startPendingJumps
        }
        if previousSubsequentJumpsCount > 0 {
            return .startPreviousSubsequentJumps
        }
        return .startNormally
    }

    static func shouldUnhookAllBeforeFramerRecovery(parentDepth: Int32) -> Bool {
        return parentDepth < 0
    }

    static func unwindCount(ancestryClientIDsFromLeafToRoot: [String],
                            targetUniqueID: String) -> Int {
        guard let index = ancestryClientIDsFromLeafToRoot.firstIndex(of: targetUniqueID) else {
            return 0
        }
        return index + 1
    }
}

/// Coordinates SSH `ConductorDelegate` callbacks and `VT100ScreenDelegate` conductor hooks.
@objc
final class PTYSessionSSHCoordinator: NSObject, ConductorDelegate {
    private weak var session: PTYSession?

    /// Pending callback invoked once the newly attached SSH conductor sends initial text.
    @objc var pendingConductor: ((PTYSession) -> Void)?

    init(session: PTYSession) {
        self.session = session
        super.init()
    }

    // MARK: - ConductorDelegate

    var guid: String {
        return session?.guid ?? ""
    }

    @objc(conductorWriteString:)
    func conductorWrite(string: String) {
        DLog("Conductor write: \(string)")
        session?.writeTaskNoBroadcast(string)
    }

    @objc
    func conductorSendInitialText() {
        guard let session else {
            return
        }
        session.sendInitialText()
        if let pending = pendingConductor {
            pendingConductor = nil
            pending(session)
        }
    }

    func conductorWillDie() {
        guard let session else {
            return
        }
        RLog("conductorWillDie")
        let replacement: iTermPublisher<NSNumber> = MainActor.assumeIsolated {
            session.conductor?.parent?.cpuUtilizationPublisher
        } ?? iTermLocalCPUUtilizationPublisher.sharedInstance()
        iTermCPUUtilization.instance(forSessionID: session.guid).publisher = replacement
    }

    func conductorDidUnhook() {
        conductorWillDie()
    }

    func conductorAbort(reason: String) {
        guard let session else {
            return
        }
        XLog("conductor aborted: \(reason)")
        conductorWillDie()

        let location = MainActor.assumeIsolated {
            session.conductor?.parent?.sshIdentity.compactDescription ?? ""
        }
        session.screen.mutateAsynchronously { _, mutableState, _ in
            mutableState.appendString(atCursor: "An error occurred while setting up the SSH environment:")
            mutableState.appendCarriageReturnLineFeed()
            mutableState.appendString(atCursor: reason)
            mutableState.appendCarriageReturnLineFeed()
            let message = mutableState.sshEndBannerTerminatingCount(1, newLocation: location)
            mutableState.appendBannerMessage(message)
        }
        unhookSSHConductor()
    }

    func conductorQuit() {
        guard let session else {
            return
        }
        RLog("conductorQuit")
        conductorWillDie()
        let identity = MainActor.assumeIsolated {
            session.conductor?.sshIdentity.description ?? ""
        }
        session.screen.mutateAsynchronously { _, mutableState, _ in
            mutableState.appendBannerMessage("Disconnected from \(identity)")
        }
        unhookSSHConductor()
        session.clearSSHWriteQueue()
    }

    func conductorStateDidChange() {
        DLog("conductorDidExfiltrateState")
        updateVariablesFromConductor()
    }

    // MARK: - Variable Synchronization & Unhooking

    @objc
    func updateVariablesFromConductor() {
        guard let session else {
            return
        }
        let conductorInfo = MainActor.assumeIsolated { () -> (hasConductor: Bool, framing: Bool, home: String?, shell: String?, uname: String?) in
            guard let conductor = session.conductor else {
                return (false, false, nil, nil, nil)
            }
            return (true, conductor.framing, conductor.homeDirectory, conductor.shell, conductor.uname)
        }
        let isOnLocalhost = session.currentHost?.isLocalhost ?? true
        let snapshot = PTYSessionSSHVariableSnapshot.compute(
            hasConductor: conductorInfo.hasConductor,
            conductorFraming: conductorInfo.framing,
            conductorHomeDirectory: conductorInfo.home,
            conductorShell: conductorInfo.shell,
            conductorUName: conductorInfo.uname,
            localHomeDirectory: NSHomeDirectory(),
            localShell: conductorInfo.hasConductor ? nil : session.bestGuessAtUserShell(withPath: false),
            localUName: conductorInfo.hasConductor ? nil : session.bestGuessAtUName(),
            isOnLocalhost: isOnLocalhost
        )
        session.shell.sshIntegrationActive = snapshot.sshIntegrationActive
        let scope = session.genericScope
        scope.setValue(snapshot.homeDirectory, forVariableNamed: iTermVariableKeySessionHomeDirectory)
        scope.setValue(snapshot.sshIntegrationLevel, forVariableNamed: iTermVariableKeySSHIntegrationLevel)
        scope.setValue(snapshot.shell, forVariableNamed: iTermVariableKeyShell)
        scope.setValue(snapshot.uname, forVariableNamed: iTermVariableKeyUname)
    }

    @objc
    func unhookSSHConductor() {
        guard let session else {
            return
        }
        let previousConductor = session.conductor
        RLog("Unhook \(String(describing: previousConductor))")
        conductorWillDie()
        MainActor.assumeIsolated {
            if let config = previousConductor?.terminalConfiguration as? [AnyHashable: Any] {
                session.screen.restoreSavedState(config)
            }
        }
        let parentConductor = MainActor.assumeIsolated {
            previousConductor?.parent
        }
        session.replaceSSHConductor(with: parentConductor, removeChannelClients: true)
        updateVariablesFromConductor()
    }

    // MARK: - VT100ScreenDelegate SSH Conductor Hooks

    @objc(handleHookSSHConductorWithToken:uniqueID:boolArgs:sshargs:dcsID:savedState:)
    func handleHookSSHConductor(token: String,
                                uniqueID: String,
                                boolArgs: String,
                                sshargs: String,
                                dcsID: String,
                                savedState: [AnyHashable: Any]) {
        guard let session else {
            return
        }
        let localOrigin = SecretServer.instance?.check(token) ?? false
        let poppedJump = session.popPendingSSHJump()
        let previousConductor = session.conductor
        let directory = PTYSessionSSHPolicy.initialDirectoryForHook(
            isSSHProfileState: session.sshProfileStateActive,
            hasExistingConductor: previousConductor != nil,
            environmentPWD: session.environment?["PWD"] as? String,
            nextPendingJumpDirectory: poppedJump?.initialDirectory
        )
        let configDict = iTermProfilePreferences.object(forKey: KEY_SSH_CONFIG, inProfile: session.profile ?? [:]) as? NSDictionary
        let config = SSHConfiguration(dictionary: configDict)
        let varsToSend: [String: String]
        if localOrigin {
            varsToSend = session.screen.exfiltratedEnvironmentVariables(config.environmentVariablesToCopy)
        } else {
            varsToSend = [:]
        }
        let clientVars = session.screen.exfiltratedEnvironmentVariables(nil)
        let remainingJumps = session.remainingPendingSSHJumps()

        let newConductor = MainActor.assumeIsolated { () -> Conductor in
            let conductor = Conductor(sshargs,
                                      boolArgs: boolArgs,
                                      dcsID: dcsID,
                                      clientUniqueID: uniqueID,
                                      varsToSend: varsToSend,
                                      clientVars: clientVars,
                                      initialDirectory: directory,
                                      parent: previousConductor)
            conductor.terminalConfiguration = savedState as NSDictionary
            if localOrigin {
                for tuple in config.filesToCopy {
                    if let source = tuple.firstObject as String?,
                       let destination = tuple.secondObject as String? {
                        conductor.add(path: source, destination: destination)
                    }
                }
            }
            return conductor
        }

        session.sshProfileStateActive = false
        session.replaceSSHConductor(with: newConductor, removeChannelClients: false)

        MainActor.assumeIsolated {
            let previousSubsequentJumps = previousConductor?.subsequentJumps_objc ?? []
            switch PTYSessionSSHPolicy.startAction(
                hasPreviousConductor: previousConductor != nil,
                remainingPendingJumpsCount: remainingJumps.count,
                previousSubsequentJumpsCount: previousSubsequentJumps.count
            ) {
            case .startPendingJumps:
                newConductor.startJumping(to: remainingJumps)
            case .startPreviousSubsequentJumps:
                newConductor.startJumping(to: previousSubsequentJumps)
                previousConductor?.childDidBeginJumping()
            case .startNormally:
                newConductor.start()
            }
        }
        updateVariablesFromConductor()
    }

    @objc(handleReadSSHConductorLine:depth:)
    func handleReadSSHConductorLine(_ string: String, depth: Int32) {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.handle(line: string, depth: depth)
        }
    }

    @objc
    func handleUnhookSSHConductor() {
        guard let session else {
            return
        }
        if let conductor = session.conductor {
            MainActor.assumeIsolated {
                conductor.handleUnhook()
            }
        }
        session.flushSSHWriteQueue()
    }

    @objc(handleBeginSSHConductorCommandWithIdentifier:depth:)
    func handleBeginSSHConductorCommand(identifier: String, depth: Int32) {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.handleCommandBegin(identifier: identifier, depth: depth)
        }
    }

    @objc(handleEndSSHConductorCommandWithIdentifier:type:status:depth:)
    func handleEndSSHConductorCommand(identifier: String,
                                      type: String,
                                      status: UInt8,
                                      depth: Int32) {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.handleCommandEnd(identifier: identifier,
                                       type: type,
                                       status: status,
                                       depth: depth)
        }
    }

    @objc(handleSSHSideChannelOutput:pid:channel:depth:)
    func handleSSHSideChannelOutput(_ string: String,
                                    pid: Int32,
                                    channel: UInt8,
                                    depth: Int32) {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.handleSideChannelOutput(string, pid: pid, channel: channel, depth: depth)
        }
    }

    @objc(handleReadRawSSHData:)
    func handleReadRawSSHData(_ data: Data) {
        guard let session else {
            return
        }
        guard session.conductor != nil else {
            DLog("Read raw ssh data but there is no conductor")
            return
        }
        if session.hasCoprocess {
            let nsData = data as NSData
            DLog("Read raw SSH data, passing it on to the coprocess: \(nsData)")
            DLog("tty -> coprocess: \(nsData.it_hexEncoded()) (\(nsData.shortDebugString() ?? ""))")
            session.shell.write(toCoprocess: data)
        } else {
            DLog("Read raw ssh data but the shell has no coprocess")
        }
    }

    @objc(handleTerminateSSHProcess:code:depth:)
    func handleTerminateSSHProcess(pid: Int32, code: Int32, depth: Int32) {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.handleTerminate(pid, code: code, depth: depth)
        }
    }

    @objc(handleEndSSH:)
    func handleEndSSH(uniqueID: String) -> Int {
        guard let session else {
            return 0
        }
        DLog("\(uniqueID)")
        let ancestryMatches = MainActor.assumeIsolated {
            session.conductor?.ancestryContains(clientUniqueID: uniqueID) ?? false
        }
        guard ancestryMatches else {
            DLog("Ancestry does not contain this unique ID")
            return 0
        }
        var found = false
        var count = 0
        while session.conductor != nil && !found {
            found = MainActor.assumeIsolated {
                session.conductor?.clientUniqueID == uniqueID
            }
            count += 1
            unhookSSHConductor()
        }
        return count
    }

    @objc
    func sshLocation() -> String? {
        guard let conductor = session?.conductor else {
            return nil
        }
        return MainActor.assumeIsolated {
            conductor.sshIdentity.compactDescription
        }
    }

    @objc(handleBeginFramerRecovery:)
    func handleBeginFramerRecovery(parentDepth: Int32) {
        guard let session else {
            return
        }
        if PTYSessionSSHPolicy.shouldUnhookAllBeforeFramerRecovery(parentDepth: parentDepth) {
            while session.conductor != nil {
                unhookSSHConductor()
            }
        }
        let previousConductor = session.conductor
        let recoveryConductor = MainActor.assumeIsolated {
            Conductor("",
                      boolArgs: "",
                      dcsID: "",
                      clientUniqueID: "",
                      varsToSend: [:],
                      clientVars: [:],
                      initialDirectory: nil,
                      parent: previousConductor)
        }
        session.replaceSSHConductor(with: recoveryConductor, removeChannelClients: false)
        updateVariablesFromConductor()
        MainActor.assumeIsolated {
            recoveryConductor.startRecovery()
        }
    }

    @objc(handleFramerRecoveryString:)
    func handleFramerRecoveryString(_ string: String) -> ConductorRecovery? {
        guard let session else {
            return nil
        }
        let recovery = MainActor.assumeIsolated {
            session.conductor?.handleRecovery(line: string)
        }
        guard let recovery else {
            return nil
        }
        let recoveredConductor = MainActor.assumeIsolated {
            Conductor(recovery: recovery)
        }
        session.replaceSSHConductor(with: recoveredConductor, removeChannelClients: false)
        updateVariablesFromConductor()
        return recovery
    }

    @objc
    func handleResynchronizeSSH() {
        // Final step of recovery: reset conductor internal state since tokens may have been dropped.
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.didResynchronize()
        }
    }

    @objc
    func handleFramerRecoveryDidFinish() {
        guard let conductor = session?.conductor else {
            return
        }
        MainActor.assumeIsolated {
            conductor.recoveryDidFinish()
        }
    }
}
