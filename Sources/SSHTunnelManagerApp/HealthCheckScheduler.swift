import Foundation

struct ScheduledHealthCheckTarget: Equatable, Sendable {
    let request: HealthProbeRequest

    var key: RuleHealthCheckKey { request.key }
    var interval: TimeInterval { request.configuration.interval }
}

struct HealthCheckSchedule: Sendable {
    private struct Entry: Sendable {
        var target: ScheduledHealthCheckTarget
        var dueAt: TimeInterval
        var sequence: UInt64
    }

    private var entries: [RuleHealthCheckKey: Entry] = [:]
    private var nextSequence: UInt64 = 0

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    mutating func updateTargets(
        _ targets: [ScheduledHealthCheckTarget],
        now: TimeInterval
    ) {
        var incoming: [RuleHealthCheckKey: ScheduledHealthCheckTarget] = [:]
        var normalizedTargets: [ScheduledHealthCheckTarget] = []
        for target in targets where incoming[target.key] == nil {
            incoming[target.key] = target
            normalizedTargets.append(target)
        }
        entries = entries.filter { incoming[$0.key] != nil }
        for target in normalizedTargets {
            if let existing = entries[target.key], existing.target == target {
                continue
            }
            entries[target.key] = Entry(
                target: target,
                dueAt: now,
                sequence: takeSequence()
            )
        }
    }

    mutating func takeDueTargets(
        now: TimeInterval,
        excluding activeKeys: Set<RuleHealthCheckKey>,
        limit: Int
    ) -> [ScheduledHealthCheckTarget] {
        guard limit > 0 else { return [] }
        return entries.values
            .filter { $0.dueAt <= now && !activeKeys.contains($0.target.key) }
            .sorted {
                if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
                return $0.sequence < $1.sequence
            }
            .prefix(limit)
            .map(\.target)
    }

    mutating func recordCompletion(
        of target: ScheduledHealthCheckTarget,
        now: TimeInterval
    ) {
        guard var entry = entries[target.key], entry.target == target else { return }
        entry.dueAt = now + target.interval
        entry.sequence = takeSequence()
        entries[target.key] = entry
    }

    mutating func staggerAll(now: TimeInterval, window: TimeInterval) {
        guard window > 0 else {
            for key in Array(entries.keys) {
                guard var entry = entries[key] else { continue }
                entry.dueAt = now
                entry.sequence = takeSequence()
                entries[key] = entry
            }
            return
        }
        for key in Array(entries.keys) {
            guard var entry = entries[key] else { continue }
            entry.dueAt = now + Self.jitter(for: key, window: window)
            entry.sequence = takeSequence()
            entries[key] = entry
        }
    }

    func target(for key: RuleHealthCheckKey) -> ScheduledHealthCheckTarget? {
        entries[key]?.target
    }

    func nextDueDate(excluding activeKeys: Set<RuleHealthCheckKey>) -> TimeInterval? {
        entries.values
            .filter { !activeKeys.contains($0.target.key) }
            .map(\.dueAt)
            .min()
    }

    private mutating func takeSequence() -> UInt64 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private static func jitter(
        for key: RuleHealthCheckKey,
        window: TimeInterval
    ) -> TimeInterval {
        let scalarTotal = (key.tunnelID.uuidString + key.ruleID.uuidString)
            .unicodeScalars
            .reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
        return Double(scalarTotal % 1_000) / 1_000 * window
    }
}

struct HealthCheckSchedulerClock: Sendable {
    let now: @Sendable () -> TimeInterval
    let wallNow: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async throws -> Void

    static let live = Self(
        now: { ProcessInfo.processInfo.systemUptime },
        wallNow: Date.init,
        sleep: { duration in
            try await Task.sleep(for: .seconds(max(0, duration)))
        }
    )
}

@MainActor
final class HealthCheckScheduler {
    static let maximumConcurrentProbes = 8
    static let resumeStaggerWindow: TimeInterval = 0.9

    private struct ActiveProbe {
        let target: ScheduledHealthCheckTarget
        let task: Task<Void, Never>
    }

    private let prober: any HealthProbing
    private let clock: HealthCheckSchedulerClock
    private var schedule = HealthCheckSchedule()
    private var active: [UUID: ActiveProbe] = [:]
    private var wakeTask: Task<Void, Never>?
    private(set) var isSuspended = false

    var onResult: ((ScheduledHealthCheckTarget, HealthProbeResult, Date) -> Void)?

    var activeProbeCount: Int { active.count }
    var scheduledTargetCount: Int { schedule.count }

    init(
        prober: any HealthProbing = SystemHealthProber(),
        clock: HealthCheckSchedulerClock = .live
    ) {
        self.prober = prober
        self.clock = clock
    }

    func updateTargets(_ targets: [ScheduledHealthCheckTarget]) {
        var incoming: [RuleHealthCheckKey: ScheduledHealthCheckTarget] = [:]
        for target in targets where incoming[target.key] == nil {
            incoming[target.key] = target
        }
        for value in active.values where incoming[value.target.key] != value.target {
            value.task.cancel()
        }
        schedule.updateTargets(targets, now: clock.now())
        pump()
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        wakeTask?.cancel()
        wakeTask = nil
        if suspended {
            for value in active.values { value.task.cancel() }
        } else {
            schedule.staggerAll(
                now: clock.now(),
                window: Self.resumeStaggerWindow
            )
            pump()
        }
    }

    func shutdown() {
        isSuspended = true
        wakeTask?.cancel()
        wakeTask = nil
        for value in active.values { value.task.cancel() }
        schedule.updateTargets([], now: clock.now())
        onResult = nil
    }

    private func pump() {
        guard !isSuspended else { return }
        wakeTask?.cancel()
        wakeTask = nil
        let activeKeys = Set(active.values.map(\.target.key))
        let availableSlots = Self.maximumConcurrentProbes - active.count
        let dueTargets = schedule.takeDueTargets(
            now: clock.now(),
            excluding: activeKeys,
            limit: availableSlots
        )
        for target in dueTargets {
            start(target)
        }
        scheduleNextWakeIfNeeded()
    }

    private func start(_ target: ScheduledHealthCheckTarget) {
        let token = UUID()
        let prober = self.prober
        let task = Task { [weak self] in
            let result = await prober.probe(target.request)
            let wasCancelled = Task.isCancelled || result == .failure(.cancelled)
            guard let self else { return }
            self.complete(
                token: token,
                target: target,
                result: result,
                wasCancelled: wasCancelled
            )
        }
        active[token] = ActiveProbe(target: target, task: task)
    }

    private func complete(
        token: UUID,
        target: ScheduledHealthCheckTarget,
        result: HealthProbeResult,
        wasCancelled: Bool
    ) {
        active.removeValue(forKey: token)
        if !wasCancelled,
           !isSuspended,
           schedule.target(for: target.key) == target {
            schedule.recordCompletion(of: target, now: clock.now())
            onResult?(target, result, clock.wallNow())
        }
        pump()
    }

    private func scheduleNextWakeIfNeeded() {
        guard !isSuspended, active.count < Self.maximumConcurrentProbes else { return }
        let activeKeys = Set(active.values.map(\.target.key))
        guard let nextDue = schedule.nextDueDate(excluding: activeKeys) else { return }
        let delay = max(0, nextDue - clock.now())
        let sleep = clock.sleep
        wakeTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.wakeTask = nil
            self.pump()
        }
    }
}
