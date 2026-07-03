import Foundation
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@MainActor
@Test func addDynamicForwardRejectsHostWithForwardingDirectivesFromInjectedResolver() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "example-bastion": .resolved("""
        user appuser
        hostname 203.0.113.10
        localforward 127.0.0.1:18080 127.0.0.1:8080
        """)
    ])
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: resolver
    )
    defer { manager.prepareForApplicationTermination() }
    var draft = TunnelDraft()
    draft.mode = .dynamicForward
    draft.name = "Example SOCKS"
    draft.sshHost = "example-bastion"
    draft.localHost = "127.0.0.1"
    draft.localPort = "1080"

    let added = manager.addTunnel(draft)

    #expect(!added)
    #expect(manager.tunnels.isEmpty)
    #expect(manager.addError.contains("LocalForward"))
    #expect(resolver.requestedNames == ["example-bastion"])
}

@MainActor
@Test func startLocalForwardRejectsHostWithForwardingDirectivesFromInjectedResolver() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "example-bastion": .resolved("""
        user appuser
        hostname 203.0.113.10
        remoteforward 127.0.0.1:18080 127.0.0.1:8080
        """)
    ])
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: resolver
    )
    defer { manager.prepareForApplicationTermination() }
    let tunnel = TunnelConfig(
        name: "Example",
        sshHost: "example-bastion",
        localHost: "127.0.0.1",
        localPort: 18080,
        remoteHost: "127.0.0.1",
        remotePort: 8080,
        openURL: nil
    )

    manager.start(tunnel)

    #expect(manager.lastError(for: tunnel).contains("RemoteForward"))
    #expect(!manager.isManagedProcessRunning(for: tunnel))
    #expect(resolver.requestedNames == ["example-bastion"])
}

@MainActor
@Test func addSSHConfigTunnelAllowsLocalForwardFromInjectedResolver() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "example-service": .resolved("""
        user appuser
        hostname 203.0.113.10
        localforward 127.0.0.1:18080 127.0.0.1:8080
        """)
    ])
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: resolver
    )
    defer { manager.prepareForApplicationTermination() }
    var draft = TunnelDraft()
    draft.mode = .sshConfig
    draft.name = "Example Service"
    draft.sshConfigName = "example-service"

    let added = manager.addTunnel(draft)

    #expect(added)
    #expect(manager.tunnels.count == 1)
    #expect(resolver.requestedNames == ["example-service"])
}

private final class StubSSHConfigResolver: SSHConfigResolving {
    private let results: [String: SSHConfigResolution]
    private(set) var requestedNames: [String] = []

    init(results: [String: SSHConfigResolution]) {
        self.results = results
    }

    func resolveConfig(named name: String, timeout: TimeInterval) -> SSHConfigResolution {
        requestedNames.append(name)
        return results[name] ?? .failed
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-manager-app-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
