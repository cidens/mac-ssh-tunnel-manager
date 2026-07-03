import Foundation

public struct TunnelConfigStore: Sendable {
    public let configURL: URL

    public init(configURL: URL) {
        self.configURL = configURL
    }

    public func load() throws -> [TunnelConfig] {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return []
        }

        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode([TunnelConfig].self, from: data)
    }

    public func save(_ tunnels: [TunnelConfig]) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tunnels)
        try data.write(to: configURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
    }
}
