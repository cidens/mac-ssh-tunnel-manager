import Foundation
import Darwin
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@Test func ruleHealthStateRequiresThreeFailuresAndOneSuccessRecovers() {
    var state = RuleHealthCheckRuntimeState()
    let started = Date(timeIntervalSince1970: 1_000)

    state.record(.failure(.connectionRefused), at: started)
    state.record(.failure(.timeout), at: started.addingTimeInterval(1))
    #expect(state.phase == .waiting)
    #expect(state.consecutiveFailures == 2)

    state.record(.failure(.protocolError), at: started.addingTimeInterval(2))
    #expect(state.phase == .unhealthy)
    #expect(state.failureCategory == .protocolError)

    state.record(.success, at: started.addingTimeInterval(3))
    #expect(state.phase == .healthy)
    #expect(state.consecutiveFailures == 0)
    #expect(state.failureCategory == nil)

    state.record(.failure(.cancelled), at: started.addingTimeInterval(4))
    #expect(state.lastCheckedAt == started.addingTimeInterval(3))
    #expect(state.phase == .healthy)
}

@Test func healthSchedulePreservesFairOrderAndStaggersResume() {
    let targets = (0..<100).map(healthCheckTarget(index:))
    var schedule = HealthCheckSchedule()
    schedule.updateTargets(targets, now: 0)
    var received: [RuleHealthCheckKey] = []

    while received.count < targets.count {
        let batch = schedule.takeDueTargets(now: 0, excluding: [], limit: 8)
        #expect(!batch.isEmpty)
        #expect(batch.count <= 8)
        received.append(contentsOf: batch.map(\.key))
        for target in batch {
            schedule.recordCompletion(of: target, now: 0)
        }
    }

    #expect(received == targets.map(\.key))
    schedule.staggerAll(now: 100, window: 0.9)
    #expect(schedule.takeDueTargets(now: 99.999, excluding: [], limit: 100).isEmpty)
    #expect(schedule.takeDueTargets(now: 100.9, excluding: [], limit: 100).count == 100)
}

@Test func duplicateHealthTargetsDoNotCrashOrCreateDuplicateTasks() {
    let target = healthCheckTarget(index: 0)
    var schedule = HealthCheckSchedule()

    schedule.updateTargets([target, target], now: 0)

    #expect(schedule.count == 1)
    #expect(schedule.takeDueTargets(now: 0, excluding: [], limit: 8) == [target])
}

@Test func aggregatingMaximumDisabledHealthCheckDataStaysWithinBudget() {
    let groups = (0..<1_000).map { groupIndex in
        (0..<TunnelConfig.maximumRuleCount).map { ruleIndex in
            TunnelForwardRule(
                mode: .localForward,
                localHost: "127.0.0.1",
                localPort: 10_000 + ((groupIndex + ruleIndex) % 50_000),
                remoteHost: "localhost",
                remotePort: 80
            )
        }
    }
    for _ in 0..<5 {
        for rules in groups {
            _ = TunnelManager.healthAggregatePhase(rules: rules, states: [:])
        }
    }
    var durations: [TimeInterval] = []
    for _ in 0..<30 {
        let started = ProcessInfo.processInfo.systemUptime
        for rules in groups {
            #expect(TunnelManager.healthAggregatePhase(rules: rules, states: [:]) == .notConfigured)
        }
        durations.append(ProcessInfo.processInfo.systemUptime - started)
    }
    durations.sort()
    let median = durations[durations.count / 2]
    let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
    print(String(
        format: "health-disabled-aggregation groups=1000 rules_per_group=20 samples=30 median_ms=%.3f p95_ms=%.3f",
        median * 1_000,
        p95 * 1_000
    ))
    #expect(p95 < 0.1, "20,000 disabled-rule aggregations P95 was \(p95) seconds")
}

@MainActor
@Test func oneHundredDueHealthChecksMeetReleaseSchedulingBudget() async {
    var samples: [TimeInterval] = []
    for index in 0..<35 {
        let prober = ImmediateHealthProber()
        let scheduler = HealthCheckScheduler(prober: prober)
        let targets = (0..<100).map(healthCheckTarget(index:))
        let started = ProcessInfo.processInfo.systemUptime
        await withCheckedContinuation { continuation in
            var completed = 0
            scheduler.onResult = { _, _, _ in
                completed += 1
                if completed == targets.count {
                    continuation.resume()
                }
            }
            scheduler.updateTargets(targets)
        }
        let duration = ProcessInfo.processInfo.systemUptime - started
        scheduler.shutdown()
        if index >= 5 { samples.append(duration) }
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print(String(
        format: "health-due-scheduling targets=100 concurrency=8 samples=30 median_ms=%.3f p95_ms=%.3f",
        median * 1_000,
        p95 * 1_000
    ))
    #expect(p95 < 1, "100 due checks scheduling P95 was \(p95) seconds")
}

@MainActor
@Test func probeWorkDoesNotContinuouslyBlockTheMainThread() async throws {
    var samples: [TimeInterval] = []
    for index in 0..<35 {
        let scheduler = HealthCheckScheduler(prober: BlockingHealthProber())
        let started = ProcessInfo.processInfo.systemUptime
        let responseTime = await withCheckedContinuation { continuation in
            scheduler.updateTargets([healthCheckTarget(index: index)])
            DispatchQueue.main.async {
                continuation.resume(returning: ProcessInfo.processInfo.systemUptime - started)
            }
        }
        scheduler.shutdown()
        try await Task.sleep(for: .milliseconds(80))
        if index >= 5 { samples.append(responseTime) }
    }
    samples.sort()
    let median = samples[samples.count / 2]
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    print(String(
        format: "health-main-actor injected_probe_ms=75 samples=30 median_ms=%.3f p95_ms=%.3f",
        median * 1_000,
        p95 * 1_000
    ))
    #expect(p95 < 0.05, "Main-actor response P95 was \(p95) seconds")
}

@MainActor
@Test func longRunningHealthChecksStayWithinCPUAndMemoryBudgets() async throws {
    guard ProcessInfo.processInfo.environment["SSH_TUNNEL_MANAGER_LONG_PERFORMANCE"] == "1" else {
        return
    }
    let duration = TimeInterval(
        ProcessInfo.processInfo.environment["SSH_TUNNEL_MANAGER_PERFORMANCE_SECONDS"] ?? "600"
    ) ?? 600
    let prober = CountingHealthProber()
    let scheduler = HealthCheckScheduler(prober: prober)
    let targets = (0..<100).map { index in
        ScheduledHealthCheckTarget(request: HealthProbeRequest(
            key: RuleHealthCheckKey(tunnelID: UUID(), ruleID: UUID()),
            generation: 1,
            listenerHost: "127.0.0.1",
            listenerPort: 10_000 + index,
            configuration: TunnelHealthCheckConfiguration(kind: .tcp, interval: 30, timeout: 3)
        ))
    }
    let baselineRSS = currentResidentBytes()
    #expect(baselineRSS > 0, "Unable to read the process resident-memory size")
    var peakRSS = baselineRSS
    let baselineCPU = processCPUSeconds()
    let started = ProcessInfo.processInfo.systemUptime
    scheduler.updateTargets(targets)
    while ProcessInfo.processInfo.systemUptime - started < duration {
        peakRSS = max(peakRSS, currentResidentBytes())
        try await Task.sleep(for: .seconds(min(1, duration)))
    }
    scheduler.shutdown()
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    let cpuPercent = max(0, processCPUSeconds() - baselineCPU) / elapsed * 100
    let additionalRSS = max(0, Int64(peakRSS) - Int64(baselineRSS))
    let callCount = await prober.callCount
    print(String(
        format: "health-long-run targets=100 interval_s=30 duration_s=%.1f calls=%d avg_cpu_percent=%.3f additional_peak_rss_mib=%.3f",
        elapsed,
        callCount,
        cpuPercent,
        Double(additionalRSS) / 1_048_576
    ))
    #expect(callCount >= 100)
    #expect(cpuPercent < 2, "Average CPU was \(cpuPercent)%")
    #expect(additionalRSS < 20 * 1_048_576, "Additional peak RSS was \(additionalRSS) bytes")
}

@MainActor
@Test func schedulerNeverRunsMoreThanEightProbes() async throws {
    let prober = ConcurrencyHealthProber(delay: 0.01)
    let scheduler = HealthCheckScheduler(prober: prober)
    var results = 0
    scheduler.onResult = { _, _, _ in results += 1 }

    scheduler.updateTargets((0..<100).map(healthCheckTarget(index:)))
    try await waitForHealthCondition { results == 100 }

    #expect(await prober.maximumConcurrent == 8)
    #expect(await prober.callCount == 100)
    #expect(scheduler.activeProbeCount == 0)
    scheduler.shutdown()
}

@MainActor
@Test func removingTargetsCancelsActiveProbesAndReleasesSlots() async throws {
    let prober = CancellationHealthProber()
    let scheduler = HealthCheckScheduler(prober: prober)
    scheduler.updateTargets((0..<20).map(healthCheckTarget(index:)))
    try await waitForHealthCondition { await prober.activeCount == 8 }

    scheduler.updateTargets([])
    try await waitForHealthCondition { await prober.cancelledCount == 8 }

    #expect(scheduler.scheduledTargetCount == 0)
    #expect(scheduler.activeProbeCount == 0)
    scheduler.shutdown()
}

@MainActor
@Test func changedGenerationRejectsLateResultsBeforeStartingReplacement() async throws {
    let prober = ControlledHealthProber()
    let scheduler = HealthCheckScheduler(prober: prober)
    let key = RuleHealthCheckKey(tunnelID: UUID(), ruleID: UUID())
    let original = healthCheckTarget(key: key, generation: 1)
    let replacement = healthCheckTarget(key: key, generation: 2)
    var acceptedGenerations: [UInt64] = []
    scheduler.onResult = { target, _, _ in
        acceptedGenerations.append(target.request.generation)
    }

    scheduler.updateTargets([original])
    try await waitForHealthCondition { await prober.pendingGenerations == [1] }
    scheduler.updateTargets([replacement])
    #expect(scheduler.activeProbeCount == 1)

    await prober.complete(generation: 1, with: .success)
    try await waitForHealthCondition { await prober.pendingGenerations == [2] }
    #expect(acceptedGenerations.isEmpty)

    await prober.complete(generation: 2, with: .success)
    try await waitForHealthCondition { acceptedGenerations == [2] }
    #expect(scheduler.activeProbeCount == 0)
    scheduler.shutdown()
}

@MainActor
@Test func disabledHealthChecksCreateNoScheduledOrProbeTasks() async {
    let prober = ConcurrencyHealthProber(delay: 0)
    let scheduler = HealthCheckScheduler(prober: prober)

    scheduler.updateTargets([])
    await Task.yield()

    #expect(scheduler.scheduledTargetCount == 0)
    #expect(scheduler.activeProbeCount == 0)
    #expect(await prober.callCount == 0)
    scheduler.shutdown()
}

@MainActor
@Test func managerSchedulesOnlyEnabledChecksForReadyManagedProcesses() throws {
    var tunnel = TunnelConfig(
        name: "Managed", sshHost: "example", localHost: "127.0.0.1", localPort: 18_080,
        remoteHost: "web", remotePort: 80, openURL: nil
    )
    var rule = tunnel.rules[0]
    rule.healthCheck = TunnelHealthCheckConfiguration(kind: .tcp)
    tunnel.replaceRules([rule])
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["10"]
    try process.run()
    defer {
        process.terminate()
        process.waitUntilExit()
    }
    var runtime = TunnelRuntimeState()
    let generation = runtime.recovery.requestStart()
    let didStart = runtime.recovery.markRunning(generation: generation)
    #expect(didStart)
    runtime.process = process

    #expect(TunnelManager.healthCheckTargets(tunnels: [tunnel], runtimes: [tunnel.id: runtime]).isEmpty)
    runtime.isPortListening = true
    let targets = TunnelManager.healthCheckTargets(tunnels: [tunnel], runtimes: [tunnel.id: runtime])
    #expect(targets.count == 1)
    #expect(targets[0].request.generation == generation)
    #expect(targets[0].request.key.ruleID == rule.id)

    _ = runtime.recovery.requestStop(reason: .userRequested)
    #expect(TunnelManager.healthCheckTargets(tunnels: [tunnel], runtimes: [tunnel.id: runtime]).isEmpty)

    var disabledRule = rule
    disabledRule.isEnabled = false
    tunnel.replaceRules([disabledRule])
    let restartedGeneration = runtime.recovery.requestStart()
    let didRestart = runtime.recovery.markRunning(generation: restartedGeneration)
    #expect(didRestart)
    #expect(TunnelManager.healthCheckTargets(tunnels: [tunnel], runtimes: [tunnel.id: runtime]).isEmpty)
}

private actor ConcurrencyHealthProber: HealthProbing {
    private let delay: TimeInterval
    private var active = 0
    private(set) var maximumConcurrent = 0
    private(set) var callCount = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        active += 1
        callCount += 1
        maximumConcurrent = max(maximumConcurrent, active)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        active -= 1
        return Task.isCancelled ? .failure(.cancelled) : .success
    }
}

private struct ImmediateHealthProber: HealthProbing {
    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult { .success }
}

private struct BlockingHealthProber: HealthProbing {
    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        usleep(75_000)
        return .success
    }
}

private actor CountingHealthProber: HealthProbing {
    private(set) var callCount = 0

    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        callCount += 1
        return .success
    }
}

private actor CancellationHealthProber: HealthProbing {
    private(set) var activeCount = 0
    private(set) var cancelledCount = 0

    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        activeCount += 1
        defer { activeCount -= 1 }
        do {
            try await Task.sleep(for: .seconds(10))
            return .success
        } catch {
            cancelledCount += 1
            return .failure(.cancelled)
        }
    }
}

private actor ControlledHealthProber: HealthProbing {
    private var continuations: [UInt64: CheckedContinuation<HealthProbeResult, Never>] = [:]

    var pendingGenerations: [UInt64] {
        continuations.keys.sorted()
    }

    func probe(_ request: HealthProbeRequest) async -> HealthProbeResult {
        await withCheckedContinuation { continuation in
            continuations[request.generation] = continuation
        }
    }

    func complete(generation: UInt64, with result: HealthProbeResult) {
        continuations.removeValue(forKey: generation)?.resume(returning: result)
    }
}

private func healthCheckTarget(index: Int) -> ScheduledHealthCheckTarget {
    ScheduledHealthCheckTarget(request: HealthProbeRequest(
        key: RuleHealthCheckKey(tunnelID: UUID(), ruleID: UUID()),
        generation: 1,
        listenerHost: "127.0.0.1",
        listenerPort: 10_000 + index,
        configuration: TunnelHealthCheckConfiguration(kind: .tcp)
    ))
}

private func healthCheckTarget(
    key: RuleHealthCheckKey,
    generation: UInt64
) -> ScheduledHealthCheckTarget {
    ScheduledHealthCheckTarget(request: HealthProbeRequest(
        key: key,
        generation: generation,
        listenerHost: "127.0.0.1",
        listenerPort: 10_000,
        configuration: TunnelHealthCheckConfiguration(kind: .tcp)
    ))
}

private func waitForHealthCondition(
    _ condition: @escaping @MainActor () async -> Bool
) async throws {
    for _ in 0..<500 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for health-check condition")
}

private func processCPUSeconds() -> TimeInterval {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        + TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
}

private func currentResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                rebound,
                &count
            )
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
