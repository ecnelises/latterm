// Classify a complete line from a tmux control-mode connection.
import Foundation

@objc final class TmuxControlLineState: NSObject {
    private var recovering: Bool
    private var command: (id: String, number: String)?

    @objc(initRecovering:) init(recovering: Bool) { self.recovering = recovering }

    @objc(classify:serverMayOmitEndGuardBeforeExit:)
    func classify(_ line: String, serverMayOmitEndGuardBeforeExit: Bool) -> VT100TerminalTokenType {
        if recovering {
            recovering = false
            // Reattachment can start in the middle of a notification.
            if !line.hasPrefix("%begin") && !line.hasPrefix("%exit") { return VT100_WAIT }
        }

        if line.hasPrefix("%exit"), command == nil || serverMayOmitEndGuardBeforeExit {
            command = nil
            return TMUX_EXIT
        }
        if let current = command {
            if line.hasPrefix("%end ") || line.hasPrefix("%error ") {
                let fields = line.components(separatedBy: " ")
                if fields.count >= 3 && fields[1] == current.id && fields[2] == current.number { command = nil }
            }
        } else if line.hasPrefix("%begin") {
            let fields = line.components(separatedBy: " ")
            if fields.count >= 3 { command = (fields[1], fields[2]) }
        }
        return TMUX_LINE
    }
}
