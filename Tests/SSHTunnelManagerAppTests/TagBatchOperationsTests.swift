import Foundation
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@Test func tagGroupSnapshotMatchesCaseInsensitivelyAndConservesStatusCounts() {
    var first = tagBatchTunnel(name: "First", tag: "Production", order: 2)
    var second = tagBatchTunnel(name: "Second", tag: "production", order: 0)
    var third = tagBatchTunnel(name: "Third", tag: "PRODUCTION", order: 1)
    let unrelated = tagBatchTunnel(name: "Unrelated", tag: "Staging", order: 3)
    first.isFavorite = true
    second.isFavorite = false
    third.isFavorite = true
    let statuses: [TunnelConfig.ID: TunnelRuntimeStatus] = [
        first.id: .running,
        second.id: .waitingToReconnect,
        third.id: .failed,
    ]

    let snapshot = TagGroupSnapshot(
        tag: "PrOdUcTiOn",
        tunnels: [first, second, third, unrelated],
        status: { statuses[$0.id] ?? .stopped }
    )

    #expect(snapshot.memberIDs == [second.id, third.id, first.id])
    #expect(snapshot.totalCount == 3)
    #expect(snapshot.runningCount == 1)
    #expect(snapshot.pendingCount == 1)
    #expect(snapshot.failedCount == 1)
    #expect(snapshot.stoppedCount == 0)
    #expect(
        snapshot.runningCount + snapshot.pendingCount + snapshot.failedCount + snapshot.stoppedCount
            == snapshot.totalCount
    )
}

@Test func boundedTagBatchSchedulerPreservesOrderAndNeverExceedsFourTasks() async {
    let probe = TagBatchConcurrencyProbe()
    let inputs = Array(0..<100)

    let outputs = await BoundedTagBatchScheduler.run(elements: inputs) { value in
        await probe.begin()
        try? await Task.sleep(for: .milliseconds(2))
        await probe.end()
        return value
    }

    #expect(outputs == inputs)
    #expect(await probe.maximum == 4)
}

@MainActor
@Test func tagBatchStartTargetsEveryMemberAndLaunchesInManualOrder() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let first = tagBatchTunnel(name: "First", tag: "Production", order: 2)
    let second = tagBatchTunnel(name: "Second", tag: "production", order: 0)
    let third = tagBatchTunnel(name: "Third", tag: "Production", order: 1)
    var unrelated = tagBatchTunnel(name: "Unrelated", tag: "Staging", order: 3)
    unrelated.isFavorite = true
    try store.save([first, second, third, unrelated])
    var launchedNames: [String] = []
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(delays: [
            "Second": 0.03,
            "Third": 0.02,
            "First": 0.01,
        ]),
        tagBatchStartHook: { tunnel in
            launchedNames.append(tunnel.name)
            return .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }

    let visibleFavorites = manager.displayedTunnels(
        searchQuery: "does-not-match",
        selectedTag: "Production",
        favoritesOnly: true,
        sort: .name
    )
    #expect(visibleFavorites.isEmpty)

    manager.startAllTunnels(withTag: "PRODUCTION")
    manager.startAllTunnels(withTag: "production")
    let result = try await tagBatchResult(from: manager)

    #expect(launchedNames == ["Second", "Third", "First"])
    #expect(result.startedCount == 3)
    #expect(result.skippedCount == 0)
    #expect(result.failedCount == 0)
    #expect(result.outcomes.map(\.id) == [second.id, third.id, first.id])
}

@MainActor
@Test func singleStopPreventsAPreflightedBatchMemberFromLaunching() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = tagBatchTunnel(name: "Stopped", tag: "Production", order: 0)
    try store.save([tunnel])
    var launchedNames: [String] = []
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(defaultDelay: 0.075),
        tagBatchStartHook: { tunnel in
            launchedNames.append(tunnel.name)
            return .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAllTunnels(withTag: "Production")
    try await Task.sleep(for: .milliseconds(10))
    manager.stop(try #require(manager.tunnels.first))
    let result = try await tagBatchResult(from: manager)

    #expect(launchedNames.isEmpty)
    #expect(result.startedCount == 0)
    #expect(result.skippedCount == 1)
    #expect(result.outcomes.first?.reason?.contains("停止") == true
        || result.outcomes.first?.reason?.contains("Stopped") == true)
}

@MainActor
@Test func deletingAMemberDuringPreflightSkipsItsStaleReference() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnel = tagBatchTunnel(name: "Deleted", tag: "Production", order: 0)
    try store.save([tunnel])
    var launchedNames: [String] = []
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(defaultDelay: 0.075),
        tagBatchStartHook: { tunnel in
            launchedNames.append(tunnel.name)
            return .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAllTunnels(withTag: "Production")
    try await Task.sleep(for: .milliseconds(10))
    manager.deleteTunnel(try #require(manager.tunnels.first))
    let result = try await tagBatchResult(from: manager)

    #expect(launchedNames.isEmpty)
    #expect(result.skippedCount == 1)
    #expect(result.outcomes.first?.reason?.contains("不存在") == true
        || result.outcomes.first?.reason?.contains("no longer exists") == true)
}

@MainActor
@Test func tagBatchStartContinuesAfterSkippedAndFailedMembers() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let good = tagBatchTunnel(name: "Good", tag: "Production", order: 0)
    let risky = tagBatchTunnel(name: "Risky", tag: "Production", order: 1)
    let rejected = tagBatchTunnel(name: "Rejected", tag: "Production", order: 2)
    let later = tagBatchTunnel(name: "Later", tag: "Production", order: 3)
    try store.save([good, risky, rejected, later])
    var launchedNames: [String] = []
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(decisions: [
            "Risky": .skipped(.riskConfirmationRequired),
        ]),
        tagBatchStartHook: { tunnel in
            launchedNames.append(tunnel.name)
            return tunnel.name == "Rejected" ? .failed("Injected launch failure") : .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAllTunnels(withTag: "Production")
    let result = try await tagBatchResult(from: manager)

    #expect(launchedNames == ["Good", "Rejected", "Later"])
    #expect(result.startedCount == 2)
    #expect(result.skippedCount == 1)
    #expect(result.failedCount == 1)
    #expect(result.issues.map(\.name) == ["Risky", "Rejected"])
    #expect(result.issues.first?.reason?.contains("风险") == true
        || result.issues.first?.reason?.contains("risk") == true)
}

@MainActor
@Test func tagBatchStopCancelsStartsThatHaveNotLaunched() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnels = (0..<6).map {
        tagBatchTunnel(name: "Tunnel \($0)", tag: "Production", order: $0)
    }
    try store.save(tunnels)
    var launchedNames: [String] = []
    var stoppedNames: [String] = []
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(defaultDelay: 0.075),
        tagBatchStartHook: { tunnel in
            launchedNames.append(tunnel.name)
            return .accepted
        },
        tagBatchStopHook: { tunnel in
            stoppedNames.append(tunnel.name)
            return .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }

    manager.startAllTunnels(withTag: "Production")
    try await Task.sleep(for: .milliseconds(10))
    manager.stopAllTunnels(withTag: "production")
    let result = try await tagBatchResult(from: manager)

    #expect(launchedNames.isEmpty)
    #expect(Set(stoppedNames) == Set(tunnels.map(\.name)))
    #expect(result.action == .stop)
    #expect(result.stoppedCount == tunnels.count)
    #expect(result.outcomes.map(\.name) == tunnels.map(\.name))
}

@Test func systemTagBatchPreflightUsesOneSnapshotAndProtectsRiskAndConflictBoundaries() {
    let snapshot = CountingTagBatchSnapshotProvider(output: """
    ssh 10 user 3u IPv4 0t0 TCP 127.0.0.1:18080 (LISTEN)
    """)
    let checker = SystemTagBatchStartPreflightChecker(
        sshConfigResolver: TagBatchSSHConfigResolver(),
        localPortSnapshotProvider: snapshot
    )
    let conflict = tagBatchLocalForward(name: "Conflict", host: "127.0.0.1", port: 18_080)
    let safe = tagBatchLocalForward(name: "Safe", host: "127.0.0.1", port: 18_081)
    let risky = tagBatchLocalForward(name: "Risky", host: "*", port: 18_082)
    var disabled = tagBatchLocalForward(name: "Disabled", host: "127.0.0.1", port: 18_083)
    disabled.replaceRules(disabled.effectiveRules.map { rule in
        var value = rule
        value.isEnabled = false
        return value
    })
    let tunnels = [conflict, safe, risky, disabled]
    let context = checker.prepare(tunnels: tunnels)

    #expect(checker.check(tunnel: conflict, context: context)
        != .eligible)
    #expect(checker.check(tunnel: safe, context: context)
        == .eligible)
    #expect(checker.check(tunnel: risky, context: context)
        == .skipped(.riskConfirmationRequired))
    #expect(checker.check(tunnel: disabled, context: context)
        == .skipped(.noEnabledRules))
    #expect(snapshot.callCount == 1)
}

@Test func configuredListenerIndexExcludesOnlyTheCurrentTunnelOwner() {
    let first = tagBatchLocalForward(name: "First", host: "127.0.0.1", port: 18_080)
    let second = tagBatchLocalForward(name: "Second", host: "localhost", port: 18_080)
    let wildcard = tagBatchLocalForward(name: "Wildcard", host: "0.0.0.0", port: 18_081)

    let onlyFirst = TagBatchConfiguredListenerIndex(tunnels: [first])
    #expect(!onlyFirst.isOccupied(host: "localhost", port: 18_080, excluding: first.id))

    let loopbackConflict = TagBatchConfiguredListenerIndex(tunnels: [first, second])
    #expect(loopbackConflict.isOccupied(host: "127.0.0.1", port: 18_080, excluding: first.id))
    #expect(loopbackConflict.isOccupied(host: "[::1]", port: 18_080, excluding: first.id))

    let wildcardConflict = TagBatchConfiguredListenerIndex(tunnels: [first, wildcard])
    #expect(wildcardConflict.isOccupied(host: "192.168.1.10", port: 18_081, excluding: first.id))
    #expect(!wildcardConflict.isOccupied(host: "127.0.0.1", port: 18_080, excluding: first.id))
}

@Test func detachedTagBatchWorkPropagatesParentCancellation() async {
    let probe = TagBatchCancellationProbe()
    let parent = Task {
        await TagBatchDetachedWork.run {
            probe.waitForCancellation()
        }
    }

    #expect(probe.waitUntilStarted())
    parent.cancel()
    #expect(await parent.value)
}

@Test func largeTagGroupAggregationMeetsReleasePerformanceBudget() {
    let tunnels = (0..<1_000).map { index -> TunnelConfig in
        var tunnel = tagBatchTunnel(name: "Tunnel \(index)", tag: "tag-0", order: index)
        tunnel.tags = (0..<10).map { "tag-\($0)" }
        return tunnel
    }
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let snapshot = TagGroupSnapshot(tag: "TAG-9", tunnels: tunnels) { _ in .stopped }
        let elapsed = tagBatchSeconds(started.duration(to: .now))
        #expect(snapshot.totalCount == 1_000)
        #expect(snapshot.stoppedCount == 1_000)
        if iteration >= 5 { samples.append(elapsed) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-group-summary tunnels=1000 tags_each=10 samples=30 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #if !DEBUG
    #expect(p95 < 0.1, "Release tag summary P95 was \(p95) seconds")
    #endif
}

@Test func oneHundredMemberSchedulerMeetsReleasePerformanceBudget() async {
    var samples: [Double] = []
    let inputs = Array(0..<100)

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let outputs = await BoundedTagBatchScheduler.run(elements: inputs) { $0 }
        let elapsed = tagBatchSeconds(started.duration(to: .now))
        #expect(outputs == inputs)
        if iteration >= 5 { samples.append(elapsed) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-batch-scheduler members=100 samples=30 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #if !DEBUG
    #expect(p95 < 0.2, "Release batch scheduler P95 was \(p95) seconds")
    #endif
}

@Test func largeSystemTagBatchPreflightMeetsReleasePerformanceBudget() {
    let tunnels = (0..<1_000).map { tagBatchLargeConnectionGroup(index: $0) }
    let snapshot = CountingTagBatchSnapshotProvider(output: "")
    let checker = SystemTagBatchStartPreflightChecker(
        sshConfigResolver: TagBatchSSHConfigResolver(),
        localPortSnapshotProvider: snapshot
    )
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let context = checker.prepare(tunnels: tunnels)
        #expect(context.configuredListeners.listenerCount == 20_000)
        for tunnel in tunnels.prefix(100) {
            #expect(checker.check(tunnel: tunnel, context: context) == .eligible)
        }
        let elapsed = tagBatchSeconds(started.duration(to: .now))
        if iteration >= 5 { samples.append(elapsed) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-batch-preflight-index endpoints=20000 queries=100 samples=30 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #expect(snapshot.callCount == 35)
    #if !DEBUG
    #expect(p95 < 0.1, "Release indexed preflight P95 was \(p95) seconds")
    #endif
}

@Test func maximumSamePortListenerIndexAvoidsCopyOnWriteRegression() {
    let tunnels = (0..<1_000).map { index in
        tagBatchLargeConnectionGroup(index: index, sharedPort: 18_080)
    }
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let index = TagBatchConfiguredListenerIndex(tunnels: tunnels)
        let elapsed = tagBatchSeconds(started.duration(to: .now))
        #expect(index.listenerCount == 20_000)
        #expect(index.isOccupied(
            host: "127.0.0.1",
            port: 18_080,
            excluding: tunnels[0].id
        ))
        if iteration >= 5 { samples.append(elapsed) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-batch-preflight-shared-port endpoints=20000 samples=30 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #if !DEBUG
    #expect(p95 < 0.1, "Release shared-port preflight index P95 was \(p95) seconds")
    #endif
}

@MainActor
@Test func oneHundredMemberBatchRequestMeetsReleasePerformanceBudget() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let tunnels = (0..<100).map {
        tagBatchTunnel(name: "Tunnel \($0)", tag: "Production", order: $0)
    }
    try store.save(tunnels)
    var launchCount = 0
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(),
        tagBatchStartHook: { _ in
            launchCount += 1
            return .accepted
        }
    )
    defer { manager.prepareForApplicationTermination() }
    var samples: [Double] = []

    for iteration in 0..<35 {
        let previousLaunchCount = launchCount
        let started = ContinuousClock.now
        manager.startAllTunnels(withTag: "Production")
        let result = try await tagBatchResult(from: manager)
        let elapsed = tagBatchSeconds(started.duration(to: .now))
        #expect(result.startedCount == 100)
        #expect(launchCount - previousLaunchCount == 100)
        manager.clearTagBatchResult()
        if iteration >= 5 { samples.append(elapsed) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-batch-manager members=100 samples=30 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #if !DEBUG
    #expect(p95 < 0.2, "Release 100-member batch request P95 was \(p95) seconds")
    #endif
}

@MainActor
@Test func slowTagBatchPreflightDoesNotBlockTheMainActor() async throws {
    let directory = try tagBatchTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    try store.save([tagBatchTunnel(name: "Slow", tag: "Production", order: 0)])
    let manager = TunnelManager(
        store: store,
        sshConfigResolver: TagBatchSSHConfigResolver(),
        tagBatchPreflightChecker: StubTagBatchPreflightChecker(defaultDelay: 0.075),
        tagBatchStartHook: { _ in .accepted }
    )
    defer { manager.prepareForApplicationTermination() }
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        manager.startAllTunnels(withTag: "Production")
        try await Task.sleep(for: .milliseconds(5))
        let responseDelay = tagBatchSeconds(started.duration(to: .now))
        _ = try await tagBatchResult(from: manager)
        manager.clearTagBatchResult()
        if iteration >= 5 { samples.append(responseDelay) }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print("tag-batch-main-actor samples=30 injected_preflight_ms=75 median_ms=\(median * 1_000) p95_ms=\(p95 * 1_000)")
    #if !DEBUG
    #expect(p95 < 0.05, "Release tag batch main-actor response P95 was \(p95) seconds")
    #endif
}

private struct StubTagBatchPreflightChecker: TagBatchStartPreflightChecking {
    let decisions: [String: TagBatchPreflightDecision]
    let delays: [String: TimeInterval]
    let defaultDelay: TimeInterval

    init(
        decisions: [String: TagBatchPreflightDecision] = [:],
        delays: [String: TimeInterval] = [:],
        defaultDelay: TimeInterval = 0
    ) {
        self.decisions = decisions
        self.delays = delays
        self.defaultDelay = defaultDelay
    }

    func prepare(tunnels: [TunnelConfig]) -> TagBatchPreflightContext { .empty }

    func check(
        tunnel: TunnelConfig,
        context: TagBatchPreflightContext
    ) -> TagBatchPreflightDecision {
        Thread.sleep(forTimeInterval: delays[tunnel.name] ?? defaultDelay)
        return Task.isCancelled ? .skipped(.cancelled) : decisions[tunnel.name] ?? .eligible
    }
}

private struct TagBatchSSHConfigResolver: SSHConfigResolving {
    func resolveConfig(named name: String, timeout: TimeInterval) -> SSHConfigResolution {
        .failed
    }
}

private final class CountingTagBatchSnapshotProvider: LocalPortSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let output: String
    private var calls = 0

    init(output: String) {
        self.output = output
    }

    var callCount: Int { lock.withLock { calls } }

    func snapshot() throws -> String {
        lock.withLock { calls += 1 }
        return output
    }
}

private actor TagBatchConcurrencyProbe {
    private var active = 0
    private(set) var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
    }
}

private final class TagBatchCancellationProbe: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 1) == .success
    }

    func waitForCancellation() -> Bool {
        started.signal()
        let deadline = Date().addingTimeInterval(1)
        while !Task.isCancelled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        return Task.isCancelled
    }
}

@MainActor
private func tagBatchResult(from manager: TunnelManager) async throws -> TagBatchResult {
    for _ in 0..<500 {
        if let result = manager.tagBatchOperation?.result { return result }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for tag batch operation")
    throw TagBatchTestError.timedOut
}

private enum TagBatchTestError: Error {
    case timedOut
}

private func tagBatchTunnel(name: String, tag: String, order: Int) -> TunnelConfig {
    var tunnel = TunnelConfig(name: name, sshConfigName: "alias-\(order)", openURL: nil)
    tunnel.tags = [tag]
    tunnel.manualOrder = order
    return tunnel
}

private func tagBatchLocalForward(name: String, host: String, port: Int) -> TunnelConfig {
    var tunnel = TunnelConfig(
        name: name,
        sshHost: "example-host",
        localHost: host,
        localPort: port,
        remoteHost: "localhost",
        remotePort: 8_080,
        openURL: nil
    )
    tunnel.tags = ["Production"]
    return tunnel
}

private func tagBatchLargeConnectionGroup(index: Int, sharedPort: Int? = nil) -> TunnelConfig {
    let firstPort = sharedPort ?? (10_000 + index * TunnelConfig.maximumRuleCount)
    var tunnel = tagBatchLocalForward(
        name: "Tunnel \(index)",
        host: "127.0.0.1",
        port: firstPort
    )
    tunnel.replaceRules((0..<TunnelConfig.maximumRuleCount).map { ruleIndex in
        TunnelForwardRule(
            mode: .localForward,
            localHost: "127.0.0.1",
            localPort: sharedPort ?? (firstPort + ruleIndex),
            remoteHost: "localhost",
            remotePort: 8_080
        )
    })
    return tunnel
}

private func tagBatchTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-tag-batch-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func tagBatchSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
