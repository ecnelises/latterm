//
//  iTermNonTextPasteHelper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/9/26.
//

import AppKit
import UniformTypeIdentifiers

// Where a pasted file's path would be used.
@objc(iTermNonTextPasteDestination)
enum iTermNonTextPasteDestination: Int, CustomStringConvertible {
    // This machine. Its paths are meaningful.
    case local
    // Proven to be another machine: an ssh integration connection, or an OSC 7 machineID token
    // that doesn't match ours. A local path names nothing there.
    case verifiedRemote
    // Judged remote only because the reported hostname isn't one of ours. That can be wrong (a
    // shell whose $HOST went stale, a name we don't recognize), so the local path is still offered
    // as a way out. See issue 13117.
    case unverifiedRemote

    var canUpload: Bool {
        return self != .local
    }

    var description: String {
        switch self {
        case .local: return "local"
        case .verifiedRemote: return "verifiedRemote"
        case .unverifiedRemote: return "unverifiedRemote"
        }
    }
}

@objc(iTermNonTextPasteHelperDelegate)
protocol iTermNonTextPasteHelperDelegate: AnyObject {
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, pasteString string: String)
    func nonTextPasteHelperWindow(_ sender: iTermNonTextPasteHelper) -> NSWindow?
    func nonTextPasteHelperDestination(_ sender: iTermNonTextPasteHelper) -> iTermNonTextPasteDestination
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFiles paths: [String])
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFileAndPastePath path: String)
    func nonTextPasteHelper(_ sender: iTermNonTextPasteHelper, uploadFilesAndPastePaths paths: [String])
}

@objc(iTermNonTextPasteHelper)
class iTermNonTextPasteHelper: NSObject {
    @objc weak var delegate: iTermNonTextPasteHelperDelegate?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    @objc static func pasteboardHasNonTextContent() -> Bool {
        let pb = NSPasteboard.general
        return pb.hasFileURLs() || pb.hasRawImageData()
    }

    @objc func pasteNonTextContent() -> Bool {
        DLog("pasteNonTextContent called")
        let pb = NSPasteboard.general
        if pb.hasFileURLs() {
            guard let paths = pb.filePaths(), !paths.isEmpty else {
                RLog("hasFileURLs but no paths found")
                return false
            }
            RLog("Handling file paste with \(paths.count) paths")
            return handleFilePaste(paths)
        } else if pb.hasRawImageData() {
            guard let imageData = pb.rawImageData() else {
                RLog("hasRawImageData but rawImageData() returned nil")
                return false
            }
            // Try to determine the file extension, but proceed even if we can't
            var fileExtension: String? = nil
            if let utType = pb.rawImageDataUTType(),
               let type = UTType(utType) {
                fileExtension = type.preferredFilenameExtension
            }
            RLog("Handling image data paste: \(imageData.count) bytes, extension=\(fileExtension ?? "unknown")")
            return handleImageDataPaste(imageData: imageData, fileExtension: fileExtension)
        }
        DLog("No non-text content found on pasteboard")
        return false
    }

    @objc func showPasteOptionsForFiles(_ files: [String]) {
        _ = handleFilePaste(files)
    }

    // Raw values are stable identity (used for logging and for cancel-label matching); user-facing
    // button text comes from displayName.
    enum FilePasteAction: String {
        case pastePath = "Paste Path"
        case pastePaths = "Paste Paths"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case pasteBase64Archive = "Paste Base64-Encoded Archive (tar.gz)"
        case pasteAsText = "Paste as Text"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case uploadAndPastePaths = "Upload and Paste Paths"
        case cancel = "Cancel"

        var displayName: String {
            switch self {
            case .pastePath: return "Paste Path"
            case .pastePaths: return "Paste Paths"
            case .pasteBase64: return "Paste Base64-Encoded Contents"
            case .pasteBase64Archive: return "Paste Base64-Encoded Archive (tar.gz)"
            case .pasteAsText: return "Paste as Text"
            case .upload: return "Upload"
            case .uploadAndPastePath: return "Upload and Paste Path"
            case .uploadAndPastePaths: return "Upload and Paste Paths"
            case .cancel: return "Cancel"
            }
        }

        // A permanently silenced warning remembers an iTermWarningSelection. By default that is a
        // button position, which would be wrong here because the action list varies with the paste
        // (local vs. remote, file vs. folder, text-decodable or not). Give every action a fixed
        // selection instead and hand it to iTermWarning as an actionToSelectionMap.
        //
        // What this is for, now that fileWarningIdentifier names the set of options offered: two
        // dialogs with different options no longer share a saved answer at all, so this is not what
        // prevents a cross-dialog collision. It is forward compatibility for the two ways one
        // identifier still spans more than one list. Reordering buttons does not reset a saved
        // answer, and pasteAsText, which is excluded from the identifier, fails to resolve when a
        // binary file omits it rather than firing whatever else landed in its position.
        //
        // pastePath/pastePaths and uploadAndPastePath/uploadAndPastePaths each share a selection.
        // Within a pair they are the same choice, the singular and plural forms never appear
        // together, and seven selections is all iTermWarning defines while the one-file dialog uses
        // every one of them.
        var selection: iTermWarningSelection {
            switch self {
            case .pastePath, .pastePaths: return .kiTermWarningSelection0
            case .pasteBase64: return .kiTermWarningSelection1
            case .pasteBase64Archive: return .kiTermWarningSelection2
            case .pasteAsText: return .kiTermWarningSelection3
            case .upload: return .kiTermWarningSelection4
            case .uploadAndPastePath, .uploadAndPastePaths: return .kiTermWarningSelection5
            case .cancel: return .kiTermWarningSelection6
            }
        }
    }

    // The user-defaults key under which a silenced choice is remembered, derived from the options
    // actually offered so that two pastes share a saved answer only when they present the same
    // choices. A hand-named key cannot do this: one name covering several button lists means one
    // saved answer between them, and whichever shape you answered last is the only one that stays
    // silenced.
    //
    // Sorted, so reordering buttons (a display decision) does not reset anyone: actionToSelectionMap
    // carries the saved choice across a reorder. Built from rawValue, which is stable identity,
    // never displayName, which is localized and would give the same user a different memory per
    // system language. Non-alphanumerics are stripped so a label like "Paste Base64-Encoded Archive
    // (tar.gz)" does not put spaces, parens and a dot in a defaults key.
    //
    // Known cost: adding an option to a dialog changes its key, so everyone is asked once more for
    // that dialog. The dialog did change, so that is defensible, but it is invisible from the call
    // site, hence this note.
    private static func warningIdentifier(prefix: String, names: [String]) -> String {
        let tokens = names.map { name in
            String(name.filter { $0.isLetter || $0.isNumber })
        }.sorted()
        return ([prefix] + tokens).joined(separator: "_")
    }

    // Cancel is excluded because it appears in every list and is never remembered. pasteAsText is
    // excluded because it is purely additive: it does not change what the other buttons mean, so a
    // text file and a binary file should share one memory. A saved pasteAsText simply fails to
    // resolve for a binary file and the dialog asks again, which is correct.
    static func fileWarningIdentifier(for actions: [FilePasteAction]) -> String {
        return warningIdentifier(prefix: "NoSyncPasteNonTextFile",
                                 names: actions.filter { $0 != .cancel && $0 != .pasteAsText }.map { $0.rawValue })
    }

    static func imageWarningIdentifier(for actions: [ImagePasteAction]) -> String {
        return warningIdentifier(prefix: "NoSyncPasteImage",
                                 names: actions.filter { $0 != .cancel }.map { $0.rawValue })
    }

    typealias FilePasteDestination = iTermNonTextPasteDestination

    // The buttons to offer for a file paste. Order is display order; each action carries its own
    // stable selection, so a remembered choice does not depend on where its button landed.
    static func fileActions(singleFile: Bool,
                            destination: FilePasteDestination,
                            isDirectory: Bool,
                            canPasteAsText: Bool) -> [FilePasteAction] {
        var actions = [FilePasteAction]()
        // The local path, offered as the default locally and after the uploads when remoteness is
        // only a guess, so Return still uploads on a host that really is remote.
        let offerLocalPath = (destination != .verifiedRemote)
        let canUpload = destination.canUpload
        if singleFile {
            // Naming the file. This is the only part that depends on where the session is
            // connected: a local path means nothing on the far host, so offer to put the file
            // there instead of naming it.
            if canUpload {
                if !isDirectory {
                    actions.append(.uploadAndPastePath)
                }
                actions.append(.upload)
            }
            if offerLocalPath {
                actions.append(.pastePath)
            }
            // Sending the file's own bytes inline. These type into the tty, so they work the
            // same whether the far end is local or remote, and are offered either way.
            if isDirectory {
                actions.append(.pasteBase64Archive)
            } else {
                actions.append(.pasteBase64)
                if canPasteAsText {
                    actions.append(.pasteAsText)
                }
            }
        } else {
            // Multiple files, following the same rule as one: the local paths mean nothing on the
            // far host, so offer to put the files there and name them by where they landed.
            if canUpload {
                actions.append(.uploadAndPastePaths)
                actions.append(.upload)
            }
            if offerLocalPath {
                actions.append(.pastePaths)
            }
        }
        actions.append(.cancel)
        return actions
    }

    private func handleFilePaste(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            return false
        }

        // Verify files exist
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if existingPaths.isEmpty {
            showError("The copied file no longer exists.")
            return true
        }
        if existingPaths.count < paths.count {
            let missing = paths.count - existingPaths.count
            // Single-count plural so the one count drives both agreements (file/files and
            // exists/exist); a two-count "N of M" phrasing would need a two-variable substitution.
            showError("\(missing) dropped files no longer exist and will be skipped.")
        }

        let singleFile = existingPaths.count == 1
        let destination = delegate?.nonTextPasteHelperDestination(self) ?? .local
        let isDirectory = singleFile && isDirectoryPath(existingPaths.first!)
        let canPasteAsText = singleFile && !isDirectory && firstFileIsValidUTF8(existingPaths)

        RLog("handleFilePaste: singleFile=\(singleFile) destination=\(destination) isDirectory=\(isDirectory) canPasteAsText=\(canPasteAsText)")

        let actions = Self.fileActions(singleFile: singleFile,
                                       destination: destination,
                                       isDirectory: isDirectory,
                                       canPasteAsText: canPasteAsText)
        DLog("handleFilePaste: actions=\(actions.map { $0.rawValue })")

        // Build description of files for the dialog
        let warning = iTermWarning()
        warning.title = pasteFilesPrompt(existingPaths, isDirectory: isDirectory)
        warning.actionLabels = actions.map { $0.displayName }
        warning.actionToSelectionMap = actions.map { NSNumber(value: $0.selection.rawValue) }
        warning.identifier = Self.fileWarningIdentifier(for: actions)
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        if isDirectory {
            warning.heading = "Paste Folder"
        } else if singleFile {
            warning.heading = "Paste File"
        } else {
            warning.heading = "Paste Files"
        }
        warning.cancelLabel = FilePasteAction.cancel.displayName
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleFilePaste: self was deallocated")
                return
            }
            guard let action = actions.first(where: { $0.selection == selection }) else {
                RLog("handleFilePaste: selection \(selection.rawValue) matches no offered action")
                return
            }
            RLog("handleFilePaste: user selected \(action.rawValue)")

            switch action {
            case .pastePath:
                DLog("handleFilePaste: pastePath")
                self.delegate?.nonTextPasteHelper(self, pasteString: Self.escapedPathForPaste(existingPaths.first!))
            case .pastePaths:
                DLog("handleFilePaste: pastePaths")
                let escapedPaths = existingPaths.map { Self.escapedPathForPaste($0) }.joined(separator: " ")
                self.delegate?.nonTextPasteHelper(self, pasteString: escapedPaths)
            case .pasteBase64:
                DLog("handleFilePaste: pasteBase64")
                self.pasteBase64EncodedContents(of: existingPaths.first!)
            case .pasteBase64Archive:
                DLog("handleFilePaste: pasteBase64Archive")
                self.pasteBase64EncodedArchive(of: existingPaths.first!)
            case .pasteAsText:
                DLog("handleFilePaste: pasteAsText")
                self.pasteFileAsText(existingPaths.first!)
            case .upload:
                DLog("handleFilePaste: upload")
                self.delegate?.nonTextPasteHelper(self, uploadFiles: existingPaths)
            case .uploadAndPastePath:
                DLog("handleFilePaste: uploadAndPastePath")
                self.delegate?.nonTextPasteHelper(self, uploadFileAndPastePath: existingPaths.first!)
            case .uploadAndPastePaths:
                DLog("handleFilePaste: uploadAndPastePaths")
                self.delegate?.nonTextPasteHelper(self, uploadFilesAndPastePaths: existingPaths)
            case .cancel:
                DLog("handleFilePaste: cancelled")
                break
            }
        }
        return true
    }

    // A complete localized prompt per case rather than injecting a partly-localized description into
    // a frame. File names are self-contained values and are interpolated; the many-files case varies
    // by plural on the count (String Catalog Vary-by-Plural; see CLAUDE.md).
    private func pasteFilesPrompt(_ paths: [String], isDirectory: Bool) -> String {
        if paths.count == 1 {
            let filename = (paths.first! as NSString).lastPathComponent
            if isDirectory {
                return "How would you like to paste the folder \u{201C}\(filename)\u{201D}?"
            }
            return "How would you like to paste the file \u{201C}\(filename)\u{201D}?"
        } else if paths.count <= 3 {
            let joined = paths.map { "\u{201C}\(($0 as NSString).lastPathComponent)\u{201D}" }.joined(separator: ", ")
            return "How would you like to paste \(joined)?"
        } else {
            return "How would you like to paste these \(paths.count) files?"
        }
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Paste Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = delegate?.nonTextPasteHelperWindow(self) {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // Raw values are stable identity (logging and cancel-label matching); text comes from displayName.
    enum ImagePasteAction: String {
        case saveTempAndPastePath = "Save to Temp File and Paste Path"
        case pasteBase64 = "Paste Base64-Encoded Contents"
        case upload = "Upload"
        case uploadAndPastePath = "Upload and Paste Path"
        case cancel = "Cancel"

        var displayName: String {
            switch self {
            case .saveTempAndPastePath: return "Save to Temp File and Paste Path"
            case .pasteBase64: return "Paste Base64-Encoded Contents"
            case .upload: return "Upload"
            case .uploadAndPastePath: return "Upload and Paste Path"
            case .cancel: return "Cancel"
            }
        }

        // Stable per-action selections, for the reason given on FilePasteAction.selection: this
        // list also varies, by whether the image type is known and whether we can upload.
        var selection: iTermWarningSelection {
            switch self {
            case .saveTempAndPastePath: return .kiTermWarningSelection0
            case .pasteBase64: return .kiTermWarningSelection1
            case .upload: return .kiTermWarningSelection2
            case .uploadAndPastePath: return .kiTermWarningSelection3
            case .cancel: return .kiTermWarningSelection4
            }
        }
    }

    // The buttons to offer for an image paste, based on where the session is and whether we know
    // the file type. As with fileActions, order is display order only. Saving to a local temp file
    // follows fileActions' Paste Path: the default locally, offered after the uploads when
    // remoteness is only a guess, and absent on a host proven remote.
    static func imageActions(hasFileExtension: Bool,
                             destination: iTermNonTextPasteDestination) -> [ImagePasteAction] {
        var actions = [ImagePasteAction]()
        if hasFileExtension {
            if destination.canUpload {
                actions.append(.uploadAndPastePath)
                actions.append(.upload)
            }
            if destination != .verifiedRemote {
                actions.append(.saveTempAndPastePath)
            }
        }
        actions.append(.pasteBase64)
        actions.append(.cancel)
        return actions
    }

    private func handleImageDataPaste(imageData: Data, fileExtension: String?) -> Bool {
        DLog("handleImageDataPaste: \(imageData.count) bytes, extension=\(fileExtension ?? "nil")")
        let destination = delegate?.nonTextPasteHelperDestination(self) ?? .local
        let sizeDescription = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)

        DLog("handleImageDataPaste: destination=\(destination)")

        let actions = Self.imageActions(hasFileExtension: fileExtension != nil, destination: destination)
        DLog("handleImageDataPaste: actions=\(actions.map { $0.rawValue })")

        let warning = iTermWarning()
        warning.title = imageDataPrompt(fileExtension: fileExtension, size: sizeDescription)
        warning.actionLabels = actions.map { $0.displayName }
        warning.actionToSelectionMap = actions.map { NSNumber(value: $0.selection.rawValue) }
        warning.identifier = Self.imageWarningIdentifier(for: actions)
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = "Paste Image"
        warning.cancelLabel = ImagePasteAction.cancel.displayName
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else {
                DLog("handleImageDataPaste: self was deallocated")
                return
            }
            guard let action = actions.first(where: { $0.selection == selection }) else {
                RLog("handleImageDataPaste: selection \(selection.rawValue) matches no offered action")
                return
            }
            RLog("handleImageDataPaste: user selected \(action.rawValue)")

            switch action {
            case .saveTempAndPastePath:
                DLog("handleImageDataPaste: saveTempAndPastePath")
                self.saveTempFileAndPastePath(imageData: imageData, fileExtension: fileExtension!)
            case .pasteBase64:
                DLog("handleImageDataPaste: pasteBase64")
                let base64 = (imageData as NSData).stringWithBase64Encoding(withLineBreak: "\r")
                self.pasteBase64WithConfirmationIfNeeded(base64)
            case .upload:
                DLog("handleImageDataPaste: upload")
                self.uploadImageData(imageData, fileExtension: fileExtension!, pastePath: false)
            case .uploadAndPastePath:
                DLog("handleImageDataPaste: uploadAndPastePath")
                self.uploadImageData(imageData, fileExtension: fileExtension!, pastePath: true)
            case .cancel:
                DLog("handleImageDataPaste: cancelled")
                break
            }
        }
        return true
    }

    private func uploadImageData(_ imageData: Data, fileExtension: String, pastePath: Bool) {
        DLog("uploadImageData: \(imageData.count) bytes, extension=\(fileExtension), pastePath=\(pastePath)")
        guard let tempPath = saveImageToTempFile(imageData: imageData, fileExtension: fileExtension) else {
            RLog("uploadImageData: failed to save temp file")
            return
        }
        if pastePath {
            DLog("uploadImageData: calling delegate uploadFileAndPastePath")
            delegate?.nonTextPasteHelper(self, uploadFileAndPastePath: tempPath)
        } else {
            DLog("uploadImageData: calling delegate uploadFiles")
            delegate?.nonTextPasteHelper(self, uploadFiles: [tempPath])
        }
    }

    private func saveImageToTempFile(imageData: Data, fileExtension: String) -> String? {
        DLog("saveImageToTempFile: \(imageData.count) bytes, extension=\(fileExtension)")
        // Screenshots often offer TIFF. Agent image readers commonly accept PNG/JPEG,
        // so convert other bitmap formats before handing them a filename.
        guard let image = Self.imageForFile(imageData, fileExtension: fileExtension) else {
            showError("Could not convert the clipboard image to PNG.")
            return nil
        }
        guard let tempDir = FileManager.default.it_temporaryDirectory() else {
            RLog("saveImageToTempFile: failed to get temporary directory")
            showError("Could not create temporary directory.")
            return nil
        }
        let timestamp = Self.timestampFormatter.string(from: Date())
        // The basename must also be unique on the remote host, where multiple local
        // temporary directories all upload to the same directory.
        let filename = "pasted-image-\(timestamp)-\(UUID().uuidString).\(image.fileExtension)"
        let tempPath = (tempDir as NSString).appendingPathComponent(filename)

        do {
            try image.data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempPath)
            DLog("saveImageToTempFile: saved to \(tempPath)")
            return tempPath
        } catch {
            try? FileManager.default.removeItem(atPath: tempDir)
            RLog("saveImageToTempFile: failed to write: \(error)")
            showError("Could not save image to temporary file: \(error.localizedDescription)")
            return nil
        }
    }

    static func imageForFile(_ data: Data, fileExtension: String) -> (data: Data, fileExtension: String)? {
        switch fileExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp":
            return (data, fileExtension.lowercased())
        default:
            guard let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            return (png, "png")
        }
    }

    // A complete localized prompt per image type rather than injecting an article+type fragment
    // ("a PNG", "an", "some") into a frame, whose grammar and word order differ by language. The
    // size is a self-contained value, so interpolating it is fine.
    private func imageDataPrompt(fileExtension: String?, size: String) -> String {
        switch fileExtension?.lowercased() {
        case "png": return "The clipboard contains a PNG image (\(size)). How would you like to paste it?"
        case "jpg", "jpeg": return "The clipboard contains a JPEG image (\(size)). How would you like to paste it?"
        case "gif": return "The clipboard contains a GIF image (\(size)). How would you like to paste it?"
        case "tiff", "tif": return "The clipboard contains a TIFF image (\(size)). How would you like to paste it?"
        case "bmp": return "The clipboard contains a BMP image (\(size)). How would you like to paste it?"
        case "webp": return "The clipboard contains a WebP image (\(size)). How would you like to paste it?"
        case "heic": return "The clipboard contains a HEIC image (\(size)). How would you like to paste it?"
        case nil: return "The clipboard contains image data (\(size)). How would you like to paste it?"
        default: return "The clipboard contains an image (\(size)). How would you like to paste it?"
        }
    }

    private func firstFileIsValidUTF8(_ paths: [String]) -> Bool {
        guard let firstPath = paths.first else {
            return false
        }
        return Self.prefixIsValidUTF8(ofFileAt: firstPath)
    }

    // How much of a file we look at to decide whether it is text. Reading the whole file
    // blocked the main thread for seconds on a large file or a slow disk (issue 13024),
    // and this decision only controls whether the “Paste as Text” button is offered. A
    // sample this small can be wrong about the rest of the file; pasteFileAsText handles
    // that by reporting the file as not being UTF-8 rather than pasting garbage.
    static let utf8SampleByteCount = 50 * 1024

    // Whether the first utf8SampleByteCount bytes of the file are valid UTF-8. If they
    // are, we assume the rest of the file is too rather than pay to read it.
    static func prefixIsValidUTF8(ofFileAt path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            DLog("prefixIsValidUTF8: could not open \(path)")
            return false
        }
        defer {
            try? handle.close()
        }
        let data: Data
        do {
            // One byte more than we intend to look at, so that filling the sample is
            // proof we cut the file short. Reading exactly utf8SampleByteCount cannot
            // tell a file of that exact size from a longer one.
            data = try handle.read(upToCount: utf8SampleByteCount + 1) ?? Data()
        } catch {
            DLog("prefixIsValidUTF8: read failed for \(path): \(error)")
            return false
        }
        // Only forgive a truncated sequence when we are the ones who truncated it. A file
        // that really ends mid-sequence is not valid UTF-8.
        let weTruncated = data.count > utf8SampleByteCount
        let sample = weTruncated ? trimmingPartialTrailingSequence(data.prefix(utf8SampleByteCount)) : data
        return String(data: sample, encoding: .utf8) != nil
    }

    // Drops a trailing UTF-8 sequence that the sample boundary cut in half, so that a
    // multi-byte scalar straddling the cut does not make a text file look like binary.
    static func trimmingPartialTrailingSequence(_ data: Data) -> Data {
        // A sequence is at most four bytes and a complete one needs no trimming, so the
        // lead byte of an interrupted sequence is within the last three bytes.
        let lowerBound = max(data.startIndex, data.endIndex - 3)
        var i = data.endIndex - 1
        while i >= lowerBound {
            let byte = data[i]
            if byte & 0b1100_0000 == 0b1000_0000 {
                // Continuation byte: its lead byte is further back.
                i -= 1
                continue
            }
            if byte & 0b1000_0000 == 0 {
                // ASCII scalar, so nothing was cut.
                return data
            }
            // Lead byte. Trim it and its continuations only if its sequence runs past the
            // end of what we read.
            if sequenceLength(leadByte: byte) > data.endIndex - i {
                return data.prefix(upTo: i)
            }
            return data
        }
        // Three trailing continuation bytes with no lead byte in reach: not valid UTF-8
        // however the file continues, so leave it for the validator to reject.
        return data
    }

    private static func sequenceLength(leadByte: UInt8) -> Int {
        if leadByte & 0b1110_0000 == 0b1100_0000 {
            return 2
        }
        if leadByte & 0b1111_0000 == 0b1110_0000 {
            return 3
        }
        if leadByte & 0b1111_1000 == 0b1111_0000 {
            return 4
        }
        // Not a lead byte at all, so there is nothing to wait for.
        return 1
    }

    // Escapes a path the same way the drag-and-drop path does, honoring the user’s
    // quoting preference: off (the default) gives backslash escaping, on wraps the whole
    // path in quotes. 3.7.0 always quoted, which changed behavior for everyone. Every
    // paste-a-path action goes through here, including the ones PTYSession runs after an
    // upload, so they cannot disagree about the preference.
    @objc(escapedPathForPaste:)
    static func escapedPathForPaste(_ path: String) -> String {
        let wrapInQuotes = iTermPreferences.bool(forKey: kPreferenceKeyWrapDroppedFilenamesInQuotesWhenPasting)
        return escapedPathForPaste(path, wrapInQuotes: wrapInQuotes)
    }

    static func escapedPathForPaste(_ path: String, wrapInQuotes: Bool) -> String {
        if wrapInQuotes {
            return path.quotedStringForPaste()
        }
        return path.withEscapedShellCharacters(includingNewlines: true)
    }

    private func pasteBase64EncodedContents(of path: String) {
        DLog("pasteBase64EncodedContents: \(path)")
        guard let data = FileManager.default.contents(atPath: path) else {
            RLog("pasteBase64EncodedContents: failed to read file")
            let filename = (path as NSString).lastPathComponent
            showError("Could not read file \u{201C}\(filename)\u{201D}.")
            return
        }
        DLog("pasteBase64EncodedContents: read \(data.count) bytes")
        let base64 = (data as NSData).stringWithBase64Encoding(withLineBreak: "\r")
        pasteBase64WithConfirmationIfNeeded(base64)
    }

    private func pasteBase64EncodedArchive(of folderPath: String) {
        DLog("pasteBase64EncodedArchive: \(folderPath)")
        let folderName = (folderPath as NSString).lastPathComponent
        let parentPath = (folderPath as NSString).deletingLastPathComponent

        do {
            // Create archive with just the folder name, relative to parent
            let data = try NSData(tgzContainingFiles: [folderName],
                                  relativeToPath: parentPath,
                                  includeExtendedAttrs: false)
            DLog("pasteBase64EncodedArchive: created archive of \(data.count) bytes")
            let base64 = data.stringWithBase64Encoding(withLineBreak: "\r")
            pasteBase64WithConfirmationIfNeeded(base64)
        } catch {
            RLog("pasteBase64EncodedArchive: failed to create archive: \(error)")
            showError("Could not create archive of \u{201C}\(folderName)\u{201D}: \(error.localizedDescription)")
        }
    }

    private func pasteBase64WithConfirmationIfNeeded(_ base64: String) {
        let threshold = 10_000
        if base64.count <= threshold {
            delegate?.nonTextPasteHelper(self, pasteString:base64)
            return
        }

        let warning = iTermWarning()
        // Varies by plural on the byte count (String Catalog Vary-by-Plural; see CLAUDE.md).
        warning.title = "OK to paste \(base64.count) bytes of base64-encoded data?"
        warning.actionLabels = ["OK", "Cancel"]
        warning.identifier = "NoSyncPasteLargeBase64"
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = "Large Paste"
        warning.cancelLabel = "Cancel"
        warning.window = delegate?.nonTextPasteHelperWindow(self)

        warning.runModalAsync { [weak self] selection, _ in
            guard let self = self else { return }
            if selection == .kiTermWarningSelection0 {
                self.delegate?.nonTextPasteHelper(self, pasteString: base64)
            }
        }
    }

    private func pasteFileAsText(_ path: String) {
        let filename = (path as NSString).lastPathComponent
        guard let data = FileManager.default.contents(atPath: path) else {
            showError("Could not read file \u{201C}\(filename)\u{201D}.")
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            showError("File \u{201C}\(filename)\u{201D} is not valid UTF-8 text.")
            return
        }
        delegate?.nonTextPasteHelper(self, pasteString: text)
    }

    private func saveTempFileAndPastePath(imageData: Data, fileExtension: String) {
        DLog("saveTempFileAndPastePath: \(imageData.count) bytes, extension=\(fileExtension)")
        guard let tempPath = saveImageToTempFile(imageData: imageData, fileExtension: fileExtension) else {
            DLog("saveTempFileAndPastePath: failed to save temp file")
            return
        }
        let escapedPath = Self.escapedPathForPaste(tempPath)
        DLog("saveTempFileAndPastePath: pasting path \(escapedPath)")
        delegate?.nonTextPasteHelper(self, pasteString: escapedPath)
    }
}
