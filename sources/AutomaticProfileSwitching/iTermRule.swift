//
//  iTermRule.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/14.
//

import Foundation

/// Parses and scores an automatic profile switching rule such as `user@host:/path&job` or `{expr}`.
@objc(iTermRule)
class iTermRule: NSObject {
    @objc private(set) var username: String?
    @objc private(set) var hostname: String?
    @objc private(set) var path: String?
    @objc private(set) var job: String?
    @objc private(set) var expression: String?
    @objc private(set) var isSticky: Bool = false

    private override init() {
        super.init()
    }

    /// Parses a rule string into its components, or returns `nil` if invalid.
    @objc(initWithString:)
    convenience init?(string: String) {
        self.init()
        var remaining = string

        // Check for sticky prefix first (before checking for expression syntax).
        if remaining.hasPrefix("!") {
            isSticky = true
            remaining = String(remaining.dropFirst())
        }

        // Now check for expression syntax.
        if remaining.hasPrefix("{") && remaining.hasSuffix("}") {
            expression = String(remaining.dropFirst().dropLast())
            return
        }

        if let ampersandRange = remaining.range(of: "&") {
            job = String(remaining[ampersandRange.upperBound...])
            remaining = String(remaining[..<ampersandRange.lowerBound])
        }

        // Check for path-only rules first (start with /).
        // This handles cases like "/foo:bar@baz" where : and @ are part of the path.
        if remaining.hasPrefix("/") {
            path = remaining
            return
        }

        let atIndex = remaining.firstIndex(of: "@")
        var colonIndex = remaining.firstIndex(of: ":")

        if let atIndex {
            // user@host[:path]
            username = String(remaining[..<atIndex])
            let afterAt = remaining.index(after: atIndex)
            if let currentColon = colonIndex, currentColon < atIndex {
                // malformed, like foo:bar@baz
                colonIndex = nil
            } else if let currentColon = colonIndex {
                // user@host:path
                hostname = String(remaining[afterAt..<currentColon])
            } else {
                // user@host or user@ (empty hostname)
                let hostPart = String(remaining[afterAt...])
                if !hostPart.isEmpty {
                    hostname = hostPart
                }
            }
        }

        if let colonIndex {
            // [user@]host:path
            if hostname == nil {
                let hostPart = String(remaining[..<colonIndex])
                if !hostPart.isEmpty {
                    hostname = hostPart
                }
            }
            path = String(remaining[remaining.index(after: colonIndex)...])
        } else if atIndex == nil && !remaining.isEmpty {
            // host (only if non-empty after stripping job)
            hostname = remaining
        }
    }

    @objc(ruleWithString:)
    static func rule(withString string: String?) -> iTermRule? {
        guard let string else {
            return nil
        }
        return iTermRule(string: string)
    }

    override var description: String {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        return "<\(type(of: self)): \(ptr) hostname=\(hostname ?? "(null)") username=\(username ?? "(null)") path=\(path ?? "(null)") job=\(job ?? "(null)")>"
    }

    // Monotonically increasing on [0, 1) for nonnegative x; grows slowly enough that
    // squash(x + 1) - squash(x) > machine_epsilon for any plausible Unix path length.
    private func squash(_ x: Double) -> Double {
        it_assert(x >= 0)
        return x / (x + 1.0)
    }

    private var hasAnyComponentBesidesHostname: Bool {
        return username != nil || path != nil || job != nil
    }

    /// Computes how strongly this rule matches the current session context (0 means no match).
    @objc(scoreForHostname:username:path:job:commandLine:expressionValueProvider:)
    func score(forHostname hostname: String?,
               username: String?,
               path: String?,
               job: String?,
               commandLine: String?,
               expressionValueProvider: AutomaticProfileSwitchingExpressionScoreProvider?) -> Double {
        if let expression {
            return expressionValueProvider?.score(forExpression: expression) ?? 0.0
        }

        let pathPartialMatchScore = 0.0
        let catchallRuleScore = 1.0
        let pathExactMatchScore = 2.0
        let userExactMatchScore = 4.0
        let jobMatchScore = 8.0
        let hostPartialMatchScore = 16.0
        let hostExactMatchScore = 32.0

        var score = 0.0

        if let ruleJob = self.job {
            let jobMatches = (job as NSString?)?.stringMatchesGlobPattern(ruleJob, caseSensitive: true) ?? false
            let commandLineMatches = (commandLine as NSString?)?.stringMatchesGlobPattern(ruleJob, caseSensitive: true) ?? false
            if !jobMatches && !commandLineMatches {
                return 0
            }
            score += jobMatchScore
        }

        if let ruleHostname = self.hostname {
            if !ruleHostname.contains("*") && hostname == ruleHostname {
                score += hostExactMatchScore
            } else if ruleHostname == "*" {
                if !hasAnyComponentBesidesHostname {
                    // Preserve backward compatibility for a bare `*` catch-all rule so it still
                    // outranks profiles with no APS rules while ranking below every specific rule.
                    score += catchallRuleScore
                }
            } else if (hostname as NSString?)?.stringMatchesGlobPattern(ruleHostname, caseSensitive: false) ?? false {
                score += hostPartialMatchScore * (1.0 + squash(Double(ruleHostname.utf16.count)))
            } else if !ruleHostname.isEmpty {
                return 0
            }
        }

        if let ruleUsername = self.username {
            if username == ruleUsername {
                score += userExactMatchScore
            } else if !ruleUsername.isEmpty {
                return 0
            }
        }

        if let rulePath = self.path {
            // An augmented path ends in `/` so `/foo/bar/*` matches `/foo/bar`, while keeping the
            // original path tested so `/foo/*` still matches `/foo/bar`.
            let augmentedPath: String? = path.map { $0.hasSuffix("/") ? $0 : $0 + "/" }

            if !rulePath.contains("*") && path == rulePath {
                score += pathExactMatchScore
            } else if (augmentedPath as NSString?)?.stringMatchesGlobPattern(rulePath, caseSensitive: true) == true ||
                      (path as NSString?)?.stringMatchesGlobPattern(rulePath, caseSensitive: true) == true {
                score += pathPartialMatchScore + squash(Double(rulePath.utf16.count))
            } else if !rulePath.isEmpty {
                return 0
            }
        }

        return score
    }
}
