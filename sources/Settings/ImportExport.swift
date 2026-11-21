//
//  ImportExport.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/4/23.
//

import Foundation
import UniformTypeIdentifiers

@objc(iTerm2ImportExport)
class ImportExport: NSObject {
    fileprivate enum ExportOutcome {
        case success
        case cancelled
        case failure(String)
    }

    fileprivate static func performExportFlow() -> ExportOutcome {
        DLog("Begin")
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = ["itermexport"].compactMap { UTType(filenameExtension: $0) }
        savePanel.nameFieldStringValue = "Latterm State.itermexport"
        savePanel.title = "Export Latterm Settings and Data"

        let response = savePanel.runModal()
        guard response == NSApplication.ModalResponse.OK else {
            return .cancelled
        }
        guard let url = savePanel.url else {
            return .cancelled
        }
        RLog("Export to \(url.path)")
        do {
            let exporter = Exporter()
            try exporter.export(to: url)
            if iTermAdvancedSettingsModel.revealExportedSettingsAndData() {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return .success
        } catch {
            RLog("Failed: \(error)")
            switch error {
            case ImportExportError.failedToCreateTempDir(let reason):
                return .failure("Failed to create temporary directory: \(reason)")
            case ImportExportError.failedToCreateIntermediateFolder(let reason):
                return .failure("Failed to create folder: \(reason)")
            case ImportExportError.failedToCopyFile(let reason):
                return .failure("Failed to copy file: \(reason)")
            case ImportExportError.failedToSaveFile(let reason):
                return .failure("Failed to save file: \(reason)")
            case ImportExportError.bug(let reason):
                return .failure("A bug was encountered: \(reason). Please report this at https://github.com/ecnelises/latterm/issues")
            case ImportExportError.failedToCreateArchive(let reason):
                return .failure("Failed to create archive: \(reason)")
            case ImportExportError.failedToLoadFile(let reason):
                return .failure("Failed to load file: \(reason)")
            case ImportExportError.corruptDataFound(let reason):
                return .failure("Malformed data found: \(reason)")
            default:
                return .failure("Unexpected error: \(error.localizedDescription)")
            }
        }
    }

    @objc
    static func exportAll() -> String? {
        switch performExportFlow() {
        case .success, .cancelled:
            return nil
        case .failure(let message):
            return message
        }
    }

    @objc
    static func importAll() -> String? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = ["itermexport"].compactMap { UTType(filenameExtension: $0) }
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        do {
            let selection = iTermWarning.show(
                withTitle: "Secure settings will be updated, which may require you to enter your password. Then Latterm will restart and finish importing.",
                actions: ["OK", "Cancel"],
                accessory: nil,
                identifier: nil,
                silenceable: .kiTermWarningTypePersistent,
                heading: "Importing Settings and Data",
                window: nil)
            if selection == .kiTermWarningSelection1 {
                return nil
            }
            try Importer().importEntities(from: url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @objc
    static func finishImporting() {
        let path = iTermUserDefaults.importPath!
        let url = URL(fileURLWithPath: path)
        _ = try? Importer().importExtractedEntities(from: url, phase: .final)
        precondition(url.lastPathComponent.hasPrefix(".") && url.lastPathComponent.utf16.count > 12)
        try? FileManager.default.removeItem(at: url)
        NSApp.relaunch()
    }

    // Returns nil on success or cancellation. Returns an error message string if
    // the optional export step failed and the caller should surface it to the
    // user. On a successful erase, this method does not return: it calls
    // _exit(0) so no normal teardown code path can re-save state.
    @objc
    static func eraseAll(window: NSWindow?) -> String? {
        let exportSelection = iTermWarning.show(
            withTitle: "Would you like to export your settings and data first? You will be able to re-import the exported file later if you change your mind.",
            actions: ["Export First", "Skip Export", "Cancel"],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: "Erase All Settings and Data",
            window: window)

        switch exportSelection {
        case .kiTermWarningSelection0:
            switch performExportFlow() {
            case .success:
                break
            case .cancelled:
                // Cancelling the save panel during "Export First" cancels
                // the whole erase flow rather than silently proceeding to
                // the destructive confirmation with no backup made.
                return nil
            case .failure(let message):
                // Show the export failure under its own heading rather
                // than letting the caller surface it under "Problem
                // Erasing Settings and Data" — the failure was during
                // export, not erase, and the erase has not happened.
                _ = iTermWarning.show(
                    withTitle: message,
                    actions: ["OK"],
                    accessory: nil,
                    identifier: nil,
                    silenceable: .kiTermWarningTypePersistent,
                    heading: "Problem Exporting Settings and Data",
                    window: window)
                return nil
            }
        case .kiTermWarningSelection1:
            break  // Skip Export
        default:
            return nil
        }

        let dryRun = iTermAdvancedSettingsModel.dryRunEraseAllSettingsAndData()
        let confirmTitle: String
        let confirmHeading: String
        let actionLabel: String
        if dryRun {
            confirmTitle = """
            Dry-run mode is enabled. Latterm will log to Console.app what it would erase and stay running. Nothing will actually be deleted.
            """
            confirmHeading = "Dry-Run Erase?"
            actionLabel = "Run Dry Run"
        } else {
            confirmTitle = """
            The following will be erased and Latterm will quit immediately:

            \u{2022} Preferences (profiles, key bindings, arrangements, advanced settings)
            \u{2022} Saved windows and sessions
            \u{2022} Secure settings
            \u{2022} The contents of ~/.iterm2 and ~/Library/Application Support/iTerm2

            Items stored in the macOS Keychain (such as Password Manager entries) are not erased and must be removed manually from Keychain Access if you want them gone too. On systems with networked home directories, secure settings stored under /usr/local are written by an administrator and may also need to be removed manually.

            This cannot be undone.
            """
            confirmHeading = "Erase Everything?"
            actionLabel = "Erase Everything and Quit"
        }

        let warning = iTermWarning()
        warning.title = confirmTitle
        warning.heading = confirmHeading
        let eraseAction = iTermWarningAction(label: actionLabel, block: nil)
        eraseAction.destructive = !dryRun
        warning.warningActions = [iTermWarningAction(label: "Cancel"), eraseAction]
        warning.warningType = .kiTermWarningTypePersistent
        warning.window = window
        let confirm = warning.runModal()
        if confirm != .kiTermWarningSelection1 {
            return nil
        }

        Eraser(dryRun: dryRun).eraseEverything()
        if !dryRun {
            _exit(0)
        }
        _ = iTermWarning.show(
            withTitle: "Latterm logged what it would have erased to Console.app. Nothing was actually deleted because the “Dry-run Erase All Settings and Data” advanced setting is enabled.",
            actions: ["OK"],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: "Dry Run Complete",
            window: window)
        return nil
    }
}

// Wraps every state-mutating action the eraser performs so a single dry-run
// flag can divert it into NSLog instead of actually deleting things. Use this
// for every file/system mutation; do not call FileManager.removeItem or
// removePersistentDomain directly from an eraser.
private struct EraseAction {
    let dryRun: Bool

    func remove(atPath path: String) {
        if dryRun {
            NSLog("[Erase dry-run] would remove %@", path)
            return
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func removeUserDefaults(suiteName: String) {
        if dryRun {
            NSLog("[Erase dry-run] would removePersistentDomain forName: %@", suiteName)
            return
        }
        // The forName: variant of removePersistentDomain is routed through
        // cfprefsd by domain name, so the receiver instance is functionally
        // irrelevant here. Use iTermUserDefaults.userDefaults() anyway to
        // match the project convention from AGENTS.md.
        let defaults = iTermUserDefaults.userDefaults()
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
    }
}

private struct Eraser {
    private let config = ImportExportConfig()
    private let action: EraseAction

    init(dryRun: Bool) {
        self.action = EraseAction(dryRun: dryRun)
    }

    func eraseEverything() {
        for entity in config.entities {
            erase(entity: entity)
        }
        eraseSavedApplicationState()
    }

    // The export/import config does not include macOS's per-app saved
    // window-restoration directory because export/import has no use for
    // it, but for "Erase All Settings and Data" leaving it behind would
    // contradict the confirmation dialog and let macOS attempt window
    // restoration on next launch.
    private func eraseSavedApplicationState() {
        // macOS keys saved-state directories by bundle identifier. The
        // -suite argv only changes which NSUserDefaults suite is used; it
        // does not change the bundle identifier, so customSuiteName is
        // not relevant here.
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return
        }
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State")
            .appendingPathComponent("\(bundleID).savedState")
        action.remove(atPath: path)
    }

    private func erase(entity: ImportExportConfig.Entity) {
        switch entity.flavor {
        case .secureUserDefaults:
            SecureUserDefaultsImporterExporter().erase(action: action)
        case .userDefaults:
            UserDefaultsImporterExporter().erase(action: action)
        case let .folder(path, _):
            // Exclusions exist for export (skip transient/redundant files).
            // Erase ignores them; we want a clean slate.
            FolderImporterExporter().erase(path: path, action: action)
        }
    }
}

private enum ImportExportError: Error {
    case failedToCreateTempDir(String)
    case failedToCreateIntermediateFolder(String)
    case failedToCopyFile(String)
    case failedToSaveFile(String)
    case bug(String)
    case failedToCreateArchive(String)
    case failedToLoadFile(String)
    case corruptDataFound(String)
}

private func iTermMakeTempDir() throws -> URL {
    let tempDirURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
    return tempDirURL
}

private struct ImportExportConfig {
    enum BaseDirectory {
        case home
        case applicationSupport
    }
    struct Path {
        var baseDirectory: BaseDirectory
        var relativePath: String?

        var url: URL {
            let base = {
                switch baseDirectory {
                case .home:
                    return NSHomeDirectory()
                case .applicationSupport:
                    return FileManager.default.spacelessAppSupportWithoutCreatingLink()
                }
            }()
            guard let relativePath else {
                return URL(fileURLWithPath: base)
            }
            let fullPath = base.appendingPathComponent(relativePath)
            return URL(fileURLWithPath: fullPath)
        }
    }

    struct Entity {
        enum Flavor {
            // Exclusions are glob paths relative to the base directory + path.
            case folder(Path, exclude: Set<String>)
            case userDefaults
            case secureUserDefaults
        }

        var key: String
        var displayName: String
        var flavor: Flavor
    }
    var entities: [Entity] = [
        Entity(key: "secure-user-defaults",
               displayName: "Secure Settings",
               flavor: .secureUserDefaults),
        Entity(key: "user-defaults",
               displayName: "User Defaults",
               flavor: .userDefaults),
        Entity(key: "dot-iterm2",
               displayName: "~/.iterm2",
               flavor: .folder(Path(baseDirectory: .home, relativePath: ".iterm2"),
                               exclude: Set(["AppSupport", "iTermServer-*", "it2", "sockets", "Scripts"]))),
        Entity(key: "app-support",
               displayName: "Application Support",
               flavor: .folder(Path(baseDirectory: .applicationSupport, relativePath: nil),
                               exclude: Set(["????????-????-????-????-????????????",
                                             "*.secureSetting",
                                             "Scripts",
                                             "adblock-compiled.json",
                                             "disable-automation-auth",
                                             "iTermServer-*",
                                             "iterm2-daemon-*",
                                             "iterm2env*",
                                             "parsers",
                                             "private",
                                             "servers",
                                             "version.txt"]))),
    ]
}

private class Importer {
    private let config = ImportExportConfig()

    static func launchStatusApp() -> FileHandle? {
        let appPath = Bundle.main.bundlePath + "/Contents/MacOS/iTerm2ImportStatus.app/Contents/MacOS/iTerm2ImportStatus"
        let task = Process()
        task.launchPath = appPath

        // Create a pipe and assign it to the task's standard input.
        let pipe = Pipe()
        task.standardInput = pipe

        do {
            try task.run()
        } catch {
            print("Failed to launch task: \(error)")
            return nil
        }
        try? pipe.fileHandleForReading.close()
        return pipe.fileHandleForWriting
    }

    private let statusFileHandle: FileHandle?

    init() {
        statusFileHandle = Self.launchStatusApp()
    }

    private func setStatus(_ status: String) {
        guard let fileHandle = statusFileHandle else {
            print("File handle is nil")
            return
        }

        DispatchQueue.global().async {
            if let data = (status + "\n").data(using: .utf8) {
                do {
                    try ObjC.catching {
                        fileHandle.write(data)
                    }
                } catch {
                    DLog("Failed to write to file handle: \(error)")
                }
            } else {
                DLog("Failed to convert string to data")
            }
        }
    }

    func importEntities(from url: URL) throws {
        let tempDir = try makeTempDir()
        setStatus("Extracting Archive")
        if NSData.untar(fromArchive: url, to: tempDir) != 0 {
            return
        }

        try importExtractedEntities(from: tempDir, phase: .initial)
    }

    fileprivate enum Phase {
        case initial
        case final
    }

    fileprivate func importExtractedEntities(from sourceFolder: URL, phase: Phase) throws {
        for entity in config.entities {
            try importEntity(entity, from: sourceFolder, phase: phase)
        }
    }

    private func importEntity(_ entity: ImportExportConfig.Entity,
                              from baseURL: URL,
                              phase: Phase) throws {
        let url = baseURL.appendingPathComponent(entity.key)
        setStatus("Importing \(entity.displayName)")
        switch entity.flavor {
        case .secureUserDefaults:
            switch phase {
            case .initial:
                try SecureUserDefaultsImporterExporter().performImport(from: url)
            case .final:
                break
            }
        case .userDefaults:
            try UserDefaultsImporterExporter().performImport(from: url)
        case let .folder(path, _):
            try FolderImporterExporter().performImport(from: url, to: path)
        }
    }

    private func makeTempDir() throws -> URL {
        do {
            let tempDirURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("." + UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
            return tempDirURL
        } catch {
            throw ImportExportError.failedToCreateTempDir(error.localizedDescription)
        }
    }
}

private class Exporter {
    private let config = ImportExportConfig()

    func export(to url: URL) throws {
        let tempDir = try makeTempDir()

        for entity in config.entities {
            try export(entity: entity, to: tempDir)
        }

        return try archive(filesInFolder: tempDir, to: url)
    }

    private func makeTempDir() throws -> URL {
        do {
            return try iTermMakeTempDir()
        } catch {
            throw ImportExportError.failedToCreateTempDir(error.localizedDescription)
        }
    }

    private func export(entity: ImportExportConfig.Entity, to base: URL) throws {
        DLog("Begin \(entity.key)")
        let destination = base.appendingPathComponent(entity.key)
        do {
            try FileManager.default.createDirectory(at: destination,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToCreateIntermediateFolder(error.localizedDescription)
        }

        switch entity.flavor {
        case .folder(let path, exclude: let exclusions):
            try FolderImporterExporter().export(path: path,
                                                exclude: exclusions,
                                                destination: destination)
        case .userDefaults:
            try UserDefaultsImporterExporter().export(to: destination)
        case .secureUserDefaults:
            try SecureUserDefaultsImporterExporter().export(to: destination)
        }
    }

    func archive(filesInFolder source: URL, to destination: URL) throws {
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: source,
                                                                      includingPropertiesForKeys: nil,
                                                                      options: .skipsHiddenFiles)
        let data: NSData
        do {
            data = try NSData(tgzContainingFiles: sourceFiles.map { $0.resolvingSymlinksInPath().lastPathComponent },
                              relativeToPath: source.resolvingSymlinksInPath().path,
                              includeExtendedAttrs: true)
        } catch {
            throw ImportExportError.failedToCreateArchive(error.localizedDescription)
        }
        do {
            try data.write(to: destination)
        } catch {
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }

}

private struct FolderImporterExporter {
    func export(path: ImportExportConfig.Path,
                exclude: Set<String>,
                destination: URL) throws {
        DLog("Begin")
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path.url.resolvingSymlinksInPath().path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            return
        }
        do {
            try FileManager.default.deepCopyContentsOfDirectory(source: path.url,
                                                                to: destination,
                                                                excluding: exclude)
        } catch {
            throw ImportExportError.failedToCopyFile(error.localizedDescription)
        }
    }

    func performImport(from source: URL,
                       to destination: ImportExportConfig.Path) throws {
        do {
            try FileManager.default.deepCopyContentsOfDirectory(source: source,
                                                                to: destination.url,
                                                                excluding: Set())
        } catch {
            throw ImportExportError.failedToCopyFile(error.localizedDescription)
        }
    }

    func erase(path: ImportExportConfig.Path, action: EraseAction) {
        // Path.url resolves .applicationSupport via the spaceless symlink
        // ~/.iterm2/AppSupport, which is created lazily and may not exist
        // yet on a fresh install or after the dot-dir entity unlinks it
        // earlier in this same session. Use the canonical app-support path
        // directly so we don't silently no-op and leave the user's
        // profiles, arrangements, and SavedState on disk after they
        // confirmed "Erase Everything and Quit".
        let target: String
        switch path.baseDirectory {
        case .home:
            target = path.url.resolvingSymlinksInPath().path
        case .applicationSupport:
            guard let real = FileManager.default.applicationSupportDirectoryWithoutCreating(),
                  !real.isEmpty else {
                return
            }
            if let relative = path.relativePath, !relative.isEmpty {
                target = (real as NSString).appendingPathComponent(relative)
            } else {
                target = real
            }
        }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: target) else {
            return
        }
        for item in items {
            let fullPath = (target as NSString).appendingPathComponent(item)
            action.remove(atPath: fullPath)
        }
    }
}

private struct UserDefaultsImporterExporter {
    private let filename = "UserDefaults.plist"
    func export(to destination: URL) throws {
        DLog("Begin")
        let dictionary = iTermRemotePreferences.sharedInstance().userDefaultsDictionary
        try dictionary.saveAsPropertyList(to: destination.appendingPathComponent(filename))
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        if iTermUserDefaults.importPath != nil {
            DLog("Have import path")
            iTermPreferences.initializeUserDefaults()
            iTermPreferences.setBool(false, forKey: kPreferenceKeyLoadPrefsFromCustomFolder)
            iTermPreferences.setString(nil, forKey: kPreferenceKeyCustomFolder)
            iTermUserDefaults.importPath = nil
            return
        }
        DLog("No import path")
        iTermPreferences.setBool(true, forKey: kPreferenceKeyLoadPrefsFromCustomFolder)
        iTermPreferences.setString(source.appendingPathComponent(filename).path,
                                   forKey: kPreferenceKeyCustomFolder)
        iTermUserDefaults.importPath = source.deletingLastPathComponent().path

        NSApp.relaunch()
    }

    func erase(action: EraseAction) {
        // The main suite (settings, profiles, advanced settings, etc.).
        let mainSuite: String
        if let custom = iTermUserDefaults.customSuiteName() as String?, !custom.isEmpty {
            mainSuite = custom
        } else if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            mainSuite = bundleID
        } else {
            return
        }
        eraseSuite(mainSuite, action: action)

        // iTermPrivateUserDefaults (defined in iTermUserDefaults.m) writes
        // to a separate ".private" suite that holds NoSyncSearchHistory2
        // and similar private state. Mirror its naming exactly: when no
        // -suite was given the private suite is the literal string
        // "com.googlecode.iterm2.private", not a derivation of the bundle
        // identifier.
        let privateSuite: String
        if let custom = iTermUserDefaults.customSuiteName() as String?, !custom.isEmpty {
            privateSuite = "\(custom).private"
        } else {
            privateSuite = "com.googlecode.iterm2.private"
        }
        eraseSuite(privateSuite, action: action)
    }

    private func eraseSuite(_ suiteName: String, action: EraseAction) {
        action.removeUserDefaults(suiteName: suiteName)
        // removePersistentDomain + synchronize asks cfprefsd to clear and
        // flush, but cfprefsd's on-disk behavior for an empty domain is
        // implementation-defined (it may rewrite an empty plist or leave
        // the existing file alone). Remove the file directly so the next
        // launch definitely sees no preferences regardless of which path
        // cfprefsd takes.
        let plistPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Preferences")
            .appendingPathComponent("\(suiteName).plist")
        action.remove(atPath: plistPath)
    }
}

extension NSApplication {
    @objc
    func relaunch() -> Never {
        RLog("Relaunch")
        let pid = ProcessInfo().processIdentifier
        let pathToSelf = Bundle.main.bundlePath
        let quotedPathToSelf = pathToSelf.withEscapedShellCharacters(includingNewlines: true) as String
        // Preserve -suite so the relaunched instance uses the same defaults domain. -n forces a
        // new instance, since open ignores --args when it finds a running copy to activate.
        let openCommand: String
        if let suiteName = iTermUserDefaults.customSuiteName() {
            let quotedSuiteName = suiteName.withEscapedShellCharacters(includingNewlines: true) as String
            openCommand = "/usr/bin/open -n \(quotedPathToSelf) --args -suite \(quotedSuiteName)"
        } else {
            openCommand = "/usr/bin/open \(quotedPathToSelf)"
        }
        DLog("Relaunch with: \(openCommand)")
        let script = ["while /bin/kill -0 \(pid) >&/dev/null",
                      "do /bin/sleep 0.1",
                      "done",
                      openCommand].joined(separator: ";")
        Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", "(" + script + ")&"])
        exit(0)
    }
}

private struct SecureUserDefaultsImporterExporter {
    private let filename = "SecureUserDefaults.plist"
    func export(to destination: URL) throws {
        DLog("Begin")
        let dictionary = SecureUserDefaults.serializeAll()
        try dictionary.saveAsPropertyList(to: destination.appendingPathComponent(filename))
    }

    func performImport(from source: URL) throws {
        DLog("Begin")
        let data: Data
        do {
            data = try Data(contentsOf: source.appendingPathComponent(filename))
        } catch {
            DLog("\(error)")
            throw ImportExportError.failedToLoadFile(error.localizedDescription)
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            DLog("\(error) for \(data.stringOrHex)")
            throw ImportExportError.corruptDataFound("Invalid data found at \(source.path)")
        }
        if let stringDict = plist as? [String: String] {
            reallyPerformImport(stringDict)
        } else {
            DLog("Cast failed for \(plist)")
            throw ImportExportError.corruptDataFound("Wrong format content for \(source.path)")
        }
    }

    private func reallyPerformImport(_ dict: [String: String]) {
        SecureUserDefaults.deserializeAll(dict: dict)
    }

    func erase(action: EraseAction) {
        // Secure user defaults files in the app support directory are
        // removed by the app-support folder erase (they match the
        // *.secureSetting suffix). The fallback location used when the home
        // directory is on a network mount lives outside any folder entity,
        // so clear it explicitly here.
        let folder: String
        if let suite = iTermUserDefaults.customSuiteName() as String?, !suite.isEmpty {
            folder = "/usr/local/\(suite)-secure-settings"
        } else {
            folder = "/usr/local/iTerm2-secure-settings"
        }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
            return
        }
        for item in items where (item as NSString).pathExtension == "secureSetting" {
            let fullPath = (folder as NSString).appendingPathComponent(item)
            action.remove(atPath: fullPath)
        }
    }
}

func relativePath(base: URL, absolutePath: URL) -> String? {
    let baseComponents = base.pathComponents
    let absoluteComponents = absolutePath.pathComponents

    // If the absolute path is not within the base directory, return nil
    guard absoluteComponents.starts(with: baseComponents) else {
        return nil
    }

    guard absoluteComponents.count > baseComponents.count else {
        return nil
    }

    return absoluteComponents[baseComponents.count...].joined(separator: "/")
}

fileprivate extension Dictionary {
    func saveAsPropertyList(to destination: URL) throws {
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: self,
                                                                  format: .xml,
                                                                  options: 0) else {
            throw ImportExportError.bug("Failed to serialize user defaults")
        }

        do {
            try plistData.write(to: destination)
        } catch {
            throw ImportExportError.failedToSaveFile(error.localizedDescription)
        }
    }
}

extension FileManager {
    // Sockets, FIFOs, and devices can't be copied, and they are runtime state rather than data
    // (for example, the sockets it2 over SSH creates in ~/.iterm2/it2), so copies skip them.
    // Symbolic links are not special; they are copied as links.
    private func isSpecialFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.fileResourceTypeKey]).fileResourceType else {
            return false
        }
        switch type {
        case .socket, .namedPipe, .characterSpecial, .blockSpecial:
            return true
        default:
            return false
        }
    }

    func deepCopyContentsOfDirectory(source: URL,
                                     to destination: URL,
                                     excluding exclusions: Set<String>) throws {
        let fileManager = FileManager.default

        // Create the destination directory if it does not exist
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)

        // Get the contents of the source directory
        let directoryContents = try fileManager.contentsOfDirectory(at: source.resolvingSymlinksInPath(),
                                                                    includingPropertiesForKeys: nil,
                                                                    options: .skipsHiddenFiles)

        // Loop through the contents of the source directory
        for url in directoryContents {
            let fileName = url.lastPathComponent

            // Check if the file should be excluded based on the glob pattern
            if exclusions.contains(where: { fileName.matchesGlob($0) }) {
                DLog("Skipping file: \(fileName)")
                continue
            }

            if isSpecialFile(url) {
                DLog("Skipping special file: \(url.path)")
                continue
            }

            // Determine the destination file URL
            let destinationURL = destination.appendingPathComponent(fileName)

            // Check if the item at the URL is a directory
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            // If the item is a directory, recursively copy its contents
            if isDirectory.boolValue {
                // Copy the directory recursively
                let subDestination = destination.appendingPathComponent(fileName)
                try deepCopyContentsOfDirectory(source: url, to: subDestination, excluding: Set())
            } else {
                // Copy the file to the destination directory
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: url, to: destinationURL)
            }
        }
    }

    func deepCopyDirectory(at sourceURL: URL,
                           to destinationURL: URL,
                           shouldCopySubdirectory: (URL) -> Bool) throws {
        try? createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let contents = try contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [])
        for item in contents {
            if isSpecialFile(item) {
                DLog("Skipping special file: \(item.path)")
                continue
            }
            let destinationItemURL = destinationURL.appendingPathComponent(item.lastPathComponent)
            var isDirectory: ObjCBool = false
            guard fileExists(atPath: item.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                if shouldCopySubdirectory(item) {
                    try deepCopyDirectory(at: item,
                                          to: destinationItemURL,
                                          shouldCopySubdirectory: shouldCopySubdirectory)
                }
            } else {
                try copyItem(at: item, to: destinationItemURL)
            }
        }
    }
}

extension String {
    func matchesGlob(_ pattern: String) -> Bool {
        return self.withCString { s in
            return pattern.withCString { p in
                fnmatch(p, s, FNM_PATHNAME) == 0
            }
        }
    }
}
