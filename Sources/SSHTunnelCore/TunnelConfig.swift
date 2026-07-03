import Foundation

public enum TunnelMode: String, Codable, Equatable, Sendable {
    case localForward
    case dynamicForward
    case sshConfig
}

public struct TunnelConfig: Codable, Equatable, Identifiable, Sendable {
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mode = try container.decodeIfPresent(TunnelMode.self, forKey: .mode) ?? .localForward
        name = try container.decode(String.self, forKey: .name)
        openURL = try container.decodeIfPresent(URL.self, forKey: .openURL)

        switch mode {
        case .localForward:
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

        switch mode {
        case .localForward:
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
