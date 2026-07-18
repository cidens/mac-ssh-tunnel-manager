import Foundation

public enum TunnelMode: String, Codable, Equatable, Sendable {
    case localForward
    case remoteForward
    case dynamicForward
    case sshConfig
}

public struct TunnelConfig: Codable, Equatable, Identifiable, Sendable {
    public static let maximumTagCount = 10
    public static let maximumTagLength = 32

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

        switch mode {
        case .localForward, .remoteForward:
            sshHost = try container.decode(String.self, forKey: .sshHost)
            localHost = try container.decode(String.self, forKey: .localHost)
            localPort = try container.decode(Int.self, forKey: .localPort)
            remoteHost = try container.decode(String.self, forKey: .remoteHost)
            remotePort = try container.decode(Int.self, forKey: .remotePort)
            sshConfigName = try container.decodeIfPresent(String.self, forKey: .sshConfigName)
        case .dynamicForward:
            sshHost = try container.decode(String.self, forKey: .sshHost)
            localHost = try container.decode(String.self, forKey: .localHost)
            localPort = try container.decode(Int.self, forKey: .localPort)
            remoteHost = ""
            remotePort = 0
            sshConfigName = nil
        case .sshConfig:
            sshHost = ""
            localHost = ""
            localPort = 0
            remoteHost = ""
            remotePort = 0
            sshConfigName = try container.decode(String.self, forKey: .sshConfigName)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(openURL, forKey: .openURL)
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(manualOrder, forKey: .manualOrder)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)

        switch mode {
        case .localForward, .remoteForward:
            try container.encode(sshHost, forKey: .sshHost)
            try container.encode(localHost, forKey: .localHost)
            try container.encode(localPort, forKey: .localPort)
            try container.encode(remoteHost, forKey: .remoteHost)
            try container.encode(remotePort, forKey: .remotePort)
        case .dynamicForward:
            try container.encode(sshHost, forKey: .sshHost)
            try container.encode(localHost, forKey: .localHost)
            try container.encode(localPort, forKey: .localPort)
        case .sshConfig:
            try container.encode(sshConfigName, forKey: .sshConfigName)
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
    case sshConfigMissingLocalForward(String)
    case sshConfigValidationTimedOut(String, Int)
    case sshHostContainsForwardingDirectives(String)

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
        case .sshConfigMissingLocalForward(let name):
            return CoreStrings.format("error.sshConfigMissingLocalForward", language: language, name)
        case .sshConfigValidationTimedOut(let name, let seconds):
            return CoreStrings.format("error.sshConfigValidationTimedOut", language: language, name, seconds)
        case .sshHostContainsForwardingDirectives(let name):
            return CoreStrings.format("error.sshHostContainsForwardingDirectives", language: language, name)
        }
    }

    private func fieldName(_ field: String, language: String?) -> String {
        CoreStrings.string("field.\(field)", language: language, defaultValue: field)
    }
}
