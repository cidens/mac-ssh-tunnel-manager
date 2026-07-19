import Foundation
import Testing
@testable import SSHTunnelCore

@Test func storeLoadsEmptyListWhenConfigFileDoesNotExist() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))

    #expect(try store.load() == [])
}

@Test func storeRoundTripsTunnelConfigurationsAsJSON() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = TunnelConfig(
        name: "Example DB",
        sshHost: "work-host",
        localHost: "127.0.0.1",
        localPort: 15432,
        remoteHost: "127.0.0.1",
        remotePort: 5432,
        openURL: URL(string: "http://127.0.0.1:15432")
    )

    try store.save([tunnel])

    #expect(try store.load() == [tunnel])
}

@Test func storeWritesConfigWithUserOnlyPermissions() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "nested/tunnels.json"))
    let tunnel = TunnelConfig(
        name: "Example DB",
        sshHost: "work-host",
        localHost: "127.0.0.1",
        localPort: 15432,
        remoteHost: "127.0.0.1",
        remotePort: 5432,
        openURL: nil
    )

    try store.save([tunnel])

    #expect(try permissions(of: directory.appending(path: "nested")) == 0o700)
    #expect(try permissions(of: directory.appending(path: "nested/tunnels.json")) == 0o600)
}

@Test func storeTightensExistingConfigPermissions() throws {
    let directory = try temporaryDirectory()
    let configURL = directory.appending(path: "tunnels.json")
    _ = FileManager.default.createFile(atPath: configURL.path, contents: Data("[]".utf8))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: configURL.path
    )
    let store = TunnelConfigStore(configURL: configURL)

    try store.save([])

    #expect(try permissions(of: configURL) == 0o600)
}

@Test func storeRoundTripsSSHConfigTunnelConfigurationsAsJSON() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = TunnelConfig(
        name: "Example via config",
        sshConfigName: "example-service",
        openURL: URL(string: "http://127.0.0.1:18080")
    )

    try store.save([tunnel])

    let loaded = try store.load()
    #expect(loaded == [tunnel])
    #expect(loaded.first?.mode == .sshConfig)
    #expect(loaded.first?.sshConfigName == "example-service")
}

@Test func storeRoundTripsDynamicForwardTunnelConfigurationsAsJSON() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000108",
      "mode": "dynamicForward",
      "name": "Example SOCKS",
      "sshHost": "example-bastion",
      "localHost": "127.0.0.1",
      "localPort": 1080
    }
    """
    let data = try #require(json.data(using: .utf8))
    let tunnel = try JSONDecoder().decode(TunnelConfig.self, from: data)

    try store.save([tunnel])

    let loaded = try store.load()
    #expect(loaded == [tunnel])
    #expect(loaded.first?.mode.rawValue == "dynamicForward")
    #expect(loaded.first?.sshHost == "example-bastion")
    #expect(loaded.first?.localHost == "127.0.0.1")
    #expect(loaded.first?.localPort == 1080)
    #expect(loaded.first?.remoteHost == "")
    #expect(loaded.first?.remotePort == 0)
}

@Test func decodesLegacyTunnelConfigurationsAsLocalForward() throws {
    let json = """
    [
      {
        "id": "00000000-0000-0000-0000-000000000001",
        "name": "Legacy",
        "sshHost": "work-host",
        "localHost": "127.0.0.1",
        "localPort": 15432,
        "remoteHost": "127.0.0.1",
        "remotePort": 5432,
        "openURL": "http://127.0.0.1:15432"
      }
    ]
    """
    let data = try #require(json.data(using: .utf8))

    let tunnels = try JSONDecoder().decode([TunnelConfig].self, from: data)

    #expect(tunnels.first?.mode == .localForward)
    #expect(tunnels.first?.sshHost == "work-host")
    #expect(tunnels.first?.localPort == 15432)
    #expect(tunnels.first?.tags == [])
    #expect(tunnels.first?.isFavorite == false)
    #expect(tunnels.first?.manualOrder == nil)
    #expect(tunnels.first?.isAutoReconnectEnabled == false)
    #expect(tunnels.first?.isAutoStartEnabled == false)
}

@Test func normalizesTagsByTrimmingAndCaseInsensitiveDeduplication() throws {
    let tags = try TunnelConfig.normalizedTags([
        "  Production ", "production", "Database", "  ", "PRODUCTION", "", "Database",
        "production", " ", "DATABASE", "Production", "café", "CAFE"
    ])

    #expect(tags == ["Production", "Database", "café", "CAFE"])
}

@Test func rejectsTagsBeyondConfiguredLimits() {
    #expect(throws: TunnelTagValidationError.tooManyTags(maximum: TunnelConfig.maximumTagCount)) {
        try TunnelConfig.normalizedTags((0...TunnelConfig.maximumTagCount).map { "tag-\($0)" })
    }
    #expect(throws: TunnelTagValidationError.tagTooLong(maximum: TunnelConfig.maximumTagLength)) {
        try TunnelConfig.normalizedTags([String(repeating: "x", count: TunnelConfig.maximumTagLength + 1)])
    }
}

@Test func roundTripsOrganizationMetadata() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var tunnel = TunnelConfig(
        name: "Example DB", sshHost: "work-host", localHost: "127.0.0.1", localPort: 15432,
        remoteHost: "127.0.0.1", remotePort: 5432, openURL: nil
    )
    tunnel.tags = ["Database"]
    tunnel.isFavorite = true
    tunnel.manualOrder = 3
    tunnel.lastUsedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    tunnel.isAutoReconnectEnabled = true
    tunnel.isAutoStartEnabled = true

    try store.save([tunnel])
    #expect(try store.load() == [tunnel])
}

@Test func storeRoundTripsRemoteForwardConfigurations() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = TunnelConfig(
        name: "Example Reverse",
        sshHost: "example-bastion",
        remoteBindHost: "localhost",
        remotePort: 18_080,
        localTargetHost: "127.0.0.1",
        localPort: 3_000,
        openURL: nil
    )

    try store.save([tunnel])

    let loaded = try store.load()
    #expect(loaded == [tunnel])
}

@Test func firstRemoteForwardWriteCreatesOneTimeRecoverableLegacyBackup() throws {
    let directory = try temporaryDirectory()
    let configURL = directory.appending(path: "tunnels.json")
    let store = TunnelConfigStore(configURL: configURL)
    let legacyJSON = """
    [
      {
        "id": "00000000-0000-0000-0000-000000000030",
        "name": "Legacy 0.3.0",
        "sshHost": "example-bastion",
        "localHost": "127.0.0.1",
        "localPort": 15432,
        "remoteHost": "127.0.0.1",
        "remotePort": 5432
      }
    ]
    """
    let legacyData = try #require(legacyJSON.data(using: .utf8))
    try legacyData.write(to: configURL)
    let legacyTunnel = try #require(try store.load().first)
    let remoteTunnel = TunnelConfig(
        name: "Example Reverse",
        sshHost: "example-bastion",
        remoteBindHost: "localhost",
        remotePort: 18_080,
        localTargetHost: "127.0.0.1",
        localPort: 3_000,
        openURL: nil
    )

    try store.save([legacyTunnel, remoteTunnel])

    #expect(try Data(contentsOf: store.preRemoteForwardBackupURL) == legacyData)
    #expect(try permissions(of: store.preRemoteForwardBackupURL) == 0o600)
    #expect(try store.load().first == legacyTunnel)

    let originalBackup = try Data(contentsOf: store.preRemoteForwardBackupURL)
    try store.save([remoteTunnel])
    #expect(try Data(contentsOf: store.preRemoteForwardBackupURL) == originalBackup)

    let restored = try JSONDecoder().decode(
        [TunnelConfig].self,
        from: Data(contentsOf: store.preRemoteForwardBackupURL)
    )
    #expect(restored == [legacyTunnel])
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-manager-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
