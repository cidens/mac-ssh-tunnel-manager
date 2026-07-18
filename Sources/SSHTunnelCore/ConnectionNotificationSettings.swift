import Foundation

public struct ConnectionNotificationSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultSettings = ConnectionNotificationSettings(
        schemaVersion: currentSchemaVersion,
        isEnabled: false
    )

    public var schemaVersion: Int
    public var isEnabled: Bool

    public init(schemaVersion: Int, isEnabled: Bool) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConnectionNotificationSettingsError.unsupportedSchemaVersion(schemaVersion)
        }
    }
}

public enum ConnectionNotificationSettingsError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

public struct ConnectionNotificationSettingsStore: Sendable {
    public let settingsURL: URL

    public init(settingsURL: URL) {
        self.settingsURL = settingsURL
    }

    public func load() throws -> ConnectionNotificationSettings? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        let settings = try JSONDecoder().decode(ConnectionNotificationSettings.self, from: data)
        try settings.validate()
        return settings
    }

    public func save(_ settings: ConnectionNotificationSettings) throws {
        try settings.validate()
        let directory = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }
}
