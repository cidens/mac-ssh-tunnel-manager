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

@MainActor
@Test func addSSHConfigTunnelAllowsRemoteAndDynamicForwarding() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "remote-service": .resolved("remoteforward localhost:18080 127.0.0.1:8080\n"),
        "socks-service": .resolved("dynamicforward 127.0.0.1:1080\n"),
    ])
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: resolver
    )
    defer { manager.prepareForApplicationTermination() }

    for alias in ["remote-service", "socks-service"] {
        var draft = TunnelDraft()
        draft.mode = .sshConfig
        draft.name = alias
        draft.sshConfigName = alias
        #expect(manager.addTunnel(draft))
    }

    #expect(manager.tunnels.map(\.sshConfigName) == ["remote-service", "socks-service"])
    #expect(resolver.requestedNames == ["remote-service", "socks-service"])
}

@MainActor
@Test func addDynamicForwardRequiresConfirmationForNonLoopbackBind() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "example-bastion": .resolved("user appuser\nhostname example-bastion\n")
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
    draft.localHost = "*"
    draft.localPort = "1080"
    var didSucceed = false

    #expect(!manager.addTunnel(draft, onSuccess: { didSucceed = true }))
    #expect(manager.tunnels.isEmpty)
    #expect(manager.riskWarning != nil)
    #expect(!didSucceed)

    manager.confirmRiskyOperation()

    #expect(manager.tunnels.count == 1)
    #expect(manager.riskWarning == nil)
    #expect(didSucceed)
}

@MainActor
@Test func addSSHConfigTunnelRequiresConfirmationForNonLoopbackLocalForward() throws {
    let directory = try temporaryDirectory()
    let resolver = StubSSHConfigResolver(results: [
        "example-service": .resolved("localforward *:18080 127.0.0.1:8080\n")
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

    #expect(!manager.addTunnel(draft))
    #expect(manager.tunnels.isEmpty)
    #expect(manager.riskWarning != nil)

    manager.cancelRiskyOperation()

    #expect(manager.tunnels.isEmpty)
    #expect(manager.riskWarning == nil)
}

@MainActor
@Test func addRemoteForwardRequiresEndpointBoundConfirmationForNonLoopbackRemoteBind() throws {
    let directory = try temporaryDirectory()
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: StubSSHConfigResolver(results: [
            "example-bastion": .resolved("user appuser\nhostname 203.0.113.10\n")
        ])
    )
    defer { manager.prepareForApplicationTermination() }
    let draft = remoteForwardDraft(remoteBindHost: "*", remotePort: "18080")

    #expect(!manager.addTunnel(draft))
    #expect(manager.tunnels.isEmpty)
    #expect(manager.riskWarning?.title == AppStrings.riskyRemoteBindTitle())
    #expect(manager.riskWarning?.message.contains("*:18080") == true)
    #expect(manager.riskWarning?.message.contains("GatewayPorts") == true)

    manager.confirmRiskyOperation()

    #expect(manager.tunnels.count == 1)
    #expect(manager.riskWarning == nil)
}

@MainActor
@Test func startingRemoteForwardCannotBypassNonLoopbackRemoteBindConfirmation() throws {
    let directory = try temporaryDirectory()
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: StubSSHConfigResolver(results: [
            "example-bastion": .resolved("user appuser\nhostname 203.0.113.10\n")
        ])
    )
    defer { manager.prepareForApplicationTermination() }
    let tunnel = TunnelConfig(
        name: "Example Reverse",
        sshHost: "example-bastion",
        remoteBindHost: "0.0.0.0",
        remotePort: 18_080,
        localTargetHost: "127.0.0.1",
        localPort: 3_000,
        openURL: nil
    )

    manager.start(tunnel)

    #expect(manager.riskWarning?.message.contains("0.0.0.0:18080") == true)
    #expect(!manager.isManagedProcessRunning(for: tunnel))
}

@MainActor
@Test func remoteForwardRejectsSSHHostWithExistingForwardingDirectives() throws {
    let directory = try temporaryDirectory()
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        sshConfigResolver: StubSSHConfigResolver(results: [
            "example-bastion": .resolved("dynamicforward 127.0.0.1:1080\n")
        ])
    )
    defer { manager.prepareForApplicationTermination() }

    #expect(!manager.addTunnel(remoteForwardDraft()))
    #expect(manager.tunnels.isEmpty)
    #expect(manager.addError.contains("DynamicForward"))
}

@MainActor
@Test func remoteForwardUsesProcessOnlyStatusWithoutCheckingLocalTargetPort() {
    let tunnel = TunnelConfig(
        name: "Example Reverse",
        sshHost: "example-bastion",
        remoteBindHost: "localhost",
        remotePort: 18_080,
        localTargetHost: "127.0.0.1",
        localPort: 3_000,
        openURL: nil
    )

    #expect(!TunnelManager.shouldCheckLocalPort(for: tunnel))
}

@MainActor
@Test func favoriteChangeRollsBackWhenSavingFails() throws {
    let directory = try temporaryDirectory()
    let configURL = directory.appending(path: "tunnels.json")
    let store = TunnelConfigStore(configURL: configURL)
    let tunnel = TunnelConfig(name: "Example", sshConfigName: "example", openURL: nil)
    try store.save([tunnel])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }
    try replaceConfigFileWithDirectory(at: configURL)

    manager.toggleFavorite(try #require(manager.tunnels.first))

    #expect(manager.tunnels.first?.isFavorite == false)
    #expect(!manager.addError.isEmpty)
}

@MainActor
@Test func manualOrderRollsBackWhenSavingFails() throws {
    let directory = try temporaryDirectory()
    let configURL = directory.appending(path: "tunnels.json")
    let store = TunnelConfigStore(configURL: configURL)
    let first = TunnelConfig(name: "First", sshConfigName: "first", openURL: nil)
    let second = TunnelConfig(name: "Second", sshConfigName: "second", openURL: nil)
    try store.save([first, second])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }
    try replaceConfigFileWithDirectory(at: configURL)

    manager.moveManualOrder(try #require(manager.tunnels.first), direction: 1)

    #expect(manager.tunnels.map(\.name) == ["First", "Second"])
    #expect(manager.tunnels.map(\.manualOrder) == [0, 1])
    #expect(!manager.addError.isEmpty)
}

@MainActor
@Test func manualOrderMovePersistsTheSwappedSequence() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let first = TunnelConfig(name: "First", sshConfigName: "first", openURL: nil)
    let second = TunnelConfig(name: "Second", sshConfigName: "second", openURL: nil)
    try store.save([first, second])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }

    manager.moveManualOrder(try #require(manager.tunnels.first), direction: 1)

    #expect(manager.tunnels.map(\.name) == ["Second", "First"])
    #expect(manager.tunnels.map(\.manualOrder) == [0, 1])
    #expect(try store.load().map(\.name) == ["Second", "First"])
}

@MainActor
@Test func availableTagsDeduplicateCaseInsensitiveValuesAcrossTunnels() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var first = TunnelConfig(name: "First", sshConfigName: "first", openURL: nil)
    first.tags = ["Production", "Database"]
    var second = TunnelConfig(name: "Second", sshConfigName: "second", openURL: nil)
    second.tags = ["production", "Web"]
    try store.save([first, second])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }

    #expect(manager.availableTags == ["Database", "Production", "Web"])
}

@MainActor
@Test func searchDoesNotMatchPlaceholderPortsForSSHConfigTunnels() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = TunnelConfig(name: "Example", sshConfigName: "plain-alias", openURL: nil)
    try store.save([tunnel])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }

    #expect(
        manager.displayedTunnels(
            searchQuery: "0",
            selectedTag: nil,
            favoritesOnly: false,
            sort: .manual
        ).isEmpty
    )
    #expect(
        manager.displayedTunnels(
            searchQuery: "plain-alias",
            selectedTag: nil,
            favoritesOnly: false,
            sort: .manual
        ).map(\.id) == [tunnel.id]
    )
}

@MainActor
@Test func batchImportStoresUniqueSSHConfigReferencesWithoutStartingThem() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    try store.save([TunnelConfig(name: "Existing", sshConfigName: "existing-service", openURL: nil)])
    let manager = TunnelManager(store: store, sshConfigResolver: StubSSHConfigResolver(results: [:]))
    defer { manager.prepareForApplicationTermination() }

    let imported = manager.importSSHConfigAliases([
        "new-service",
        "NEW-SERVICE",
        "EXISTING-SERVICE",
    ])

    #expect(imported)
    #expect(manager.tunnels.map(\.sshConfigName) == ["existing-service", "new-service"])
    #expect(manager.tunnels.allSatisfy { !$0.isAutoReconnectEnabled })
    #expect(manager.tunnels.allSatisfy { !$0.isAutoStartEnabled })
    #expect(manager.tunnels.allSatisfy { !manager.isManagedProcessRunning(for: $0) })
    #expect(try store.load() == manager.tunnels)
}

@MainActor
@Test func batchImportRollsBackWhenPersistenceFails() throws {
    let directory = try temporaryDirectory()
    let configURL = directory.appending(path: "tunnels.json")
    try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: false)
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: configURL),
        sshConfigResolver: StubSSHConfigResolver(results: [:])
    )
    defer { manager.prepareForApplicationTermination() }

    #expect(!manager.importSSHConfigAliases(["new-service"]))
    #expect(manager.tunnels.isEmpty)
    #expect(!manager.addError.isEmpty)
}

@MainActor
@Test func appLaunchStartsOnlyTunnelsWithAutomaticConnectionEnabled() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var automatic = TunnelConfig(name: "Automatic", sshConfigName: "automatic", openURL: nil)
    automatic.isAutoStartEnabled = true
    let manual = TunnelConfig(name: "Manual", sshConfigName: "manual", openURL: nil)
    try store.save([automatic, manual])
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: StubSSHConfigResolver(results: [:])
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAutomaticallyConfiguredTunnels()

    let loadedAutomatic = try #require(manager.tunnels.first { $0.id == automatic.id })
    let loadedManual = try #require(manager.tunnels.first { $0.id == manual.id })
    #expect(!manager.lastError(for: loadedAutomatic).isEmpty)
    #expect(manager.lastError(for: loadedManual).isEmpty)
    #expect(manager.status(for: loadedAutomatic) == .failed)
    #expect(manager.status(for: loadedManual) == .stopped)
}

@MainActor
@Test func appLaunchSkipsRiskyListenerWithoutOpeningConfirmation() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var tunnel = TunnelConfig(name: "Risky", sshConfigName: "risky", openURL: nil)
    tunnel.isAutoStartEnabled = true
    try store.save([tunnel])
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: StubSSHConfigResolver(results: [
            "risky": .resolved("localforward *:18080 127.0.0.1:8080\n")
        ])
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAutomaticallyConfiguredTunnels()

    let loaded = try #require(manager.tunnels.first)
    #expect(manager.riskWarning == nil)
    #expect(manager.status(for: loaded) == .failed)
    #expect(manager.lastError(for: loaded).contains("跳过自动连接")
        || manager.lastError(for: loaded).contains("Automatic connection was skipped"))
}

@MainActor
@Test func automaticConnectionFailureUsesAutoReconnectPreference() throws {
    let directory = try temporaryDirectory()
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var retrying = TunnelConfig(name: "Retrying", sshConfigName: "retrying", openURL: nil)
    retrying.isAutoStartEnabled = true
    retrying.isAutoReconnectEnabled = true
    var oneShot = TunnelConfig(name: "One Shot", sshConfigName: "one-shot", openURL: nil)
    oneShot.isAutoStartEnabled = true
    try store.save([retrying, oneShot])
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: StubSSHConfigResolver(results: [
            "retrying": .timedOut,
            "one-shot": .timedOut,
        ])
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAutomaticallyConfiguredTunnels()

    let loadedRetrying = try #require(manager.tunnels.first { $0.id == retrying.id })
    let loadedOneShot = try #require(manager.tunnels.first { $0.id == oneShot.id })
    #expect(manager.status(for: loadedRetrying) == .waitingToReconnect)
    #expect(manager.status(for: loadedOneShot) == .failed)
}

private final class StubSSHConfigResolver: SSHConfigResolving, @unchecked Sendable {
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

private func remoteForwardDraft(
    remoteBindHost: String = "localhost",
    remotePort: String = "18080"
) -> TunnelDraft {
    var draft = TunnelDraft()
    draft.mode = .remoteForward
    draft.name = "Example Reverse"
    draft.sshHost = "example-bastion"
    draft.remoteHost = remoteBindHost
    draft.remotePort = remotePort
    draft.localHost = "127.0.0.1"
    draft.localPort = "3000"
    return draft
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-manager-app-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func replaceConfigFileWithDirectory(at url: URL) throws {
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
}
