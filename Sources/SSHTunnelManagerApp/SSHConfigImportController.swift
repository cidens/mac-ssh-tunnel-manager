import Foundation
import SSHTunnelCore

enum SSHConfigImportPreview: Equatable, Sendable {
    case notPreviewed
    case resolving
    case resolved([SSHConfigForwardingDirective])
    case noForwarding
    case failed
    case timedOut
}

struct SSHConfigImportCandidate: Equatable, Identifiable, Sendable {
    let alias: String
    let sourcePath: String?
    let sourceLine: Int?
    var isSelected: Bool
    let isDuplicate: Bool
    var preview: SSHConfigImportPreview

    var id: String {
        alias.folding(options: .caseInsensitive, locale: nil)
    }
}

@MainActor
final class SSHConfigImportController: ObservableObject {
    @Published private(set) var candidates: [SSHConfigImportCandidate] = []
    @Published private(set) var discoveryIssues: [SSHConfigDiscoveryIssue] = []
    @Published private(set) var containsMatchExec = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var isResolving = false
    @Published private(set) var manualAliasError = ""

    private let discovery: SSHConfigDiscovery
    private let resolver: any SSHConfigResolving
    private var existingAliases = Set<String>()
    private var matchExecApproved = false

    init(
        discovery: SSHConfigDiscovery = SSHConfigDiscovery(
            configURL: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".ssh/config")
        ),
        resolver: any SSHConfigResolving = SystemSSHConfigResolver()
    ) {
        self.discovery = discovery
        self.resolver = resolver
    }

    var selectedCount: Int {
        candidates.count(where: { $0.isSelected && !$0.isDuplicate })
    }

    var canPreview: Bool {
        !isDiscovering && !isResolving && candidates.contains {
            $0.isSelected && !$0.isDuplicate
        }
    }

    var importableAliases: [String] {
        candidates.compactMap { candidate in
            guard candidate.isSelected, !candidate.isDuplicate,
                  case .resolved(let directives) = candidate.preview,
                  !directives.isEmpty else {
                return nil
            }
            return candidate.alias
        }
    }

    var hasRiskyImport: Bool {
        candidates.contains { candidate in
            guard candidate.isSelected,
                  case .resolved(let directives) = candidate.preview else {
                return false
            }
            return directives.contains(where: \.isPotentiallyExposed)
        }
    }

    var requiresMatchExecConfirmation: Bool {
        containsMatchExec && !matchExecApproved
    }

    @discardableResult
    func load(existingAliases values: [String]) -> Task<Void, Never>? {
        guard !isDiscovering else { return nil }
        existingAliases = Set(values.map(Self.comparisonKey))
        isDiscovering = true
        return Task { [weak self, discovery] in
            let result = await Task.detached(priority: .utility) {
                discovery.discover()
            }.value
            guard let self else { return }
            self.discoveryIssues = result.issues.map { issue in
                SSHConfigDiscoveryIssue(
                    kind: issue.kind,
                    sourcePath: Self.abbreviatedPath(issue.sourcePath),
                    line: issue.line
                )
            }
            self.containsMatchExec = result.containsMatchExec
            self.candidates = result.hosts.map { host in
                SSHConfigImportCandidate(
                    alias: host.alias,
                    sourcePath: Self.abbreviatedPath(host.sourcePath),
                    sourceLine: host.line,
                    isSelected: false,
                    isDuplicate: self.existingAliases.contains(Self.comparisonKey(host.alias)),
                    preview: .notPreviewed
                )
            }
            self.isDiscovering = false
        }
    }

    func addManualAlias(_ rawValue: String) -> Bool {
        manualAliasError = ""
        let alias = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let tunnel = TunnelConfig(name: alias, sshConfigName: alias, openURL: nil)
            try SSHCommandBuilder().validate(tunnel)
        } catch {
            manualAliasError = AppStrings.importInvalidAlias()
            return false
        }

        if let index = candidates.firstIndex(where: {
            Self.comparisonKey($0.alias) == Self.comparisonKey(alias)
        }) {
            if !candidates[index].isDuplicate {
                candidates[index].isSelected = true
            }
            return true
        }

        let duplicate = existingAliases.contains(Self.comparisonKey(alias))
        candidates.append(SSHConfigImportCandidate(
            alias: alias,
            sourcePath: nil,
            sourceLine: nil,
            isSelected: !duplicate,
            isDuplicate: duplicate,
            preview: .notPreviewed
        ))
        return true
    }

    func setSelected(_ selected: Bool, id: SSHConfigImportCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }),
              !candidates[index].isDuplicate else { return }
        candidates[index].isSelected = selected
    }

    func selectAll() {
        for index in candidates.indices where !candidates[index].isDuplicate {
            candidates[index].isSelected = true
        }
    }

    func selectNone() {
        for index in candidates.indices {
            candidates[index].isSelected = false
        }
    }

    func approveMatchExec() {
        matchExecApproved = true
    }

    func previewSelected() async {
        guard canPreview, !requiresMatchExecConfirmation else { return }
        let aliases = candidates.compactMap { candidate in
            candidate.isSelected && !candidate.isDuplicate ? candidate.alias : nil
        }
        guard !aliases.isEmpty else { return }

        isResolving = true
        for index in candidates.indices where aliases.contains(candidates[index].alias) {
            candidates[index].preview = .resolving
        }
        let resolver = self.resolver
        let results = await Task.detached(priority: .userInitiated) {
            await Self.resolve(aliases: aliases, resolver: resolver)
        }.value

        for index in candidates.indices {
            guard let resolution = results[candidates[index].alias] else { continue }
            switch resolution {
            case .resolved(let output):
                let directives = SSHConfigOutputParser.forwardingDirectives(output)
                candidates[index].preview = directives.isEmpty
                    ? .noForwarding
                    : .resolved(directives)
            case .failed:
                candidates[index].preview = .failed
            case .timedOut:
                candidates[index].preview = .timedOut
            }
        }
        isResolving = false
    }

    private nonisolated static func resolve(
        aliases: [String],
        resolver: any SSHConfigResolving
    ) async -> [String: SSHConfigResolution] {
        await withTaskGroup(of: (String, SSHConfigResolution).self) { group in
            var iterator = aliases.makeIterator()
            for _ in 0..<min(4, aliases.count) {
                if let alias = iterator.next() {
                    group.addTask {
                        (alias, resolver.resolveConfig(named: alias, timeout: 10))
                    }
                }
            }

            var results: [String: SSHConfigResolution] = [:]
            while let (alias, resolution) = await group.next() {
                results[alias] = resolution
                if let nextAlias = iterator.next() {
                    group.addTask {
                        (nextAlias, resolver.resolveConfig(named: nextAlias, timeout: 10))
                    }
                }
            }
            return results
        }
    }

    private nonisolated static func comparisonKey(_ value: String) -> String {
        value.folding(options: .caseInsensitive, locale: nil)
    }

    private nonisolated static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
