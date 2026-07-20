import Foundation

public enum TunnelMode: String, Codable, Equatable, Sendable {
    case localForward
    case remoteForward
    case dynamicForward
    case sshConfig
}

public struct TunnelForwardRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var mode: TunnelMode
    public var localHost: String
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var openURL: URL?
    public var isEnabled: Bool
    public var riskConfirmationSignature: String?
    public var healthCheck: TunnelHealthCheckConfiguration?

    public init(
        id: UUID = UUID(),
        mode: TunnelMode,
        localHost: String,
        localPort: Int,
        remoteHost: String = "",
        remotePort: Int = 0,
        openURL: URL? = nil,
        isEnabled: Bool = true,
        riskConfirmationSignature: String? = nil,
        healthCheck: TunnelHealthCheckConfiguration? = nil
    ) {
        self.id = id
        self.mode = mode
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.openURL = openURL
        self.isEnabled = isEnabled
        self.riskConfirmationSignature = riskConfirmationSignature
        self.healthCheck = healthCheck
    }

    public var currentRiskSignature: String {
        "\(mode.rawValue)|\(listenerHost.lowercased())|\(listenerPort)"
    }

    public var hasValidRiskConfirmation: Bool {
        riskConfirmationSignature == currentRiskSignature
    }

    public var listenerHost: String {
        mode == .remoteForward ? remoteHost : localHost
    }

    public var listenerPort: Int {
        mode == .remoteForward ? remotePort : localPort
    }
}

public struct TunnelConfig: Codable, Equatable, Identifiable, Sendable {
    public static let maximumTagCount = 10
    public static let maximumTagLength = 16

    public static func nameComparisonKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
    public static let maximumRuleCount = 20

    public var id: UUID
    public var mode: TunnelMode
    public var name: String
    public var sshHost: String
    public var localHost: String
    public var localPort: Int
    public var remoteHost: String
    public var remotePort: Int
    public var sshConfigName: String?
    public var openURL: URL?
    public var tags: [String]
    public var isFavorite: Bool
    public var manualOrder: Int?
    public var lastUsedAt: Date?
    public var isAutoReconnectEnabled: Bool
    public var isAutoStartEnabled: Bool
    public var rules: [TunnelForwardRule]

    public var effectiveRules: [TunnelForwardRule] {
        guard mode != .sshConfig, rules.count == 1, var rule = rules.first else {
            return rules
        }
        rule.mode = mode
        rule.localHost = localHost
        rule.localPort = localPort
        rule.remoteHost = remoteHost
        rule.remotePort = remotePort
        rule.openURL = openURL
        return [rule]
    }

    public mutating func replaceRules(_ newRules: [TunnelForwardRule]) {
        rules = newRules
        guard mode != .sshConfig, let primary = newRules.first else { return }
        mode = primary.mode
        localHost = primary.localHost
        localPort = primary.localPort
        remoteHost = primary.remoteHost
        remotePort = primary.remotePort
        openURL = primary.openURL
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sshHost: String,
        localHost: String,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        openURL: URL?
    ) {
        self.id = id
        self.mode = .localForward
        self.name = name
        self.sshHost = sshHost
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.sshConfigName = nil
        self.openURL = openURL
        self.tags = []
        self.isFavorite = false
        self.manualOrder = nil
        self.lastUsedAt = nil
        self.isAutoReconnectEnabled = false
        self.isAutoStartEnabled = false
        self.rules = [TunnelForwardRule(
            mode: .localForward,
            localHost: localHost,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            openURL: openURL
        )]
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sshHost: String,
        remoteBindHost: String,
        remotePort: Int,
        localTargetHost: String,
        localPort: Int,
        openURL: URL?
    ) {
        self.id = id
        self.mode = .remoteForward
        self.name = name
        self.sshHost = sshHost
        self.localHost = localTargetHost
        self.localPort = localPort
        self.remoteHost = remoteBindHost
        self.remotePort = remotePort
        self.sshConfigName = nil
        self.openURL = openURL
        self.tags = []
        self.isFavorite = false
        self.manualOrder = nil
        self.lastUsedAt = nil
        self.isAutoReconnectEnabled = false
        self.isAutoStartEnabled = false
        self.rules = [TunnelForwardRule(
            mode: .remoteForward,
            localHost: localTargetHost,
            localPort: localPort,
            remoteHost: remoteBindHost,
            remotePort: remotePort,
            openURL: openURL
        )]
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sshHost: String,
        localHost: String,
        localPort: Int,
        openURL: URL?
    ) {
        self.id = id
        self.mode = .dynamicForward
        self.name = name
        self.sshHost = sshHost
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = ""
        self.remotePort = 0
        self.sshConfigName = nil
        self.openURL = openURL
        self.tags = []
        self.isFavorite = false
        self.manualOrder = nil
        self.lastUsedAt = nil
        self.isAutoReconnectEnabled = false
        self.isAutoStartEnabled = false
        self.rules = [TunnelForwardRule(
            mode: .dynamicForward,
            localHost: localHost,
            localPort: localPort,
            openURL: openURL
        )]
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sshConfigName: String,
        openURL: URL?
    ) {
        self.id = id
        self.mode = .sshConfig
        self.name = name
        self.sshHost = ""
        self.localHost = ""
        self.localPort = 0
        self.remoteHost = ""
        self.remotePort = 0
        self.sshConfigName = sshConfigName
        self.openURL = openURL
        self.tags = []
        self.isFavorite = false
        self.manualOrder = nil
        self.lastUsedAt = nil
        self.isAutoReconnectEnabled = false
        self.isAutoStartEnabled = false
        self.rules = []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case name
        case sshHost
        case localHost
        case localPort
        case remoteHost
        case remotePort
        case sshConfigName
        case openURL
        case tags
        case isFavorite
        case manualOrder
        case lastUsedAt
        case isAutoReconnectEnabled
        case isAutoStartEnabled
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decodeIfPresent(TunnelMode.self, forKey: .mode) ?? .localForward
        name = try container.decode(String.self, forKey: .name)
        openURL = try container.decodeIfPresent(URL.self, forKey: .openURL)
        tags = try Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isAutoReconnectEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutoReconnectEnabled) ?? false
        isAutoStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutoStartEnabled) ?? false

        if let decodedRules = try container.decodeIfPresent([TunnelForwardRule].self, forKey: .rules) {
            rules = decodedRules
            if mode != .sshConfig, let primary = decodedRules.first {
                sshHost = try container.decode(String.self, forKey: .sshHost)
                mode = primary.mode
                localHost = primary.localHost
                localPort = primary.localPort
                remoteHost = primary.remoteHost
                remotePort = primary.remotePort
                openURL = primary.openURL
                sshConfigName = nil
            } else if mode == .sshConfig {
                sshHost = ""
                localHost = ""
                localPort = 0
                remoteHost = ""
                remotePort = 0
                sshConfigName = try container.decode(String.self, forKey: .sshConfigName)
            } else {
                sshHost = try container.decode(String.self, forKey: .sshHost)
                localHost = ""
                localPort = 0
                remoteHost = ""
                remotePort = 0
                sshConfigName = nil
            }
            return
        }

        switch mode {
        case .localForward, .remoteForward:
            sshHost = try container.decode(String.self, forKey: .sshHost)
            localHost = try container.decode(String.self, forKey: .localHost)
            localPort = try container.decode(Int.self, forKey: .localPort)
            remoteHost = try container.decode(String.self, forKey: .remoteHost)
            remotePort = try container.decode(Int.self, forKey: .remotePort)
            sshConfigName = try container.decodeIfPresent(String.self, forKey: .sshConfigName)
            rules = [TunnelForwardRule(
                id: id,
                mode: mode,
                localHost: localHost,
                localPort: localPort,
                remoteHost: remoteHost,
                remotePort: remotePort,
                openURL: openURL
            )]
        case .dynamicForward:
            sshHost = try container.decode(String.self, forKey: .sshHost)
            localHost = try container.decode(String.self, forKey: .localHost)
            localPort = try container.decode(Int.self, forKey: .localPort)
            remoteHost = ""
            remotePort = 0
            sshConfigName = nil
            rules = [TunnelForwardRule(
                id: id,
                mode: .dynamicForward,
                localHost: localHost,
                localPort: localPort,
                openURL: openURL
            )]
        case .sshConfig:
            sshHost = ""
            localHost = ""
            localPort = 0
            remoteHost = ""
            remotePort = 0
            sshConfigName = try container.decode(String.self, forKey: .sshConfigName)
            rules = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(name, forKey: .name)
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(manualOrder, forKey: .manualOrder)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(isAutoReconnectEnabled, forKey: .isAutoReconnectEnabled)
        try container.encode(isAutoStartEnabled, forKey: .isAutoStartEnabled)

        switch mode {
        case .localForward, .remoteForward, .dynamicForward:
            try container.encode(sshHost, forKey: .sshHost)
            try container.encode(effectiveRules, forKey: .rules)
        case .sshConfig:
            try container.encode(sshConfigName, forKey: .sshConfigName)
            try container.encodeIfPresent(openURL, forKey: .openURL)
        }
    }

    public static func normalizedTags(_ values: [String]) throws -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            guard tag.count <= maximumTagLength else {
                throw TunnelTagValidationError.tagTooLong(maximum: maximumTagLength)
            }
            guard seen.insert(tag.folding(options: .caseInsensitive, locale: nil)).inserted else {
                continue
            }
            guard result.count < maximumTagCount else {
                throw TunnelTagValidationError.tooManyTags(maximum: maximumTagCount)
            }
            result.append(tag)
        }
        return result
    }
}

public enum TunnelTagValidationError: Error, Equatable, LocalizedError {
    case tooManyTags(maximum: Int)
    case tagTooLong(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .tooManyTags(let maximum): return CoreStrings.format("error.tooManyTags", maximum)
        case .tagTooLong(let maximum): return CoreStrings.format("error.tagTooLong", maximum)
        }
    }
}

public enum TunnelValidationError: Error, Equatable, LocalizedError {
    case emptyField(String)
    case invalidHost(String)
    case invalidPort(String)
    case invalidURL(String)
    case localPortOccupied(String, Int)
    case sshConfigMissingForwardingDirective(String)
    case sshConfigValidationTimedOut(String, Int)
    case sshHostContainsForwardingDirectives(String)
    case invalidRule(Int, String)
    case noEnabledRules

    public var errorDescription: String? {
        description()
    }

    public func description(language: String? = nil) -> String {
        switch self {
        case .emptyField(let field):
            return CoreStrings.format("error.emptyField", language: language, fieldName(field, language: language))
        case .invalidHost(let field):
            return CoreStrings.format("error.invalidHost", language: language, fieldName(field, language: language))
        case .invalidPort(let field):
            return CoreStrings.format("error.invalidPort", language: language, fieldName(field, language: language))
        case .invalidURL(let field):
            return CoreStrings.format("error.invalidURL", language: language, fieldName(field, language: language))
        case .localPortOccupied(let host, let port):
            return CoreStrings.format("error.localPortOccupied", language: language, host, port)
        case .sshConfigMissingForwardingDirective(let name):
            return CoreStrings.format("error.sshConfigMissingForwardingDirective", language: language, name)
        case .sshConfigValidationTimedOut(let name, let seconds):
            return CoreStrings.format("error.sshConfigValidationTimedOut", language: language, name, seconds)
        case .sshHostContainsForwardingDirectives(let name):
            return CoreStrings.format("error.sshHostContainsForwardingDirectives", language: language, name)
        case .invalidRule(let index, let reason):
            return CoreStrings.format("error.invalidRule", language: language, index, reason)
        case .noEnabledRules:
            return CoreStrings.string("error.noEnabledRules", language: language)
        }
    }

    private func fieldName(_ field: String, language: String?) -> String {
        CoreStrings.string("field.\(field)", language: language, defaultValue: field)
    }
}
