//
//  iTermHostnameFinder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/14/24.
//

import Darwin
import Foundation

class iTermHostnameFinder: SSHHostnameFinder {
    private let configPathsOverride: [String]?

    init(configPaths: [String]? = nil) {
        self.configPathsOverride = configPaths
    }

    func sshHostname(forHost host: String) -> String {
        guard !host.isEmpty else {
            return host
        }
        var visited = Set<String>()
        for path in effectiveConfigPaths() {
            if let resolved = Self.resolveHostname(forHost: host,
                                                   inConfigFile: path,
                                                   visited: &visited) {
                return Self.expandHostnameTokens(resolved, originalHost: host)
            }
        }
        return host
    }

    private func effectiveConfigPaths() -> [String] {
        if let configPathsOverride {
            return configPathsOverride
        }
        let fm = FileManager.default
        var paths = [String]()
        if let appSupport = fm.applicationSupportDirectory(), !appSupport.isEmpty {
            paths.append((appSupport as NSString).appendingPathComponent("ssh_config"))
        }
        paths.append(("~/.ssh/config" as NSString).expandingTildeInPath)
        paths.append("/etc/ssh/ssh_config")
        paths.append("/etc/ssh_config")
        return paths
    }

    private static func resolveHostname(forHost host: String,
                                        inConfigFile path: String,
                                        visited: inout Set<String>) -> String? {
        let canonical = (path as NSString).resolvingSymlinksInPath
        guard !visited.contains(canonical),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        visited.insert(canonical)

        let isSystemConfig = path.hasPrefix("/etc/")
        var activeBlockMatches = true

        for rawLine in content.components(separatedBy: .newlines) {
            let tokens = tokenizeConfigLine(rawLine)
            guard let keyword = tokens.first?.lowercased(), tokens.count >= 2 else {
                continue
            }
            let args = Array(tokens.dropFirst())

            switch keyword {
            case "host":
                activeBlockMatches = hostMatchesPatterns(host: host, patterns: args)
            case "match":
                // Unsupported conditional blocks (`Match exec`, etc.) do not statically match.
                activeBlockMatches = args.count == 1 && args[0].lowercased() == "all"
            case "include":
                guard activeBlockMatches else {
                    continue
                }
                for pattern in args {
                    for includedPath in expandIncludePattern(pattern, isSystemConfig: isSystemConfig) {
                        if let found = resolveHostname(forHost: host,
                                                       inConfigFile: includedPath,
                                                       visited: &visited) {
                            return found
                        }
                    }
                }
            case "hostname":
                if activeBlockMatches, let target = args.first, !target.isEmpty {
                    return target
                }
            default:
                break
            }
        }
        return nil
    }

    static func tokenizeConfigLine(_ line: String) -> [String] {
        var tokens = [String]()
        var current = ""
        var inQuotes = false
        var sawEqualsForFirstToken = false

        for ch in line {
            if ch == "#" && !inQuotes && current.isEmpty {
                break
            }
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if !inQuotes {
                if ch.isWhitespace {
                    if !current.isEmpty {
                        tokens.append(current)
                        current.removeAll(keepingCapacity: true)
                    }
                    continue
                }
                if ch == "=" && tokens.isEmpty && !sawEqualsForFirstToken && !current.isEmpty {
                    sawEqualsForFirstToken = true
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                    continue
                }
            }
            current.append(ch)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    static func hostMatchesPatterns(host: String, patterns: [String]) -> Bool {
        var matchedPositive = false
        for rawPattern in patterns {
            for item in rawPattern.split(separator: ",").map(String.init) where !item.isEmpty {
                if item.hasPrefix("!") {
                    let neg = String(item.dropFirst())
                    if !neg.isEmpty && fnmatchMatches(pattern: neg, string: host) {
                        return false
                    }
                } else if fnmatchMatches(pattern: item, string: host) {
                    matchedPositive = true
                }
            }
        }
        return matchedPositive
    }

    private static func fnmatchMatches(pattern: String, string: String) -> Bool {
        return pattern.withCString { patPtr in
            string.withCString { strPtr in
                Darwin.fnmatch(patPtr, strPtr, 0) == 0
            }
        }
    }

    private static func expandIncludePattern(_ pattern: String, isSystemConfig: Bool) -> [String] {
        let expanded: String
        if pattern.hasPrefix("~/") || pattern == "~" {
            expanded = (pattern as NSString).expandingTildeInPath
        } else if pattern.hasPrefix("/") {
            expanded = pattern
        } else if isSystemConfig {
            expanded = ("/etc/ssh" as NSString).appendingPathComponent(pattern)
        } else {
            expanded = (("~/.ssh" as NSString).expandingTildeInPath as NSString).appendingPathComponent(pattern)
        }

        var globResult = glob_t()
        defer { globfree(&globResult) }
        let rc = expanded.withCString { ptr in
            Darwin.glob(ptr, 0, nil, &globResult)
        }
        guard rc == 0, globResult.gl_matchc > 0, let pathv = globResult.gl_pathv else {
            return []
        }
        var results = [String]()
        for i in 0..<Int(globResult.gl_matchc) {
            if let cStr = pathv[i] {
                results.append(String(cString: cStr))
            }
        }
        return results.sorted()
    }

    static func expandHostnameTokens(_ value: String, originalHost: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            if ch == "%", let next = iterator.next() {
                switch next {
                case "%":
                    result.append("%")
                case "h":
                    result.append(originalHost)
                default:
                    result.append("%")
                    result.append(next)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
