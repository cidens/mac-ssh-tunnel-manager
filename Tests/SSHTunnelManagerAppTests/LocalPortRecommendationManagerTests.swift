import Foundation
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@MainActor
@Test func managerRecommendationCombinesStoredDraftAndLsofEndpointsWithOneSnapshot() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    var stored = TunnelConfig(
        name: "Stored",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 18_081,
        remoteHost: "example-service",
        remotePort: 80,
        openURL: nil
    )
    stored.replaceRules(stored.effectiveRules.map { rule in
        var disabled = rule
        disabled.isEnabled = false
        return disabled
    })
    try store.save([stored])
    let provider = CountingLocalPortSnapshotProvider(output: """
    helper 100 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:18083 (LISTEN)
    """)
    let manager = TunnelManager(store: store, localPortSnapshotProvider: provider)
    var draft = recommendationDraft(port: "18080")
    var second = TunnelRuleDraft()
    second.mode = .dynamicForward
    second.localHost = "127.0.0.1"
    second.localPort = "18082"
    second.isEnabled = false
    draft.additionalRules = [second]
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)

    let recommendation = try await manager.recommendedLocalPort(
        for: fingerprint,
        in: draft,
        editingTunnelID: nil
    )

    #expect(recommendation == 18_084)
    #expect(provider.callCount == 1)
}

@MainActor
@Test func managerRecommendationExcludesTheConfigurationBeingEdited() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let stored = TunnelConfig(
        name: "Editing",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 18_080,
        remoteHost: "example-service",
        remotePort: 80,
        openURL: nil
    )
    try store.save([stored])
    let manager = TunnelManager(
        store: store,
        localPortSnapshotProvider: CountingLocalPortSnapshotProvider(output: "")
    )
    let draft = TunnelDraft(tunnel: stored)
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)

    let recommendation = try await manager.recommendedLocalPort(
        for: fingerprint,
        in: draft,
        editingTunnelID: stored.id
    )

    #expect(recommendation == 18_081)
}

@MainActor
@Test func managerRecommendationPropagatesSnapshotFailureWithoutGuessing() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        localPortSnapshotProvider: FailingLocalPortSnapshotProvider()
    )
    let draft = recommendationDraft(port: "18080")
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)

    await #expect(throws: LocalPortRecommendationError.snapshotFailed) {
        try await manager.recommendedLocalPort(
            for: fingerprint,
            in: draft,
            editingTunnelID: nil
        )
    }
}

@MainActor
@Test func managerRecommendationRejectsInvalidListenerHostBeforeSnapshot() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = CountingLocalPortSnapshotProvider(output: "")
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        localPortSnapshotProvider: provider
    )
    var draft = recommendationDraft(port: "18080")
    draft.localHost = "127.0.0.1;touch"
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)

    await #expect(throws: LocalPortRecommendationError.invalidListenerHost) {
        try await manager.recommendedLocalPort(
            for: fingerprint,
            in: draft,
            editingTunnelID: nil
        )
    }
    #expect(provider.callCount == 0)
}

@MainActor
@Test func cancellingRecommendationCancelsTheInFlightSnapshot() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshotStarted = AsyncStream<Void>.makeStream()
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        localPortSnapshotProvider: CancellationAwareLocalPortSnapshotProvider {
            snapshotStarted.continuation.yield()
        }
    )
    let draft = recommendationDraft(port: "18080")
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)
    let operation = Task {
        try await manager.recommendedLocalPort(
            for: fingerprint,
            in: draft,
            editingTunnelID: nil
        )
    }

    var snapshotStartIterator = snapshotStarted.stream.makeAsyncIterator()
    _ = await snapshotStartIterator.next()
    operation.cancel()

    await #expect(throws: CancellationError.self) {
        try await operation.value
    }
}

@MainActor
@Test func localPortRecommendationEndToEndMeetsReleasePerformanceBudget() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        localPortSnapshotProvider: SystemLocalPortSnapshotProvider()
    )
    let draft = recommendationDraft(port: "60000")
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let port = try await manager.recommendedLocalPort(
            for: fingerprint,
            in: draft,
            editingTunnelID: nil
        )
        let elapsed = started.duration(to: .now)
        #expect(port != 60_000)
        if iteration >= 5 {
            samples.append(recommendationSeconds(elapsed))
        }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    let medianMilliseconds = String(format: "%.3f", median * 1_000)
    let p95Milliseconds = String(format: "%.3f", p95 * 1_000)
    print("local-port-end-to-end lsof_snapshots=35 samples=30 median_ms=\(medianMilliseconds) p95_ms=\(p95Milliseconds)")
    #if !DEBUG
    #expect(p95 < 1, "Release end-to-end P95 was \(p95) seconds")
    #endif
}

@MainActor
@Test func slowPortSnapshotDoesNotBlockTheMainActor() async throws {
    let directory = try recommendationTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manager = TunnelManager(
        store: TunnelConfigStore(configURL: directory.appending(path: "tunnels.json")),
        localPortSnapshotProvider: DelayedLocalPortSnapshotProvider(delay: 0.075)
    )
    let draft = recommendationDraft(port: "60000")
    let fingerprint = try #require(draft.rules[0].localPortRecommendationFingerprint)
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let operation = Task {
            try await manager.recommendedLocalPort(
                for: fingerprint,
                in: draft,
                editingTunnelID: nil
            )
        }
        try await Task.sleep(for: .milliseconds(5))
        let mainActorDelay = started.duration(to: .now)
        #expect(try await operation.value == 60_001)
        if iteration >= 5 {
            samples.append(recommendationSeconds(mainActorDelay))
        }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    let medianMilliseconds = String(format: "%.3f", median * 1_000)
    let p95Milliseconds = String(format: "%.3f", p95 * 1_000)
    print("local-port-main-actor samples=30 injected_snapshot_ms=75 median_ms=\(medianMilliseconds) p95_ms=\(p95Milliseconds)")
    #if !DEBUG
    #expect(p95 < 0.05, "Release main-actor response P95 was \(p95) seconds")
    #endif
}

private final class CountingLocalPortSnapshotProvider: LocalPortSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var calls = 0

    init(output: String) {
        self.output = output
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func snapshot() throws -> String {
        lock.withLock { calls += 1 }
        return output
    }
}

private struct FailingLocalPortSnapshotProvider: LocalPortSnapshotProviding {
    func snapshot() throws -> String {
        throw LocalPortRecommendationError.snapshotFailed
    }
}

private struct DelayedLocalPortSnapshotProvider: LocalPortSnapshotProviding {
    let delay: TimeInterval

    func snapshot() throws -> String {
        Thread.sleep(forTimeInterval: delay)
        return ""
    }
}

private struct CancellationAwareLocalPortSnapshotProvider: LocalPortSnapshotProviding {
    let onStart: @Sendable () -> Void

    func snapshot() throws -> String {
        onStart()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            guard !Task.isCancelled else { throw CancellationError() }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return ""
    }
}

private func recommendationDraft(port: String) -> TunnelDraft {
    var draft = TunnelDraft()
    draft.name = "Draft"
    draft.sshHost = "example-host"
    draft.localHost = "127.0.0.1"
    draft.localPort = port
    draft.remoteHost = "example-service"
    draft.remotePort = "80"
    return draft
}

private func recommendationTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-port-recommendation-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func recommendationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
