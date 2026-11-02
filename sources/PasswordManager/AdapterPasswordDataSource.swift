//
//  AdapterPasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by Claude Code on 10/21/25.
//

import Foundation
import UniformTypeIdentifiers

/// A password manager data source that communicates with an external adapter
/// using the generic password manager protocol defined in pwmplugin/Docs/spec.md
class AdapterPasswordDataSource: CommandLinePasswordDataSource {
    enum AdapterError: LocalizedError {
        case runtime(String)
        case loginFailed(String)

        /// The adapter says the session was rejected. Carries its explanation when it gave one.
        case needsAuthentication(String?)
        case badOutput
        case canceledByUser
        case handshakeFailed
        case incompatibleProtocol
        case adapterNotFound
        case invalidToken

        var reason: String? {
            switch self {
            case .runtime(let message):
                return message
            case .loginFailed(let message):
                return "Could not log in: \(message)"
            case .needsAuthentication(let message):
                return message?.isEmpty == false ? message : "Not authenticated."
            case .badOutput:
                return "Invalid output."
            case .canceledByUser:
                return nil
            case .handshakeFailed:
                return "Handshake failed."
            case .incompatibleProtocol:
                return "Incompatible protocol. Please update Latterm."
            case .adapterNotFound:
                return "Adapter not found."
            case .invalidToken:
                return "Authentication failed. Log in again."
            }
        }

        var errorDescription: String? {
            reason ?? "Unknown error"
        }

        static func from(_ response: PasswordManagerProtocol.ErrorResponse) -> AdapterError {
            // Adapter stdout is not logged because it can hold secrets, but error messages don’t.
            DLog("Adapter error: \(response.error) needsAuthentication=\(response.needsAuthentication ?? false)")
            if response.needsAuthentication == true {
                return .needsAuthentication(response.error)
            }
            return .runtime(response.error)
        }

        // Decodes and classifies an adapter error response from raw stdout, or nil when the
        // output is not an error response. Centralizes the preamble every recipe
        // outputTransformer would otherwise repeat, so error classification lives in one place.
        static func decoded(fromAdapterOutput data: Data) -> AdapterError? {
            guard let response = try? JSONDecoder().decode(PasswordManagerProtocol.ErrorResponse.self, from: data) else {
                return nil
            }
            return AdapterError.from(response)
        }
    }

    // Type aliases for protocol types
    private typealias HandshakeRequest = PasswordManagerProtocol.HandshakeRequest
    private typealias HandshakeResponse = PasswordManagerProtocol.HandshakeResponse
    private typealias UserAccount = PasswordManagerProtocol.UserAccount
    private typealias LoginRequest = PasswordManagerProtocol.LoginRequest
    private typealias LoginResponse = PasswordManagerProtocol.LoginResponse
    private typealias ListAccountsRequest = PasswordManagerProtocol.ListAccountsRequest
    private typealias ListAccountsResponse = PasswordManagerProtocol.ListAccountsResponse
    private typealias AccountEntry = PasswordManagerProtocol.Account
    private typealias AccountIdentifierEntry = PasswordManagerProtocol.AccountIdentifier
    private typealias GetPasswordRequest = PasswordManagerProtocol.GetPasswordRequest
    private typealias PasswordResponse = PasswordManagerProtocol.Password
    private typealias SetPasswordRequest = PasswordManagerProtocol.SetPasswordRequest
    private typealias SetPasswordResponse = PasswordManagerProtocol.SetPasswordResponse
    private typealias AddAccountRequest = PasswordManagerProtocol.AddAccountRequest
    private typealias AddAccountResponse = PasswordManagerProtocol.AddAccountResponse
    private typealias DeleteAccountRequest = PasswordManagerProtocol.DeleteAccountRequest
    private typealias DeleteAccountResponse = PasswordManagerProtocol.DeleteAccountResponse
    private typealias CustomCommandRequest = PasswordManagerProtocol.CustomCommandRequest
    private typealias CustomCommandResponse = PasswordManagerProtocol.CustomCommandResponse
    private typealias ErrorResponse = PasswordManagerProtocol.ErrorResponse

    private let adapterPath: String
    private var handshakeInfo: HandshakeResponse?
    private var session = AdapterSession()
    private var authToken: String? { session.token }
    private var userAccountID: String?
    private let iTermVersion: String
    private let identifier: String
    private var pathToDatabase: String?
    private var pathToExecutable: String?
    private var masterPassword: String?
    private let userAccountKey = "NoSyncAdapaterPasswordDataSource_"

    init(adapterPath: String, identifier: String) {
        self.adapterPath = adapterPath
        self.identifier = identifier
        // Get iTerm2 version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.iTermVersion = version
        } else {
            self.iTermVersion = "unknown"
        }
        userAccountID = iTermUserDefaults.userDefaults().string(forKey: userAccountKey + identifier)
    }

    // MARK: - Helper Methods

    // Encodes `request` and builds the adapter command with the user’s shell environment.
    // The environment is cached after the first fetch, so this is usually immediate.
    // `generation` is the session the request’s token belongs to. It travels with the command
    // into its output so a rejection can be matched to the right session (see AdapterSession).
    private func makeCommand<Request: Encodable>(
        _ subcommand: String,
        request: Request,
        generation: Int? = nil,
        completion: @escaping (Result<CommandLinePasswordDataSourceExecutableCommand, Error>) -> ()
    ) {
        guard let inputData = try? JSONEncoder().encode(request) else {
            completion(.failure(AdapterError.badOutput))
            return
        }
        AdapterShellEnvironment.shared.environment { [adapterPath] environment in
            var command = CommandRequestWithInput(command: adapterPath,
                                                  args: [subcommand],
                                                  env: environment,
                                                  input: inputData)
            if let generation {
                command.userData = [Self.generationKey: String(generation)]
            }
            completion(.success(command))
        }
    }

    private static let generationKey = "authGeneration"

    // The session generation a command was built with, or nil if it didn’t record one.
    private static func generation(of output: Output) -> Int? {
        return output.userData?[generationKey].flatMap { Int($0) }
    }

    private func runAdapterCommand<Request: Encodable, Response: Decodable>(
        _ subcommand: String,
        request: Request,
        completion: @escaping (Result<Response, Error>) -> ()
    ) {
        makeCommand(subcommand, request: request) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let command):
                Self.execute(command, completion: completion)
            }
        }
    }

    private static func execute<Response: Decodable>(
        _ command: CommandLinePasswordDataSourceExecutableCommand,
        completion: @escaping (Result<Response, Error>) -> ()
    ) {
        command.execAsync { output, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let output = output else {
                    completion(.failure(AdapterError.runtime("No output from adapter")))
                    return
                }

                // Try to decode as error response first
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: output.stdout) {
                    completion(.failure(AdapterError.from(errorResponse)))
                    return
                }

                if output.returnCode != 0 {
                    completion(.failure(AdapterError.runtime("Adapter returned code \(output.returnCode)")))
                    return
                }

                // Try to decode as expected response
                guard let response = try? decoder.decode(Response.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    // The adapter stdout can contain a login/session token; do not log
                    // its contents into the always-on ring. Log only the byte count.
                    RLog("Failed to decode response from adapter. Output byteCount=\(output.stdout.count)")
                    return
                }

                completion(.success(response))
            }
        }
    }

    private func ensureHandshake(_ completion: @escaping (Error?) -> ()) {
        if handshakeInfo != nil {
            completion(nil)
            return
        }

        let request = HandshakeRequest(
            iTermVersion: iTermVersion,
            minProtocolVersion: 0,
            maxProtocolVersion: 0)

        runAdapterCommand("handshake", request: request) { [weak self] (result: Result<HandshakeResponse, Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                if response.protocolVersion != 0 {
                    completion(AdapterError.incompatibleProtocol)
                    return
                }
                self.handshakeInfo = response
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
    }

    private func requestPathToDatabase(_ handshake: HandshakeResponse) -> Bool {
        if let saved = iTermUserDefaults.userDefaults().string(forKey: "PathToDatabase_\(identifier)") {
            pathToDatabase = saved
            return true
        }

        let kind = handshake.pathToDatabaseKind ?? .file
        switch kind {
        case .file:
            return requestPathToDatabaseViaFilePanel(handshake: handshake)
        case .url:
            return requestPathToDatabaseViaTextField(handshake: handshake)
        }
    }

    private func requestPathToDatabaseViaFilePanel(handshake: HandshakeResponse) -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.resolvesAliases = false
        openPanel.message = handshakeInfo?.pathToDatabasePrompt ?? "Select a database file for \(identifier)"

        if let ext = handshake.databaseExtension {
            openPanel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        }

        let response = openPanel.runModal()
        guard response == .OK, let selectedURL = openPanel.url else {
            return false
        }

        pathToDatabase = selectedURL.path
        iTermUserDefaults.userDefaults().set(selectedURL.path, forKey: "PathToDatabase_\(identifier)")
        return true
    }

    private func requestPathToDatabaseViaTextField(handshake: HandshakeResponse) -> Bool {
        let alert = NSAlert()
        alert.messageText = handshake.pathToDatabasePrompt ?? "Enter database URL for \(identifier)"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = handshake.pathToDatabasePlaceholder ?? "https://\u{2026}"
        alert.accessoryView = textField
        alert.layout()
        alert.window.makeFirstResponder(textField)

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return false
        }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return false
        }

        pathToDatabase = value
        iTermUserDefaults.userDefaults().set(value, forKey: "PathToDatabase_\(identifier)")
        return true
    }

    private var pathToExecutableKey: String {
        "PathToExecutable_\(identifier)"
    }

    // Finds the adapter’s CLI and sets pathToExecutable, calling back with false if the user
    // canceled. In order: a location the user chose earlier, if it still exists; the first
    // match on the user’s shell PATH, which survives upgrades and needs no questions; and
    // finally an open panel.
    private func locateExecutable(_ name: String, completion: @escaping (Bool) -> ()) {
        if let saved = iTermUserDefaults.userDefaults().string(forKey: pathToExecutableKey) {
            if FileManager.default.isExecutableFile(atPath: saved) {
                pathToExecutable = saved
                completion(true)
                return
            }
            // Uninstalled or upgraded away. Forget it rather than fail with a missing file.
            DLog("Saved \(identifier) CLI at \(saved) is gone")
            iTermUserDefaults.userDefaults().removeObject(forKey: pathToExecutableKey)
        }
        AdapterShellEnvironment.shared.environment { [weak self] environment in
            guard let self else { return }
            if let found = Self.findExecutable(named: name, searchPath: environment["PATH"] ?? "") {
                // Not saved: looking it up each time follows the user to a new install.
                DLog("Found \(self.identifier) CLI on PATH at \(found)")
                self.pathToExecutable = found
                completion(true)
                return
            }
            completion(self.requestPathToExecutable(name))
        }
    }

    // The first executable file named `name` in the colon-separated `searchPath`, or nil.
    static func findExecutable(named name: String,
                               searchPath: String,
                               fileManager: FileManager = .default) -> String? {
        for directory in searchPath.components(separatedBy: ":") where !directory.isEmpty {
            let candidate = (directory as NSString).appendingPathComponent(name)
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func requestPathToExecutable(_ name: String) -> Bool {
        class AdapterCLIFinderOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
            private let name: String
            init(name: String) {
                self.name = name
            }
            func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
                if FileManager.default.itemIsDirectory(url.path) {
                    return true
                }
                if url.lastPathComponent == name {
                    return true
                }
                // In case the panel resolves symlinks despite resolvesAliases being off:
                // Homebrew’s ‘bw’ is a chain of symlinks ending at build/bw.js, so accept
                // names like bw.js as well.
                return url.deletingPathExtension().lastPathComponent == name
            }
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.resolvesAliases = false
        openPanel.message = "Locate the CLI for \(identifier) named \(name)"

        let delegate = AdapterCLIFinderOpenPanelDelegate(name: name)
        return withExtendedLifetime(delegate) {
            openPanel.delegate = delegate
            let response = openPanel.runModal()
            guard response == .OK, let selectedURL = openPanel.url else {
                return false
            }
            DLog("User chose \(selectedURL.path) for the \(identifier) CLI")
            pathToExecutable = selectedURL.path
            iTermUserDefaults.userDefaults().set(selectedURL.path, forKey: pathToExecutableKey)
            return true
        }
    }

    private var standardHeader: PasswordManagerProtocol.RequestHeader {
        var header = PasswordManagerProtocol.RequestHeader(
            pathToDatabase: pathToDatabase,
            pathToExecutable: pathToExecutable,
            mode: .terminal)
        if let fields = handshakeInfo?.settingsFields, !fields.isEmpty {
            var settings = [String: String]()
            for field in fields {
                if let value = storedSettingsValue(forKey: field.key) {
                    settings[field.key] = value
                }
            }
            if !settings.isEmpty {
                header.settings = settings
            }
        }
        return header
    }

    // MARK: - Credential Persistence

    private var keychainCredentialServiceName: String {
        "iTerm2-Adapter-\(identifier)"
    }

    private func persistCredentialsToKeychain(_ password: String) {
        _ = SSKeychain.setPassword(password,
                                   forService: keychainCredentialServiceName,
                                   account: identifier)
    }

    private func loadPersistedCredentials() -> String? {
        return try? SSKeychain.password(forService: keychainCredentialServiceName,
                                        account: identifier)
    }

    private func deletePersistedCredentials() {
        _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName,
                                      account: identifier)
    }

    private func hydratePersistedCredentialsIfNeeded() {
        guard handshakeInfo?.persistsCredentials == true else { return }
        if pathToDatabase == nil {
            if let u = iTermUserDefaults.userDefaults().string(forKey: "PathToDatabase_\(identifier)"), !u.isEmpty {
                pathToDatabase = u
            }
        }
        if masterPassword == nil {
            masterPassword = loadPersistedCredentials()
        }
    }

    // MARK: - Settings Field Storage

    private func storedSettingsValue(forKey key: String) -> String? {
        guard let fields = handshakeInfo?.settingsFields else { return nil }
        guard let field = fields.first(where: { $0.key == key }) else { return nil }
        if field.persistInKeychain {
            return try? SSKeychain.password(forService: keychainCredentialServiceName, account: key)
        } else {
            return iTermUserDefaults.userDefaults().string(forKey: "AdapterSetting_\(identifier)_\(key)")
        }
    }

    private func storeSettingsValue(_ value: String, forKey key: String) {
        guard let fields = handshakeInfo?.settingsFields else { return }
        guard let field = fields.first(where: { $0.key == key }) else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if field.persistInKeychain {
            if trimmed.isEmpty {
                _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName, account: key)
            } else {
                _ = SSKeychain.setPassword(trimmed, forService: keychainCredentialServiceName, account: key)
            }
        } else {
            if trimmed.isEmpty {
                iTermUserDefaults.userDefaults().removeObject(forKey: "AdapterSetting_\(identifier)_\(key)")
            } else {
                iTermUserDefaults.userDefaults().set(trimmed, forKey: "AdapterSetting_\(identifier)_\(key)")
            }
        }
    }

    private func deleteAllSettingsFieldStorage() {
        guard let fields = handshakeInfo?.settingsFields else { return }
        for field in fields {
            if field.persistInKeychain {
                _ = SSKeychain.deletePassword(forService: keychainCredentialServiceName, account: field.key)
            } else {
                iTermUserDefaults.userDefaults().removeObject(forKey: "AdapterSetting_\(identifier)_\(field.key)")
            }
        }
    }

    private func ensureAuthentication(window: NSWindow?, _ completion: @escaping (Error?) -> ()) {
        ensureHandshake { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                completion(error)
                return
            }

            // Try to restore persisted credentials before prompting.
            self.hydratePersistedCredentialsIfNeeded()

            // If we already have a token, we're done
            if self.authToken != nil {
                completion(nil)
                return
            }

            guard let handshake = self.handshakeInfo else {
                completion(AdapterError.handshakeFailed)
                return
            }

            // Pick database first since the master password depends on which db you're using.
            if handshake.needsPathToDatabase && pathToDatabase == nil {
                if !requestPathToDatabase(handshake) {
                    completion(AdapterError.canceledByUser)
                    return
                }
            }

            guard let executableName = handshake.needsPathToExecutable, self.pathToExecutable == nil else {
                self.continueAuthentication(handshake: handshake, window: window, completion)
                return
            }
            self.locateExecutable(executableName) { [weak self] found in
                guard let self else { return }
                guard found else {
                    completion(AdapterError.canceledByUser)
                    return
                }
                self.continueAuthentication(handshake: handshake, window: window, completion)
            }
        }
    }

    // The rest of ensureAuthentication, once the database and executable are known.
    private func continueAuthentication(handshake: HandshakeResponse,
                                        window: NSWindow?,
                                        _ completion: @escaping (Error?) -> ()) {
        let loginInputs = LoginInputs(window: window,
                                      name: handshake.name,
                                      completion: completion,
                                      requiresMasterPassword: handshake.requiresMasterPassword)
        // If we restored a master password from keychain, auto-login without prompting.
        // When masterPassword is nil (e.g., first launch or requiresMasterPassword is false),
        // this falls through to the normal login() path which prompts the user.
        if handshake.persistsCredentials == true,
           let saved = masterPassword, !saved.isEmpty {
            completeEnsureAuthentication(masterPassword: saved, loginInputs: loginInputs)
            return
        }
        login(loginInputs)
    }

    private func login(_ loginInputs: LoginInputs) {
        // Get master password if required
        if loginInputs.requiresMasterPassword {
            requestPassword(loginInputs)
        } else {
            completeEnsureAuthentication(masterPassword: nil, loginInputs: loginInputs)
        }
    }

    private struct LoginInputs {
        var window: NSWindow?
        var name: String
        var completion: (Error?) -> ()
        var requiresMasterPassword: Bool
    }

    // `problem` explains why the previous attempt failed, such as a mistyped password.
    private func requestPassword(_ loginInputs: LoginInputs, problem: String? = nil) {
        let label = handshakeInfo?.masterPasswordLabel ?? "master password"
        let alert = ModalPasswordAlert("Enter \(label) for \(loginInputs.name):")
        alert.detail = problem
        // Use runAsync because macOS 26 is buggy garbage and doesn’t draw an insertion point
        // in an alert’s accessory in a sheet modal.
        alert.runAsync(window: loginInputs.window) { [weak self] masterPassword in
                if let masterPassword {
                    self?.completeEnsureAuthentication(masterPassword: masterPassword,
                                                       loginInputs: loginInputs)
                } else {
                    loginInputs.completion(AdapterError.canceledByUser)
                    return
                }
            }
    }

    private static func errorIsServiceUnavailable(_ error: Error) -> Bool {
        // A structurally-classified auth rejection is definitely NOT a service problem.
        if case AdapterError.needsAuthentication(_) = error { return false }
        let s = ((error as? AdapterError)?.reason ?? error.localizedDescription).lowercased()
        let markers = [
            "timed out", "timeout", "never started processing", "worker appears",
            "restart your keeper commander", "could not connect", "connection refused",
            "cannot connect", "could not reach", "unreachable", "offline",
            "not running", "network connection", "did not complete the request in time",
        ]
        return markers.contains { s.contains($0) }
    }

    private func completeEnsureAuthentication(masterPassword: String?, loginInputs: LoginInputs) {
        // Perform login
        let loginRequest = LoginRequest(
            header: standardHeader,
            userAccountID: self.userAccountID,
            masterPassword: masterPassword)

        self.runAdapterCommand("login", request: loginRequest) { [weak self] (result: Result<LoginResponse, Error>) in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                self.session.loggedIn(token: response.token)
                if self.handshakeInfo?.persistsCredentials == true, let masterPassword {
                    self.masterPassword = masterPassword
                    self.persistCredentialsToKeychain(masterPassword)
                }
                loginInputs.completion(nil)
            case .failure(let error):
                if !Self.errorIsServiceUnavailable(error) {
                    self.masterPassword = nil
                    self.deletePersistedCredentials()
                }
                if case let .needsAuthentication(message) = error as? AdapterError,
                   loginInputs.requiresMasterPassword {
                    self.requestPassword(loginInputs, problem: message)
                    return
                }

                if case let .runtime(description) = error as? AdapterError {
                    let loginFailed = AdapterError.loginFailed(description)
                    let selection = iTermWarning.show(withTitle: loginFailed.reason ?? description,
                                                      actions: ["Try Again", "Cancel"],
                                                      accessory: nil,
                                                      identifier: nil,
                                                      silenceable: .kiTermWarningTypePersistent,
                                                      heading: "Authentication Problem",
                                                      window: loginInputs.window)
                    if selection == .kiTermWarningSelection0 {
                        DispatchQueue.main.async {
                            self.login(loginInputs)
                        }
                        return
                    }
                    loginInputs.completion(AdapterError.canceledByUser)
                    return
                }
                loginInputs.completion(error)
            }
        }
    }

    // MARK: - Recipe Builders

    private func classify(_ error: AdapterError, output: Output) -> AdapterError {
        let generation = Self.generation(of: output)
        guard case .needsAuthentication(let message) = error else {
            session.noteAccepted(generation: generation)
            return error
        }
        switch session.noteRejected(generation: generation) {
        case .retry:
            return error
        case .stop:
            let explanation = "\(identifier) rejected the session it created when you logged in, so Latterm stopped trying to log in again."
            if let message, !message.isEmpty {
                return .runtime(message + "\n\n" + explanation)
            }
            return .runtime(explanation)
        }
    }

    // Recovery shared by every recipe. classify has already decided: a rejection that is still
    // flagged needsAuthentication should be retried, and the retry builds the command again
    // with whatever session is current, logging in first if there is none.
    private func recover(from error: Error, completion: @escaping (Error?) -> ()) {
        if case AdapterError.needsAuthentication = error {
            completion(nil)
        } else {
            completion(error)
        }
    }

    private func makeListAccountsRecipe() -> AnyRecipe<Void, [CommandLinePasswordDataSource.Account]> {
        let listWarningIdentifier = "NoSyncAdapterListWarning_\(identifier)"
        return AnyRecipe(AsyncCommandRecipe<Void, [CommandLinePasswordDataSource.Account]>(
            inputTransformer: { [weak self] context, _, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = ListAccountsRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken)

                    self.makeCommand("list-accounts", request: request, generation: self.session.generation, completion: completion)
                }
            },
            recovery: { [weak self] error, completion in
                guard let self else {
                    completion(error)
                    return
                }
                self.recover(from: error, completion: completion)
            },
            outputTransformer: { [weak self] output, completion in
                let decoder = JSONDecoder()

                // Check for error response
                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(self?.classify(error, output: output) ?? error))
                    return
                }

                guard let response = try? decoder.decode(ListAccountsResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                let accounts = response.accounts.map { entry in
                    CommandLinePasswordDataSource.Account(
                        identifier: CommandLinePasswordDataSource.AccountIdentifier(value: entry.identifier.accountID),
                        userName: entry.userName,
                        accountName: entry.accountName,
                        hasOTP: entry.hasOTP,
                        sendOTP: entry.hasOTP)
                }

                if let warning = response.warning?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
                    DispatchQueue.main.async {
                        iTermWarning.show(withTitle: warning,
                                          actions: ["OK"],
                                          accessory: nil,
                                          identifier: listWarningIdentifier,
                                          silenceable: .kiTermWarningTypePermanentlySilenceable,
                                          heading: "Password Manager",
                                          window: nil)
                    }
                }

                self?.session.noteAccepted(generation: AdapterPasswordDataSource.generation(of: output))
                completion(.success(accounts))
            }))
    }

    private func makeGetPasswordRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AccountIdentifier, CommandLinePasswordDataSource.Password>(
            inputTransformer: { [weak self] context, accountIdentifier, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = GetPasswordRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: accountIdentifier.value))

                    self.makeCommand("get-password", request: request, generation: self.session.generation, completion: completion)
                }
            },
            recovery: { [weak self] error, completion in
                guard let self else {
                    completion(error)
                    return
                }
                self.recover(from: error, completion: completion)
            },
            outputTransformer: { [weak self] output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(self?.classify(error, output: output) ?? error))
                    return
                }

                guard let response = try? decoder.decode(PasswordResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                self?.session.noteAccepted(generation: AdapterPasswordDataSource.generation(of: output))
                completion(.success(CommandLinePasswordDataSource.Password(password: response.password, otp: response.otp)))
            }))
    }

    private func makeSetPasswordRecipe() -> AnyRecipe<CommandLinePasswordDataSource.SetPasswordRequest, Void> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.SetPasswordRequest, Void>(
            inputTransformer: { [weak self] context, setPasswordRequest, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    guard let handshake = self.handshakeInfo else {
                        completion(.failure(AdapterError.handshakeFailed))
                        return
                    }

                    if !handshake.canSetPasswords {
                        completion(.failure(CommandLineRecipeError.unsupported(reason: "Adapter does not support setting passwords")))
                        return
                    }

                    let request = SetPasswordRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: setPasswordRequest.accountIdentifier.value),
                        newPassword: setPasswordRequest.newPassword)

                    self.makeCommand("set-password", request: request, generation: self.session.generation, completion: completion)
                }
            },
            recovery: { [weak self] error, completion in
                guard let self else {
                    completion(error)
                    return
                }
                self.recover(from: error, completion: completion)
            },
            outputTransformer: { [weak self] output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(self?.classify(error, output: output) ?? error))
                    return
                }

                // Just verify we can decode the response
                guard let _ = try? decoder.decode(SetPasswordResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                self?.session.noteAccepted(generation: AdapterPasswordDataSource.generation(of: output))
                completion(.success(()))
            }))
    }

    private func makeDeleteRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AccountIdentifier, Void> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AccountIdentifier, Void>(
            inputTransformer: { [weak self] context, accountIdentifier, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = DeleteAccountRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        accountIdentifier: AccountIdentifierEntry(accountID: accountIdentifier.value))

                    self.makeCommand("delete-account", request: request, generation: self.session.generation, completion: completion)
                }
            },
            recovery: { [weak self] error, completion in
                guard let self else {
                    completion(error)
                    return
                }
                self.recover(from: error, completion: completion)
            },
            outputTransformer: { [weak self] output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(self?.classify(error, output: output) ?? error))
                    return
                }

                guard let _ = try? decoder.decode(DeleteAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                self?.session.noteAccepted(generation: AdapterPasswordDataSource.generation(of: output))
                completion(.success(()))
            }))
    }

    private func makeAddAccountRecipe() -> AnyRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier> {
        return AnyRecipe(AsyncCommandRecipe<CommandLinePasswordDataSource.AddRequest, CommandLinePasswordDataSource.AccountIdentifier>(
            inputTransformer: { [weak self] context, addRequest, completion in
                guard let self = self else {
                    completion(.failure(AdapterError.runtime("Data source deallocated")))
                    return
                }

                self.ensureAuthentication(window: context.window) { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    let request = AddAccountRequest(
                        header: self.standardHeader,
                        userAccountID: self.userAccountID,
                        token: self.authToken,
                        userName: addRequest.userName,
                        accountName: addRequest.accountName,
                        password: addRequest.password)

                    self.makeCommand("add-account", request: request, generation: self.session.generation, completion: completion)
                }
            },
            recovery: { [weak self] error, completion in
                guard let self else {
                    completion(error)
                    return
                }
                self.recover(from: error, completion: completion)
            },
            outputTransformer: { [weak self] output, completion in
                let decoder = JSONDecoder()

                if let error = AdapterError.decoded(fromAdapterOutput: output.stdout) {
                    completion(.failure(self?.classify(error, output: output) ?? error))
                    return
                }

                guard let response = try? decoder.decode(AddAccountResponse.self, from: output.stdout) else {
                    completion(.failure(AdapterError.badOutput))
                    return
                }

                self?.session.noteAccepted(generation: AdapterPasswordDataSource.generation(of: output))
                completion(.success(CommandLinePasswordDataSource.AccountIdentifier(value: response.accountIdentifier.accountID)))
            }))
    }

    private lazy var _listAccountsRecipe: AnyRecipe<Void, [CommandLinePasswordDataSource.Account]> = {
        // Cache for 30 minutes like OnePasswordDataSource
        return AnyRecipe(CachingVoidRecipe(makeListAccountsRecipe(), maxAge: 30 * 60))
    }()

    var configuration: Configuration {
        return Configuration(
            listAccountsRecipe: _listAccountsRecipe,
            getPasswordRecipe: makeGetPasswordRecipe(),
            setPasswordRecipe: makeSetPasswordRecipe(),
            deleteRecipe: makeDeleteRecipe(),
            addAccountRecipe: makeAddAccountRecipe())
    }
}

extension AdapterPasswordDataSource {
    static func showError(window: NSWindow?, error: AdapterError) {
        guard let reason = error.reason else {
            return
        }
        DispatchQueue.main.async {
            iTermWarning.show(withTitle: reason,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Password Manager Error",
                              window: window)
        }
    }
}
// MARK: - PasswordManagerDataSource Protocol

@objc extension AdapterPasswordDataSource: PasswordManagerDataSource {
    @objc var name: String {
        identifier
    }
    @objc var canResetConfiguration: Bool { true }

    @objc func resetConfiguration() {
        pathToDatabase = nil
        pathToExecutable = nil
        session.clear()
        masterPassword = nil
        iTermUserDefaults.userDefaults().removeObject(forKey: "PathToDatabase_\(identifier)")
        iTermUserDefaults.userDefaults().removeObject(forKey: pathToExecutableKey)
        deletePersistedCredentials()
        deleteAllSettingsFieldStorage()
        handshakeInfo = nil
    }

    var autogeneratedPasswordsOnly: Bool {
        return false
    }

    func checkAvailability() -> Bool {
        return FileManager.default.fileExists(atPath: adapterPath)
    }

    func fetchAccounts(context: RecipeExecutionContext, completion: @escaping ([PasswordManagerAccount]) -> ()) {
        return standardAccounts(context: context,
                                configuration: configuration) { maybeAccounts, maybeError in
            if let error = maybeError as? AdapterError {
                Self.showError(window: context.window, error: error)
            }
            completion(maybeAccounts ?? [])
        }
    }

    func add(userName: String,
             accountName: String,
             password: String,
             context: RecipeExecutionContext,
             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        standardAdd(configuration,
                    userName: userName,
                    accountName: accountName,
                    password: password,
                    context: context,
                    completion: completion)
    }

    func resetErrors() {
        // Clear the session token to allow retry. When persistsCredentials is true,
        // the saved masterPassword will auto-login without prompting on the next attempt.
        session.clear()
    }

    func reload(_ completion: () -> ()) {
        configuration.listAccountsRecipe.invalidateRecipe()
        completion()
    }

    func consolidateAvailabilityChecks(_ block: () -> ()) {
        // No caching of availability checks needed for adapter
        block()
    }

    func toggleShouldSendOTP(context: RecipeExecutionContext,
                             account: PasswordManagerAccount,
                             completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        it_fatalError()
    }

    var supportsMultipleAccounts: Bool {
        handshakeInfo?.userAccounts != nil
    }

    func switchAccount(completion: @escaping () -> ()) {
        let userAccounts = handshakeInfo?.userAccounts ?? []
        let pickedAccountID = AccountPicker.askUserToSelect(from: userAccounts.map {
            AccountPicker.Account(title: $0.name, accountID: $0.identifier)
        })
        userAccountID = pickedAccountID
        iTermUserDefaults.userDefaults().set(pickedAccountID, forKey: userAccountKey + identifier)
        completion()
    }
}

// MARK: - AdapterCapabilities

extension AdapterPasswordDataSource: AdapterCapabilities {
    @objc var hasSettingsFields: Bool {
        !(handshakeInfo?.settingsFields ?? []).isEmpty
    }

    @objc var settingsFieldDescriptions: [[String: Any]]? {
        handshakeInfo?.settingsFields?.map { field in
            var dict: [String: Any] = [
                "key": field.key,
                "label": field.label,
                "isSecret": field.isSecret,
                "persistInKeychain": field.persistInKeychain
            ]
            if let p = field.placeholder { dict["placeholder"] = p }
            if let n = field.note { dict["note"] = n }
            return dict
        }
    }

    @objc var customCommandDescriptions: [[String: String]]? {
        handshakeInfo?.customCommands?.map { cmd in
            var dict: [String: String] = ["name": cmd.name, "label": cmd.label]
            if let icon = cmd.icon { dict["icon"] = icon }
            return dict
        }
    }

    private static let builtInSubcommands: Set<String> = [
        "handshake", "login", "list-accounts", "get-password",
        "set-password", "add-account", "delete-account"
    ]

    @objc func runCustomCommand(_ name: String, window: NSWindow?, completion: @escaping (String?, Error?) -> Void) {
        if Self.builtInSubcommands.contains(name) {
            completion(nil, AdapterError.runtime("Cannot run built-in subcommand \u{201c}\(name)\u{201d} as a custom command"))
            return
        }
        ensureAuthentication(window: window) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completion(nil, error)
                return
            }
            let request = CustomCommandRequest(
                header: self.standardHeader,
                userAccountID: self.userAccountID,
                token: self.authToken,
                commandName: name)
            self.runAdapterCommand(name, request: request) { (result: Result<CustomCommandResponse, Error>) in
                switch result {
                case .success(let response):
                    completion(response.message, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
    }

    @objc func settingsValue(forKey key: String) -> String? {
        return storedSettingsValue(forKey: key)
    }

    @objc func setSettingsValue(_ value: String, forKey key: String) {
        storeSettingsValue(value, forKey: key)
    }
}
