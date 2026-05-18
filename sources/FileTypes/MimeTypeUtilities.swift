//
//  MimeTypeUtilities.swift
//  iTerm2
//
//  Created by George Nachman on 6/26/25.
//

import Foundation
import UniformTypeIdentifiers

class MimeTypeUtilities {
    static func extensionForMimeType(_ mimeType: String) -> String {
        let cleanMimeType = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mimeType
        if let fileExtension = UTType(mimeType: cleanMimeType)?.preferredFilenameExtension {
            return fileExtension
        }
        
        switch cleanMimeType.lowercased() {
        case let mime where mime.hasPrefix("image/"):
            return "img"
        case let mime where mime.hasPrefix("video/"):
            return "vid"
        case let mime where mime.hasPrefix("audio/"):
            return "aud"
        case let mime where mime.hasPrefix("text/"):
            return "txt"
        case let mime where mime.hasPrefix("application/"):
            return "bin"
        default:
            return "dat"
        }
    }
}
