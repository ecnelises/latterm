//
//  SessionState.swift
//  iTerm2
//
//  Shared with Companion. Keep this file platform-neutral.
//

import Foundation

enum SessionState: String, Codable {
    case idle
    case working
    case waiting
    case unknown
}
