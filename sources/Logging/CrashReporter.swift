import AppKit
import UniformTypeIdentifiers

struct CrashReport {
    let url: URL
    let date: Date
    let text: String

    // Older versions appended error logs to Apple's two-object IPS format.
    // Read that format without ever modifying the original diagnostic file.
    static func details(in text: String) -> [String: Any]? {
        let diagnostic = text.components(separatedBy: "~~ Error Logs ~~").first ?? text
        guard let newline = diagnostic.firstIndex(of: "\n") else { return nil }
        let body = String(diagnostic[diagnostic.index(after: newline)...])
        return (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
    }

    static func belongsToApplication(_ text: String, executablePath: String) -> Bool {
        guard let details = details(in: text) else { return false }
        let images = details["usedImages"] as? [[String: Any]] ?? []
        if images.contains(where: { ($0["path"] as? String)?.contains(".xctest/") == true }) {
            return false
        }
        guard let processPath = details["procPath"] as? String else { return false }
        // macOS redacts the account name in diagnostic reports.
        func normalized(_ path: String) -> String {
            path.replacingOccurrences(of: #"^/Users/[^/]+/"#,
                                      with: "/Users/USER/",
                                      options: .regularExpression)
        }
        return normalized(processPath) == normalized(executablePath)
    }

    static func latest(in folders: [URL], executablePath: String, after date: Date) -> CrashReport? {
        let manager = FileManager.default
        let prefix = URL(fileURLWithPath: executablePath).lastPathComponent + "-"
        let candidates = folders.flatMap {
            (try? manager.contentsOfDirectory(at: $0,
                                              includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles])) ?? []
        }.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "ips" }
        var latest: CrashReport?
        for url in candidates {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified > date,
                  modified > (latest?.date ?? .distantPast),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  belongsToApplication(text, executablePath: executablePath) else { continue }
            latest = CrashReport(url: url, date: modified, text: text)
        }
        return latest
    }

    func exportText(errorLogDirectory: URL?) -> String {
        guard !text.contains("~~ Error Logs ~~"), let directory = errorLogDirectory else { return text }
        let logs = (0..<3).compactMap { index -> String? in
            let url = directory.appendingPathComponent("log.\(index).txt")
            guard let log = try? String(contentsOf: url, encoding: .utf8), !log.isEmpty else { return nil }
            return "\n--- \(url.lastPathComponent) ---\n\(log)"
        }
        return logs.isEmpty ? text : text + "\n~~ Error Logs ~~\n" + logs.joined()
    }
}

@objc(iTermCrashReporter)
final class CrashReporter: NSObject {
    static let reportRecipient = "fwage73@gmail.com"
    static let lastReportKey = "NoSyncCrashReporterLastReportDate"
    private static var activeController: CrashReportWindowController?

    @objc static func checkForCrash() {
        guard NSClassFromString("XCTestCase") == nil,
              activeController == nil,
              let executablePath = Bundle.main.executablePath else { return }
        let defaults = iTermUserDefaults.userDefaults()
        let interval = defaults.object(forKey: lastReportKey) != nil
            ? defaults.double(forKey: lastReportKey)
            : defaults.double(forKey: "UKCrashReporterLastCrashReportDate")
        let after = Date(timeIntervalSince1970: interval)
        let folders = [FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")]
        let logDirectory = FileManager.default.applicationSupportDirectory().map { URL(fileURLWithPath: $0) }
        DispatchQueue.global(qos: .utility).async {
            guard let report = CrashReport.latest(in: folders, executablePath: executablePath, after: after) else {
                return
            }
            let text = report.exportText(errorLogDirectory: logDirectory)
            DispatchQueue.main.async {
                guard activeController == nil else { return }
                DLog("Showing crash report \(report.url.lastPathComponent)")
                let controller = CrashReportWindowController(report: report, text: text) {
                    defaults.set(report.date.timeIntervalSince1970, forKey: lastReportKey)
                    activeController = nil
                }
                activeController = controller
                controller.showWindow(nil)
            }
        }
    }
}

private final class CrashReportWindow: NSWindow {
    @objc func closeCurrentSession(_ sender: Any?) {
        performClose(sender)
    }
}

final class CrashReportWindowController: NSWindowController, NSWindowDelegate, NSSharingServiceDelegate {
    let report: CrashReport
    let reportText: String
    let recipient: String
    private let onDismiss: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private var mailService: NSSharingService?

    init(report: CrashReport, text: String, recipient: String = CrashReporter.reportRecipient, onDismiss: @escaping () -> Void) {
        self.report = report
        self.reportText = text
        self.recipient = recipient
        self.onDismiss = onDismiss
        let window = CrashReportWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Latterm Crash Report"
        window.minSize = NSSize(width: 700, height: 440)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) {
        it_fatalError("Crash report windows are created programmatically")
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let heading = NSTextField(labelWithString: "Latterm quit unexpectedly")
        heading.font = .boldSystemFont(ofSize: 16)
        heading.frame = NSRect(x: 20, y: 516, width: 740, height: 24)
        heading.autoresizingMask = [.width, .minYMargin]
        content.addSubview(heading)

        let explanation = NSTextField(labelWithString: "Review the log, then copy it, export it, or create an email draft.")
        explanation.frame = NSRect(x: 20, y: 488, width: 740, height: 22)
        explanation.autoresizingMask = [.width, .minYMargin]
        content.addSubview(explanation)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 94, width: 740, height: 380))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let textView = NSTextView(frame: scroll.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = reportText
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        content.addSubview(scroll)

        statusLabel.stringValue = "Email drafts are addressed to \(recipient)."
        statusLabel.frame = NSRect(x: 20, y: 62, width: 740, height: 20)
        statusLabel.autoresizingMask = [.width]
        statusLabel.lineBreakMode = .byTruncatingMiddle
        content.addSubview(statusLabel)

        let buttons: [(String, Selector, CGFloat, CGFloat)] = [
            ("Copy Log", #selector(copyReport), 20, 110),
            ("Export…", #selector(exportReport), 140, 110),
            ("Email Draft…", #selector(createEmailDraft), 260, 140),
            ("Dismiss", #selector(dismissReport), 650, 110)
        ]
        for (title, action, x, width) in buttons {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 20, width: width, height: 32)
            if action == #selector(dismissReport) {
                button.autoresizingMask = [.minXMargin]
                button.keyEquivalent = "\r"
            }
            content.addSubview(button)
        }
    }

    func copyLog(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(reportText, forType: .string)
    }

    func exportLog(to url: URL) throws {
        try reportText.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func copyReport() {
        copyLog(to: .general)
        statusLabel.stringValue = "Log copied."
    }

    @objc private func exportReport() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = report.url.deletingPathExtension().lastPathComponent + ".txt"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.exportLog(to: url)
                self.statusLabel.stringValue = "Log exported."
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func createEmailDraft() {
        guard let service = NSSharingService(named: .composeEmail) else {
            statusLabel.stringValue = "Email is unavailable. Copy or export the log instead."
            return
        }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Latterm-CrashReport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let attachment = directory.appendingPathComponent("Latterm-CrashReport.txt")
            try exportLog(to: attachment)
            let items: [Any] = ["Please describe what happened before the crash.\n\n", attachment]
            guard service.canPerform(withItems: items) else {
                statusLabel.stringValue = "Email is unavailable. Copy or export the log instead."
                return
            }
            service.recipients = [recipient]
            service.subject = "Latterm crash report"
            service.delegate = self
            mailService = service
            service.perform(withItems: items)
            statusLabel.stringValue = "Review and send the draft in your email app."
        } catch {
            showError(error)
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        showError(error)
        mailService = nil
    }

    private func showError(_ error: Error) {
        guard let window else { return }
        DLog("Crash report operation failed: \(error)")
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window)
    }

    @objc private func dismissReport() {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss()
    }
}
