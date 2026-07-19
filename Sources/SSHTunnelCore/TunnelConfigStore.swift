import Foundation

public struct TunnelConfigStore: Sendable {
    public let configURL: URL

    public var preRemoteForwardBackupURL: URL {
        configURL.appendingPathExtension("pre-remote-forward.bak")
    }

    public var preImportBackupURL: URL {
        configURL.appendingPathExtension("pre-import.bak")
    }

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
        try createPreRemoteForwardBackupIfNeeded(for: tunnels)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tunnels)
        try data.write(to: configURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
    }

    @discardableResult
    public func createPreImportBackup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: configURL)
        try data.write(to: preImportBackupURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: preImportBackupURL.path
        )
        return preImportBackupURL
    }

    public func restorePreImportBackup() throws {
        guard FileManager.default.fileExists(atPath: preImportBackupURL.path) else {
            return
        }
        let data = try Data(contentsOf: preImportBackupURL)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
    }

    public func restorePreImportState(hadOriginalFile: Bool) throws {
        if hadOriginalFile {
            try restorePreImportBackup()
        } else if FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.removeItem(at: configURL)
        }
    }

    private func createPreRemoteForwardBackupIfNeeded(for tunnels: [TunnelConfig]) throws {
        let fileManager = FileManager.default
        guard tunnels.contains(where: { $0.mode == .remoteForward }),
              fileManager.fileExists(atPath: configURL.path),
              !fileManager.fileExists(atPath: preRemoteForwardBackupURL.path) else {
            return
        }

        let existingData = try Data(contentsOf: configURL)
        if let modes = try? JSONDecoder().decode([StoredMode].self, from: existingData),
           modes.contains(where: { $0.mode == TunnelMode.remoteForward.rawValue }) {
            return
        }

        try fileManager.copyItem(at: configURL, to: preRemoteForwardBackupURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: preRemoteForwardBackupURL.path
        )
    }

    private struct StoredMode: Decodable {
        let mode: String?
    }
}
