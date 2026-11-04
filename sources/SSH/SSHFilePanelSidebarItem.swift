//
//  SSHFilePanelSidebarItem.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

/// Sidebar item for the source list
@available(macOS 11, *)
enum SSHFilePanelSidebarItem: Equatable, Hashable {
    case host(RemoteHostStatus)
    case favorite(RemoteFavorite)
    case separator

    /// Represents connection status and metadata for an SSH host
    struct RemoteHostStatus: Equatable, Hashable {
        let identity: SSHIdentity
        let isConnected: Bool
        let lastConnected: Date?

        /// Display name with connection status
        var displayName: String {
            let status = isConnected ? "●" : "○"
            return "\(status) \(identity.compactDescription)"
        }
    }

    /// Favorited item in the panel
    struct RemoteFavorite: Equatable, Hashable, Identifiable {
        let id: UUID
        let path: String
        let identity: SSHIdentity
        let dateAdded: Date
        let sortOrder: Int

        var displayName: String {
            return (path as NSString).lastPathComponent.isEmpty ? "/" : (path as NSString).lastPathComponent
        }
    }

    var id: String {
        switch self {
        case .host(let hostStatus):
            return "host-\(hostStatus.identity.stringIdentifier)"
        case .favorite(let favorite):
            return "favorite-\(favorite.id)"
        case .separator:
            return "separator"
        }
    }

    var title: String {
        switch self {
        case .host(let hostStatus):
            return hostStatus.displayName
        case .favorite(let favorite):
            return favorite.displayName
        case .separator:
            return ""
        }
    }

    var icon: NSImage? {
        switch self {
        case .host(let hostStatus):
            return hostStatus.isConnected ?
                NSImage(systemSymbolName: SFSymbol.desktopcomputer.rawValue,
                        accessibilityDescription: "Connected host") :
                NSImage(systemSymbolName: SFSymbol.desktopcomputerTrianglebadgeExclamationmark.rawValue,
                        accessibilityDescription: "Disconnected host")
        case .favorite:
            return NSImage(systemSymbolName: SFSymbol.starFill.rawValue,
                           accessibilityDescription: "Star")
        case .separator:
            return nil
        }
    }
}

