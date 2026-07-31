//
//  WorkgroupSessionState.swift
//  iTerm2
//

import Foundation

@MainActor
enum WorkgroupSessionState {
    static func state(for session: PTYSession) -> SessionState {
        guard let status = session.tabStatus else {
            return .unknown
        }
        return state(forTabStatus: status)
    }

    static func state(forTabStatus status: iTermSessionTabStatus) -> SessionState {
        if let text = status.statusText?.lowercased(), !text.isEmpty {
            switch text {
            case "idle":
                return .idle
            case "working":
                return .working
            case "waiting":
                return .waiting
            default:
                break
            }
        }
        return status.hasIndicator ? .working : .idle
    }

    static func reportedState(forTabStatus status: iTermSessionTabStatus) -> SessionState {
        guard let text = status.statusText?.lowercased(), !text.isEmpty else {
            return .unknown
        }
        switch text {
        case "idle":
            return .idle
        case "working":
            return .working
        case "waiting":
            return .waiting
        default:
            return .unknown
        }
    }
}
