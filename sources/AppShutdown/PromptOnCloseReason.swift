// Close confirmation shared by panes, tabs, windows and application termination.
import Foundation

@objc(iTermPromptOnCloseReason)
final class PromptOnCloseReason: NSObject {
    private enum Group {
        case profileJobs, profileAlways, message

        var footer: String? {
            switch self {
            case .profileJobs, .profileAlways: return "You can change this setting in Settings > Profiles > Session"
            case .message: return nil
            }
        }
    }

    private struct Entry {
        let message: String
        let priority: Int
        let group: Group
    }

    private var entries: [Entry]
    private let compound: Bool

    @objc(noReason)
    static func none() -> PromptOnCloseReason { PromptOnCloseReason() }

    private override init() {
        entries = []
        compound = true
        super.init()
    }

    private init(_ message: String, priority: Int, group: Group = .message) {
        entries = [Entry(message: message, priority: priority, group: group)]
        compound = false
        super.init()
    }

    @objc var hasReason: Bool { !entries.isEmpty }

    @objc(addReason:)
    func add(_ reason: PromptOnCloseReason) {
        it_assert(compound)
        entries.append(contentsOf: reason.entries)
    }

    @objc var message: String {
        if !compound { return entries[0].message }
        var lines: [String] = []
        var previous: Entry?
        for entry in entries.sorted(by: { $0.priority < $1.priority }) {
            guard entry.message != previous?.message else { continue }
            if let previous, previous.group != entry.group, let footer = previous.group.footer {
                lines.append(contentsOf: [footer, ""])
            }
            lines.append("• " + entry.message)
            previous = entry
        }
        if let footer = previous?.group.footer { lines.append(footer) }
        return lines.joined(separator: "\n")
    }

    private static var applicationName: String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = Bundle.main.object(forInfoDictionaryKey: key) as? String, !name.isEmpty { return name }
        }
        return "Latterm"
    }

    @objc(alwaysConfirmQuitPreferenceEnabled)
    static func confirmQuit() -> PromptOnCloseReason {
        let format = NSLocalizedString("“Settings > General > Closing > Confirm Quit %@” is enabled and there is at least one terminal window.",
                                       comment: "Prompt-on-quit reason when confirm-quit is enabled")
        return PromptOnCloseReason(String(format: format, applicationName), priority: 100)
    }

    @objc(alwaysConfirmQuitPreferenceEvenIfThereAreNoWindowsEnabled)
    static func confirmQuitWithoutWindows() -> PromptOnCloseReason {
        let format = NSLocalizedString("“Settings > General > Closing > Confirm Quit %@” and “Even if there are no windows” is enabled.",
                                       comment: "Prompt-on-quit reason when confirm-quit-without-windows is enabled")
        return PromptOnCloseReason(String(format: format, applicationName), priority: 100)
    }

    @objc(closingMultipleSessionsPreferenceEnabled)
    static func multipleSessions() -> PromptOnCloseReason {
        PromptOnCloseReason("“Settings > General > Closing > Confirm closing multiple sessions” is enabled.", priority: 90)
    }

    @objc(profileAlwaysPrompts:)
    static func profileAlwaysPrompts(_ profile: [AnyHashable: Any]?) -> PromptOnCloseReason {
        let name = profile?[KEY_NAME] as? String ?? "(null)"
        return PromptOnCloseReason("The profile “\(name)” always requires confirmation.", priority: 50, group: .profileAlways)
    }

    @objc(profile:blockedByJobs:)
    static func profile(_ profile: [AnyHashable: Any]?, blockedByJobs jobs: [String]) -> PromptOnCloseReason {
        let profileName = profile?[KEY_NAME] as? String ?? "(null)"
        let description: String
        if jobs.count > 3 {
            let count = jobs.count - 3
            description = jobs.prefix(3).joined(separator: ", ") + ", and \(count) other " + (count == 1 ? "job" : "jobs")
        } else {
            description = (jobs as NSArray).componentsJoinedWithOxfordComma()
        }
        return PromptOnCloseReason("A session with profile “\(profileName)” is running \(description).",
                                   priority: 25, group: .profileJobs)
    }

    @objc(tmuxClientsAlwaysPromptBecauseJobsAreNotExposed)
    static func tmuxJobs() -> PromptOnCloseReason {
        PromptOnCloseReason("A tmux session is configured to prompt if jobs are running, but tmux doesn’t expose the process tree.", priority: 80)
    }

    @objc static func sessionIsLocked() -> PromptOnCloseReason {
        PromptOnCloseReason("This pane is locked.", priority: 75)
    }

    @objc(tabIsPinnedWithNumber:)
    static func pinnedTab(_ number: Int32) -> PromptOnCloseReason {
        PromptOnCloseReason("Tab #\(number) is pinned.", priority: 70)
    }
}

extension PTYSession {
    @objc var promptOnCloseReason: PromptOnCloseReason {
        if exited { return .none() }
        if locked { return .sessionIsLocked() }
        let value = profile?[KEY_PROMPT_CLOSE]
        let setting = (value as? NSNumber)?.int32Value ?? (value as? NSString)?.intValue ?? 0
        switch setting {
        case PROMPT_NEVER: return .none()
        case PROMPT_EX_JOBS:
            if isTmuxClient { return .tmuxJobs() }
            guard let ignored = profile?[KEY_JOBS] as? [Any] else { return .none() }
            let ignoredNames = Set(ignored.compactMap { $0 as? String })
            let jobs = childJobNameTuples.compactMap { job -> String? in
                guard let name = job.firstObject as String?, let path = job.secondObject as String?,
                      !ignoredNames.contains(name), !ignoredNames.contains(path) else { return nil }
                return (path as NSString).lastPathComponent
            }
            return jobs.isEmpty ? .none() : .profile(profile, blockedByJobs: jobs)
        default: return .profileAlwaysPrompts(profile)
        }
    }
}

extension PTYTab {
    @objc var promptOnCloseReason: PromptOnCloseReason {
        let reason = PromptOnCloseReason.none()
        for session in sessions() ?? [] { reason.add(session.promptOnCloseReason) }
        return reason
    }
}

extension PseudoTerminal {
    @objc var promptOnCloseReason: PromptOnCloseReason {
        let reason = PromptOnCloseReason.none()
        for session in allSessions() ?? [] { reason.add(session.promptOnCloseReason) }
        for tab in tabs() ?? [] where tab.isPinned { reason.add(.pinnedTab(tab.tabNumber())) }
        return reason
    }
}
