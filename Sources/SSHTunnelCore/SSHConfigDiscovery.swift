import Darwin
import Foundation

public struct SSHConfigDiscoveredHost: Equatable, Sendable {
    public let alias: String
    public let sourcePath: String
    public let line: Int

    public init(alias: String, sourcePath: String, line: Int) {
        self.alias = alias
        self.sourcePath = sourcePath
        self.line = line
    }
}

public enum SSHConfigDiscoveryIssueKind: String, Equatable, Sendable {
    case unreadableFile
    case invalidEncoding
    case invalidSyntax
    case includeCycle
    case traversalLimitReached
}

public struct SSHConfigDiscoveryIssue: Equatable, Sendable {
    public let kind: SSHConfigDiscoveryIssueKind
    public let sourcePath: String
    public let line: Int?

    public init(kind: SSHConfigDiscoveryIssueKind, sourcePath: String, line: Int? = nil) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.line = line
    }
}

public struct SSHConfigDiscoveryResult: Equatable, Sendable {
    public let hosts: [SSHConfigDiscoveredHost]
    public let issues: [SSHConfigDiscoveryIssue]
    public let containsMatchExec: Bool

    public init(
        hosts: [SSHConfigDiscoveredHost],
        issues: [SSHConfigDiscoveryIssue],
        containsMatchExec: Bool
    ) {
        self.hosts = hosts
        self.issues = issues
        self.containsMatchExec = containsMatchExec
    }
}

public struct SSHConfigDiscovery: Sendable {
    public let configURL: URL
    public let includeBaseURL: URL
    public let maximumDepth: Int
    public let maximumFileCount: Int

    public init(
        configURL: URL,
        includeBaseURL: URL? = nil,
        maximumDepth: Int = 32,
        maximumFileCount: Int = 256
    ) {
        self.configURL = configURL
        self.includeBaseURL = includeBaseURL ?? configURL.deletingLastPathComponent()
        self.maximumDepth = maximumDepth
        self.maximumFileCount = maximumFileCount
    }

    public func discover() -> SSHConfigDiscoveryResult {
        var scanner = Scanner(
            includeBaseURL: includeBaseURL,
            maximumDepth: maximumDepth,
            maximumFileCount: maximumFileCount
        )
        scanner.scan(configURL, depth: 0)
        return scanner.result
    }
}

private extension SSHConfigDiscovery {
    struct Scanner {
        let includeBaseURL: URL
        let maximumDepth: Int
        let maximumFileCount: Int
        var hosts: [SSHConfigDiscoveredHost] = []
        var issues: [SSHConfigDiscoveryIssue] = []
        var containsMatchExec = false
        var visitedPaths = Set<String>()
        var activePaths = Set<String>()
        var seenAliases = Set<String>()

        var result: SSHConfigDiscoveryResult {
            SSHConfigDiscoveryResult(
                hosts: hosts,
                issues: issues,
                containsMatchExec: containsMatchExec
            )
        }

        mutating func scan(_ inputURL: URL, depth: Int) {
            let url = inputURL.standardizedFileURL.resolvingSymlinksInPath()
            let path = url.path

            guard depth <= maximumDepth, visitedPaths.count < maximumFileCount else {
                appendIssueOnce(.traversalLimitReached, path: path)
                return
            }
            guard !activePaths.contains(path) else {
                appendIssueOnce(.includeCycle, path: path)
                return
            }
            guard visitedPaths.insert(path).inserted else { return }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                appendIssueOnce(.unreadableFile, path: path)
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                appendIssueOnce(.invalidEncoding, path: path)
                return
            }

            activePaths.insert(path)
            defer { activePaths.remove(path) }

            for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let lineNumber = offset + 1
                guard let fields = Self.fields(in: rawLine) else {
                    issues.append(SSHConfigDiscoveryIssue(
                        kind: .invalidSyntax,
                        sourcePath: path,
                        line: lineNumber
                    ))
                    continue
                }
                guard let keyword = fields.first?.lowercased() else { continue }

                switch keyword {
                case "host":
                    discoverHosts(fields.dropFirst(), path: path, line: lineNumber)
                case "include":
                    for pattern in fields.dropFirst() {
                        for includedURL in includedURLs(for: pattern) {
                            scan(includedURL, depth: depth + 1)
                        }
                    }
                case "match":
                    if fields.dropFirst().contains(where: {
                        let condition = $0.lowercased()
                        return condition == "exec" || condition.hasPrefix("exec=")
                    }) {
                        containsMatchExec = true
                    }
                default:
                    continue
                }
            }
        }

        private mutating func discoverHosts(
            _ patterns: ArraySlice<String>,
            path: String,
            line: Int
        ) {
            for alias in patterns where Self.isExplicitHost(alias) {
                let key = alias.folding(options: .caseInsensitive, locale: nil)
                guard seenAliases.insert(key).inserted else { continue }
                hosts.append(SSHConfigDiscoveredHost(alias: alias, sourcePath: path, line: line))
            }
        }

        private mutating func appendIssueOnce(_ kind: SSHConfigDiscoveryIssueKind, path: String) {
            let issue = SSHConfigDiscoveryIssue(kind: kind, sourcePath: path)
            guard !issues.contains(issue) else { return }
            issues.append(issue)
        }

        private func includedURLs(for rawPattern: String) -> [URL] {
            let expandedPattern: String
            if rawPattern == "~" {
                expandedPattern = FileManager.default.homeDirectoryForCurrentUser.path
            } else if rawPattern.hasPrefix("~/") {
                expandedPattern = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: String(rawPattern.dropFirst(2)))
                    .path
            } else if rawPattern.hasPrefix("/") {
                expandedPattern = rawPattern
            } else {
                expandedPattern = includeBaseURL.appending(path: rawPattern).path
            }

            guard Self.containsGlob(expandedPattern) else {
                return [URL(fileURLWithPath: expandedPattern)]
            }

            var result = glob_t()
            defer { globfree(&result) }
            let status = expandedPattern.withCString { pattern in
                glob(pattern, GLOB_NOSORT, nil, &result)
            }
            guard status == 0, let paths = result.gl_pathv else { return [] }
            return (0..<Int(result.gl_pathc))
                .compactMap { index -> String? in
                    guard let path = paths[index] else { return nil }
                    return String(cString: path)
                }
                .sorted()
                .map { URL(fileURLWithPath: $0) }
        }

        private static func containsGlob(_ value: String) -> Bool {
            value.contains("*") || value.contains("?") || value.contains("[")
        }

        private static func isExplicitHost(_ value: String) -> Bool {
            !value.isEmpty
                && !value.hasPrefix("!")
                && !containsGlob(value)
        }

        private static func fields(in line: String) -> [String]? {
            var fields: [String] = []
            var current = ""
            var quote: Character?
            var escaped = false

            for character in line {
                if escaped {
                    current.append(character)
                    escaped = false
                    continue
                }
                if character == "\\" {
                    escaped = true
                    continue
                }
                if let activeQuote = quote {
                    if character == activeQuote {
                        quote = nil
                    } else {
                        current.append(character)
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#" {
                    break
                } else if character.isWhitespace {
                    if !current.isEmpty {
                        fields.append(current)
                        current = ""
                    }
                } else {
                    current.append(character)
                }
            }

            guard quote == nil else { return nil }
            if escaped { current.append("\\") }
            if !current.isEmpty { fields.append(current) }

            if fields.first?.contains("=") == true {
                let first = fields.removeFirst()
                guard let separator = first.firstIndex(of: "=") else { return nil }
                let keyword = String(first[..<separator])
                let value = String(first[first.index(after: separator)...])
                guard !keyword.isEmpty else { return nil }
                fields.insert(keyword, at: 0)
                if !value.isEmpty {
                    fields.insert(value, at: 1)
                }
            } else if fields.count > 1, fields[1] == "=" {
                fields.remove(at: 1)
            }
            return fields
        }
    }
}
