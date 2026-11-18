//
//  SessionState.swift
//  iTerm2
//

import Foundation

enum SessionState: String, Codable {
    case idle
    case working
    case waiting
    case unknown
}
