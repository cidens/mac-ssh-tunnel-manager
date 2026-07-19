import Foundation

public struct TunnelConfigurationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let oldestReadableSchemaVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let appVersion: String
    public let configs: [TunnelConfig]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        exportedAt: Date = Date(),
        appVersion: String,
        configs: [TunnelConfig]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.configs = configs
    }
}

public enum TunnelImportConflictStrategy: String, CaseIterable, Identifiable, Sendable {
    case skip
    case replace
    case copy

    public var id: String { rawValue }
}

public enum TunnelImportIssue: Equatable, Sendable {
    case duplicateIdentifier(UUID)
    case duplicateName(String)
    case localEndpointConflict(host: String, port: Int)
    case exposedListener(host: String, port: Int)

    public var isBlocking: Bool {
        switch self {
        case .duplicateIdentifier, .duplicateName, .localEndpointConflict:
            return true
        case .exposedListener:
            return false
        }
    }
}

public struct TunnelImportPreview: Equatable, Sendable {
    public let sourceAppVersion: String
    public let exportedAt: Date
    public let importedCount: Int
    public let skippedCount: Int
    public let replacedCount: Int
    public let copiedCount: Int
    public let issues: [TunnelImportIssue]
    public let mergedConfigs: [TunnelConfig]

    public var canCommit: Bool { !issues.contains(where: \.isBlocking) }
}

public enum TunnelConfigurationTransferError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge(maximumBytes: Int)
    case unsupportedSchemaVersion(Int)
    case tooManyConfigs(maximum: Int)
    case emptyAppVersion
    case duplicateIdentifier(UUID)
    case invalidConfig(name: String, reason: String)

    public var errorDescription: String? {
        description()
    }

    public func description(language: String? = nil) -> String {
        switch self {
        case .fileTooLarge(let maximumBytes):
            return CoreStrings.format("transfer.error.fileTooLarge", language: language, maximumBytes)
        case .unsupportedSchemaVersion(let version):
            return CoreStrings.format("transfer.error.unsupportedSchema", language: language, version)
        case .tooManyConfigs(let maximum):
            return CoreStrings.format("transfer.error.tooManyConfigs", language: language, maximum)
        case .emptyAppVersion:
            return CoreStrings.string("transfer.error.emptyAppVersion", language: language)
        case .duplicateIdentifier(let id):
            return CoreStrings.format("transfer.error.duplicateID", language: language, id.uuidString)
        case .invalidConfig(let name, let reason):
            return CoreStrings.format("transfer.error.invalidConfig", language: language, name, reason)
        }
    }
}

public struct TunnelConfigurationTransfer: Sendable {
    public static let maximumFileSize = 1_048_576
    public static let maximumConfigCount = 1_000

    private let commandBuilder = SSHCommandBuilder()

    public init() {}

    public func exportData(
        configs: [TunnelConfig],
        appVersion: String,
        exportedAt: Date = Date()
    ) throws -> Data {
        guard configs.count <= Self.maximumConfigCount else {
            throw TunnelConfigurationTransferError.tooManyConfigs(maximum: Self.maximumConfigCount)
        }
        let document = TunnelConfigurationDocument(
            exportedAt: exportedAt,
            appVersion: appVersion,
            configs: configs
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumFileSize else {
            throw TunnelConfigurationTransferError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        return data
    }

    public func decode(_ data: Data) throws -> TunnelConfigurationDocument {
        guard data.count <= Self.maximumFileSize else {
            throw TunnelConfigurationTransferError.fileTooLarge(maximumBytes: Self.maximumFileSize)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(DocumentHeader.self, from: data)
        guard (TunnelConfigurationDocument.oldestReadableSchemaVersion...TunnelConfigurationDocument.currentSchemaVersion)
            .contains(header.schemaVersion) else {
            throw TunnelConfigurationTransferError.unsupportedSchemaVersion(header.schemaVersion)
        }
        let document = try decoder.decode(TunnelConfigurationDocument.self, from: data)
        guard !document.appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TunnelConfigurationTransferError.emptyAppVersion
        }
        guard document.configs.count <= Self.maximumConfigCount else {
            throw TunnelConfigurationTransferError.tooManyConfigs(maximum: Self.maximumConfigCount)
        }

        var identifiers = Set<UUID>()
        var ruleIdentifiers = Set<UUID>()
        for config in document.configs {
            guard identifiers.insert(config.id).inserted else {
                throw TunnelConfigurationTransferError.duplicateIdentifier(config.id)
            }
            do {
                try commandBuilder.validate(config)
                for rule in config.effectiveRules {
                    guard ruleIdentifiers.insert(rule.id).inserted else {
                        throw TunnelConfigurationTransferError.duplicateIdentifier(rule.id)
                    }
                    try validateURL(rule.openURL)
                }
                try validateURL(config.openURL)
            } catch {
                throw TunnelConfigurationTransferError.invalidConfig(
                    name: config.name,
                    reason: error.localizedDescription
                )
            }
        }
        return document
    }

    public func preview(
        document: TunnelConfigurationDocument,
        existing: [TunnelConfig],
        strategy: TunnelImportConflictStrategy
    ) -> TunnelImportPreview {
        var merged = existing
        var importedCount = 0
        var skippedCount = 0
        var replacedCount = 0
        var copiedCount = 0
        var touchedIDs = Set<UUID>()
        var nextManualOrder = (existing.compactMap(\.manualOrder).max() ?? -1) + 1

        let orderedSources = document.configs.sorted {
            ($0.manualOrder ?? Int.max, $0.name) < ($1.manualOrder ?? Int.max, $1.name)
        }
        for source in orderedSources {
            var imported = source
            imported.isAutoStartEnabled = false
            imported.lastUsedAt = nil
            imported.replaceRules(imported.effectiveRules.map { rule in
                var sanitized = rule
                sanitized.riskConfirmationSignature = nil
                return sanitized
            })

            if let existingIndex = merged.firstIndex(where: { $0.id == imported.id }) {
                switch strategy {
                case .skip:
                    skippedCount += 1
                    continue
                case .replace:
                    imported.manualOrder = merged[existingIndex].manualOrder
                    merged[existingIndex] = imported
                    touchedIDs.insert(imported.id)
                    replacedCount += 1
                case .copy:
                    imported.id = UUID()
                    imported.replaceRules(imported.effectiveRules.map { rule in
                        var copy = rule
                        copy.id = UUID()
                        return copy
                    })
                    imported.manualOrder = nextManualOrder
                    imported.name = uniqueCopyName(for: imported.name, in: merged)
                    nextManualOrder += 1
                    merged.append(imported)
                    touchedIDs.insert(imported.id)
                    copiedCount += 1
                }
            } else {
                imported.manualOrder = nextManualOrder
                nextManualOrder += 1
                merged.append(imported)
                touchedIDs.insert(imported.id)
                importedCount += 1
            }
        }

        normalizeManualOrder(&merged)
        let issues = identifierIssues(in: merged)
            + nameIssues(in: merged, touchedIDs: touchedIDs)
            + endpointIssues(in: merged, touchedIDs: touchedIDs)
        return TunnelImportPreview(
            sourceAppVersion: document.appVersion,
            exportedAt: document.exportedAt,
            importedCount: importedCount,
            skippedCount: skippedCount,
            replacedCount: replacedCount,
            copiedCount: copiedCount,
            issues: issues,
            mergedConfigs: merged
        )
    }

    private func validateURL(_ url: URL?) throws {
        guard let url else { return }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw TunnelValidationError.invalidURL("openURL")
        }
    }

    private func identifierIssues(in configs: [TunnelConfig]) -> [TunnelImportIssue] {
        var seen = Set<UUID>()
        var issues: [TunnelImportIssue] = []
        for rule in configs.flatMap(\.effectiveRules) where !seen.insert(rule.id).inserted {
            issues.append(.duplicateIdentifier(rule.id))
        }
        return issues
    }

    private func nameIssues(in configs: [TunnelConfig], touchedIDs: Set<UUID>) -> [TunnelImportIssue] {
        var issues: [TunnelImportIssue] = []
        for (index, config) in configs.enumerated() {
            let key = TunnelConfig.nameComparisonKey(config.name)
            for other in configs.dropFirst(index + 1) where
                key == TunnelConfig.nameComparisonKey(other.name)
                    && (touchedIDs.contains(config.id) || touchedIDs.contains(other.id)) {
                let reportedName: String
                if touchedIDs.contains(config.id), !touchedIDs.contains(other.id) {
                    reportedName = other.name
                } else {
                    reportedName = config.name
                }
                issues.append(.duplicateName(reportedName.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return issues
    }

    private func uniqueCopyName(for name: String, in configs: [TunnelConfig]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingKeys = Set(configs.map { TunnelConfig.nameComparisonKey($0.name) })
        var suffix = 2
        while existingKeys.contains(TunnelConfig.nameComparisonKey("\(base) (\(suffix))")) {
            suffix += 1
        }
        return "\(base) (\(suffix))"
    }

    private func endpointIssues(in configs: [TunnelConfig], touchedIDs: Set<UUID>) -> [TunnelImportIssue] {
        var issues: [TunnelImportIssue] = []
        let endpoints = configs.flatMap { config in
            config.effectiveRules.compactMap { rule in
                listenerEndpoint(for: rule).map { (config.id, $0) }
            }
        }
        for (index, value) in endpoints.enumerated() {
            let (id, endpoint) = value
            for other in endpoints.dropFirst(index + 1) {
                guard endpoint.port == other.1.port,
                      Self.hostsOverlap(endpoint.host, other.1.host),
                      touchedIDs.contains(id) || touchedIDs.contains(other.0) else {
                    continue
                }
                let reportedHost = touchedIDs.contains(id) ? endpoint.host : other.1.host
                issues.append(.localEndpointConflict(host: reportedHost, port: endpoint.port))
            }
        }
        for config in configs where touchedIDs.contains(config.id) {
            for rule in config.effectiveRules {
                guard let endpoint = exposureEndpoint(for: rule),
                      Self.isPotentiallyExposed(endpoint.host) else {
                    continue
                }
                issues.append(.exposedListener(host: endpoint.host, port: endpoint.port))
            }
        }
        return Array(Set(issues.map(IssueKey.init))).map(\.issue).sorted(by: issueSort)
    }

    private func listenerEndpoint(for rule: TunnelForwardRule) -> ListenerEndpoint? {
        guard rule.isEnabled else { return nil }
        switch rule.mode {
        case .localForward, .dynamicForward:
            return ListenerEndpoint(host: normalizedHost(rule.localHost), port: rule.localPort)
        case .remoteForward, .sshConfig:
            return nil
        }
    }

    private func exposureEndpoint(for rule: TunnelForwardRule) -> ListenerEndpoint? {
        guard rule.isEnabled else { return nil }
        switch rule.mode {
        case .localForward, .dynamicForward:
            return ListenerEndpoint(host: normalizedHost(rule.localHost), port: rule.localPort)
        case .remoteForward:
            return ListenerEndpoint(host: normalizedHost(rule.remoteHost), port: rule.remotePort)
        case .sshConfig:
            return nil
        }
    }

    private func normalizedHost(_ host: String) -> String {
        let normalized = host.lowercased()
        return normalized == "localhost" ? "127.0.0.1" : normalized
    }

    private static func isPotentiallyExposed(_ host: String) -> Bool {
        ["*", "0.0.0.0", "::", "[::]"].contains(host.lowercased())
    }

    private static func hostsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let wildcardHosts = Set(["*", "0.0.0.0", "::", "[::]"])
        return wildcardHosts.contains(lhs) || wildcardHosts.contains(rhs)
    }

    private func normalizeManualOrder(_ configs: inout [TunnelConfig]) {
        configs.sort { ($0.manualOrder ?? Int.max, $0.name) < ($1.manualOrder ?? Int.max, $1.name) }
        for index in configs.indices { configs[index].manualOrder = index }
    }

    private func issueSort(_ lhs: TunnelImportIssue, _ rhs: TunnelImportIssue) -> Bool {
        String(describing: lhs) < String(describing: rhs)
    }

    private struct ListenerEndpoint: Hashable {
        let host: String
        let port: Int
    }

    private struct DocumentHeader: Decodable {
        let schemaVersion: Int
    }

    private struct IssueKey: Hashable {
        let kind: Int
        let host: String
        let port: Int
        let issue: TunnelImportIssue

        init(_ issue: TunnelImportIssue) {
            self.issue = issue
            switch issue {
            case .duplicateIdentifier(let id):
                kind = 0
                host = id.uuidString
                port = 0
            case .duplicateName(let name):
                kind = 1
                host = TunnelConfig.nameComparisonKey(name)
                port = 0
            case .localEndpointConflict(let hostValue, let portValue):
                kind = 2
                host = hostValue
                port = portValue
            case .exposedListener(let hostValue, let portValue):
                kind = 3
                host = hostValue
                port = portValue
            }
        }

        static func == (lhs: IssueKey, rhs: IssueKey) -> Bool {
            lhs.kind == rhs.kind && lhs.host == rhs.host && lhs.port == rhs.port
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(host)
            hasher.combine(port)
        }
    }
}
