import Foundation
import SSHTunnelCore

enum TagBatchAction: String, Equatable, Sendable {
    case start
    case stop
}

enum TagBatchOutcomeKind: String, Equatable, Sendable {
    case started
    case stopped
    case skipped
    case failed
}

struct TagBatchMemberOutcome: Equatable, Identifiable, Sendable {
    let id: TunnelConfig.ID
    let name: String
    let kind: TagBatchOutcomeKind
    let reason: String?
}

struct TagBatchResult: Equatable, Sendable {
    let action: TagBatchAction
    let tag: String
    let outcomes: [TagBatchMemberOutcome]

    var startedCount: Int { count(.started) }
    var stoppedCount: Int { count(.stopped) }
    var skippedCount: Int { count(.skipped) }
    var failedCount: Int { count(.failed) }

    var issues: [TagBatchMemberOutcome] {
        outcomes.filter { $0.kind == .skipped || $0.kind == .failed }
    }

    private func count(_ kind: TagBatchOutcomeKind) -> Int {
        outcomes.count { $0.kind == kind }
    }
}

struct TagBatchOperationState: Equatable, Identifiable, Sendable {
    let id: UUID
    let tag: String
    let action: TagBatchAction
    let totalCount: Int
    let result: TagBatchResult?

    var isRunning: Bool { result == nil }

    static func running(tag: String, action: TagBatchAction, totalCount: Int) -> Self {
        Self(id: UUID(), tag: tag, action: action, totalCount: totalCount, result: nil)
    }

    func completed(with result: TagBatchResult) -> Self {
        Self(id: id, tag: tag, action: action, totalCount: totalCount, result: result)
    }
}

struct TagGroupSnapshot: Equatable, Sendable {
    let tag: String
    let memberIDs: [TunnelConfig.ID]
    let runningCount: Int
    let pendingCount: Int
    let failedCount: Int
    let stoppedCount: Int

    var totalCount: Int { memberIDs.count }

    init(
        tag: String,
        tunnels: [TunnelConfig],
        status: (TunnelConfig) -> TunnelRuntimeStatus
    ) {
        let key = Self.comparisonKey(tag)
        let members = tunnels
            .filter { tunnel in
                tunnel.tags.contains { Self.comparisonKey($0) == key }
            }
            .sorted { left, right in
                let leftOrder = left.manualOrder ?? Int.max
                let rightOrder = right.manualOrder ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }

        var running = 0
        var pending = 0
        var failed = 0
        var stopped = 0
        for tunnel in members {
            switch status(tunnel) {
            case .running, .portListening:
                running += 1
            case .connecting, .waitingForNetwork, .waitingToReconnect:
                pending += 1
            case .failed, .externalListening:
                failed += 1
            case .stopped:
                stopped += 1
            }
        }

        self.tag = tag
        memberIDs = members.map(\.id)
        runningCount = running
        pendingCount = pending
        failedCount = failed
        stoppedCount = stopped
    }

    static func comparisonKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

enum TagBatchSkipReason: Equatable, Sendable {
    case alreadyRequested
    case alreadyStopped
    case missing
    case noEnabledRules
    case riskConfirmationRequired
    case preflightFailed(String)
    case changedDuringPreflight
    case stoppedDuringBatch
    case cancelled

    func displayText(language: String? = nil) -> String {
        switch self {
        case .alreadyRequested:
            return AppStrings.string("tagBatch.reason.alreadyRequested", language: language)
        case .alreadyStopped:
            return AppStrings.string("tagBatch.reason.alreadyStopped", language: language)
        case .missing:
            return AppStrings.string("tagBatch.reason.missing", language: language)
        case .noEnabledRules:
            return AppStrings.string("tagBatch.reason.noEnabledRules", language: language)
        case .riskConfirmationRequired:
            return AppStrings.string("tagBatch.reason.riskConfirmation", language: language)
        case .preflightFailed(let message):
            return AppStrings.format("tagBatch.reason.preflight", language: language, message)
        case .changedDuringPreflight:
            return AppStrings.string("tagBatch.reason.changed", language: language)
        case .stoppedDuringBatch:
            return AppStrings.string("tagBatch.reason.stopped", language: language)
        case .cancelled:
            return AppStrings.string("tagBatch.reason.cancelled", language: language)
        }
    }
}

enum TagBatchPreflightDecision: Equatable, Sendable {
    case eligible
    case skipped(TagBatchSkipReason)
}

struct TagBatchPreflightContext: Sendable {
    let configuredListeners: TagBatchConfiguredListenerIndex
    let systemListeners: LocalPortOccupancyIndex
    let snapshotError: String?

    static let empty = Self(
        configuredListeners: TagBatchConfiguredListenerIndex(tunnels: []),
        systemListeners: LocalPortOccupancyIndex(endpoints: [LocalPortEndpoint]()),
        snapshotError: nil
    )
}

struct TagBatchConfiguredListenerIndex: Sendable {
    private struct Listener: Sendable {
        let owner: TunnelConfig.ID
        let host: String
    }

    private struct PortOccupancy: Sendable {
        let first: Listener
        var additional: [Listener] = []

        mutating func append(_ listener: Listener) {
            additional.append(listener)
        }

        func containsOtherOwner(
            overlapping requestedHost: String,
            excluding owner: TunnelConfig.ID
        ) -> Bool {
            if first.owner != owner,
               TagBatchConfiguredListenerIndex.hostsOverlap(first.host, requestedHost) {
                return true
            }
            return additional.contains { listener in
                listener.owner != owner
                    && TagBatchConfiguredListenerIndex.hostsOverlap(
                        listener.host,
                        requestedHost
                    )
            }
        }
    }

    private let occupancies: [Int: PortOccupancy]
    let listenerCount: Int

    var isEmpty: Bool { listenerCount == 0 }

    init(tunnels: [TunnelConfig]) {
        var values: [Int: PortOccupancy] = [:]
        var count = 0
        values.reserveCapacity(tunnels.count * TunnelConfig.maximumRuleCount)
        for tunnel in tunnels {
            for rule in tunnel.effectiveRules where rule.isEnabled
                && (rule.mode == .localForward || rule.mode == .dynamicForward) {
                count += 1
                let listener = Listener(
                    owner: tunnel.id,
                    host: Self.normalizedHost(rule.localHost)
                )
                if values[rule.localPort] != nil {
                    values[rule.localPort]?.append(listener)
                } else {
                    values[rule.localPort] = PortOccupancy(first: listener)
                }
            }
        }
        occupancies = values
        listenerCount = count
    }

    func isOccupied(host: String, port: Int, excluding owner: TunnelConfig.ID) -> Bool {
        guard let occupancy = occupancies[port] else { return false }
        let requestedHost = Self.normalizedHost(host)
        return occupancy.containsOtherOwner(overlapping: requestedHost, excluding: owner)
    }

    private static func hostsOverlap(_ left: String, _ right: String) -> Bool {
        if isWildcardHost(left) || isWildcardHost(right) {
            return true
        }
        if left == "localhost" {
            return loopbackHosts.contains(right)
        }
        if right == "localhost" {
            return loopbackHosts.contains(left)
        }
        return left == right
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    private static func normalizedHost(_ host: String) -> String {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func isWildcardHost(_ host: String) -> Bool {
        ["*", "0.0.0.0", "::"].contains(host)
    }
}

protocol TagBatchStartPreflightChecking: Sendable {
    func prepare(tunnels: [TunnelConfig]) -> TagBatchPreflightContext
    func check(
        tunnel: TunnelConfig,
        context: TagBatchPreflightContext
    ) -> TagBatchPreflightDecision
}

struct SystemTagBatchStartPreflightChecker: TagBatchStartPreflightChecking {
    private let commandBuilder = SSHCommandBuilder()
    private let sshConfigResolver: any SSHConfigResolving
    private let localPortSnapshotProvider: any LocalPortSnapshotProviding

    init(
        sshConfigResolver: any SSHConfigResolving,
        localPortSnapshotProvider: any LocalPortSnapshotProviding
    ) {
        self.sshConfigResolver = sshConfigResolver
        self.localPortSnapshotProvider = localPortSnapshotProvider
    }

    func prepare(tunnels: [TunnelConfig]) -> TagBatchPreflightContext {
        let configuredListeners = TagBatchConfiguredListenerIndex(tunnels: tunnels)
        guard !configuredListeners.isEmpty else {
            return TagBatchPreflightContext(
                configuredListeners: configuredListeners,
                systemListeners: LocalPortOccupancyIndex(endpoints: [LocalPortEndpoint]()),
                snapshotError: nil
            )
        }
        do {
            let output = try localPortSnapshotProvider.snapshot()
            return TagBatchPreflightContext(
                configuredListeners: configuredListeners,
                systemListeners: LocalPortOccupancyIndex(
                    endpoints: PortStatusParser.listeningEndpoints(lsofOutput: output)
                ),
                snapshotError: nil
            )
        } catch {
            return TagBatchPreflightContext(
                configuredListeners: configuredListeners,
                systemListeners: LocalPortOccupancyIndex(endpoints: [LocalPortEndpoint]()),
                snapshotError: error.localizedDescription
            )
        }
    }

    func check(
        tunnel: TunnelConfig,
        context: TagBatchPreflightContext
    ) -> TagBatchPreflightDecision {
        guard !Task.isCancelled else { return .skipped(.cancelled) }

        do {
            try commandBuilder.validateForStart(tunnel)
        } catch TunnelValidationError.noEnabledRules {
            return .skipped(.noEnabledRules)
        } catch {
            return .skipped(.preflightFailed(error.localizedDescription))
        }

        if tunnel.mode == .sshConfig {
            return checkSSHConfigTunnel(tunnel)
        }

        if tunnel.effectiveRules.contains(where: { rule in
            rule.isEnabled
                && Self.isPotentiallyExposedBindHost(rule.listenerHost)
                && !rule.hasValidRiskConfirmation
        }) {
            return .skipped(.riskConfirmationRequired)
        }

        switch sshConfigResolver.resolveConfig(named: tunnel.sshHost, timeout: 10) {
        case .resolved(let output) where SSHConfigOutputParser.hasAnyForwardingDirective(output):
            return .skipped(.preflightFailed(
                TunnelValidationError.sshHostContainsForwardingDirectives(tunnel.sshHost)
                    .localizedDescription
            ))
        case .timedOut:
            return .skipped(.preflightFailed(
                TunnelValidationError.sshConfigValidationTimedOut(tunnel.sshHost, 10)
                    .localizedDescription
            ))
        case .resolved, .failed:
            break
        }

        let candidateEndpoints = tagBatchLocalListenerEndpoints(for: tunnel)
        if !candidateEndpoints.isEmpty {
            if let snapshotError = context.snapshotError {
                return .skipped(.preflightFailed(snapshotError))
            }
            for (index, endpoint) in candidateEndpoints.enumerated() {
                if candidateEndpoints.dropFirst(index + 1).contains(where: {
                    $0.port == endpoint.port
                        && LocalPortOccupancyIndex.hostsOverlap($0.host, endpoint.host)
                }) {
                    return .skipped(.preflightFailed(
                        TunnelValidationError.localPortOccupied(endpoint.host, endpoint.port)
                            .localizedDescription
                    ))
                }
            }

            if let conflict = candidateEndpoints.first(where: {
                context.configuredListeners.isOccupied(
                    host: $0.host,
                    port: $0.port,
                    excluding: tunnel.id
                ) || context.systemListeners.isOccupied(host: $0.host, port: $0.port)
            }) {
                return .skipped(.preflightFailed(
                    TunnelValidationError.localPortOccupied(conflict.host, conflict.port)
                        .localizedDescription
                ))
            }
        }

        return .eligible
    }

    private func checkSSHConfigTunnel(_ tunnel: TunnelConfig) -> TagBatchPreflightDecision {
        let name = tunnel.sshConfigName ?? ""
        switch sshConfigResolver.resolveConfig(named: name, timeout: 10) {
        case .resolved(let output):
            let directives = SSHConfigOutputParser.forwardingDirectives(output)
            guard !directives.isEmpty else {
                return .skipped(.preflightFailed(
                    TunnelValidationError.sshConfigMissingForwardingDirective(name)
                        .localizedDescription
                ))
            }
            if directives.contains(where: \.isPotentiallyExposed) {
                return .skipped(.riskConfirmationRequired)
            }
            return .eligible
        case .failed:
            return .skipped(.preflightFailed(
                TunnelValidationError.sshConfigMissingForwardingDirective(name)
                    .localizedDescription
            ))
        case .timedOut:
            return .skipped(.preflightFailed(
                TunnelValidationError.sshConfigValidationTimedOut(name, 10)
                    .localizedDescription
            ))
        }
    }

    private static func isPotentiallyExposedBindHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["127.0.0.1", "localhost", "::1", "[::1]"].contains(normalized)
    }
}

private func tagBatchLocalListenerEndpoints(for tunnel: TunnelConfig) -> [LocalPortEndpoint] {
    tunnel.effectiveRules.compactMap { rule in
        guard rule.isEnabled, rule.mode == .localForward || rule.mode == .dynamicForward else {
            return nil
        }
        return LocalPortEndpoint(host: rule.localHost, port: rule.localPort)
    }
}

enum TagBatchHookResult: Equatable, Sendable {
    case accepted
    case failed(String)
}

typealias TagBatchStartHook = @MainActor (TunnelConfig) -> TagBatchHookResult
typealias TagBatchStopHook = @MainActor (TunnelConfig) -> TagBatchHookResult

enum TagBatchDetachedWork {
    static func run<Output: Sendable>(
        _ operation: @escaping @Sendable () -> Output
    ) async -> Output {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }
}

enum BoundedTagBatchScheduler {
    static let maximumConcurrentTasks = 4

    static func run<Element: Sendable, Output: Sendable>(
        elements: [Element],
        maximumConcurrentTasks: Int = maximumConcurrentTasks,
        operation: @escaping @Sendable (Element) async -> Output
    ) async -> [Output] {
        guard !elements.isEmpty else { return [] }
        let limit = max(1, min(maximumConcurrentTasks, elements.count))
        return await withTaskGroup(of: (Int, Output).self, returning: [Output].self) { group in
            var nextIndex = 0
            var results = Array<Output?>(repeating: nil, count: elements.count)

            func addNext() {
                guard nextIndex < elements.count else { return }
                let index = nextIndex
                let element = elements[index]
                nextIndex += 1
                group.addTask {
                    (index, await operation(element))
                }
            }

            for _ in 0..<limit { addNext() }
            while let (index, result) = await group.next() {
                results[index] = result
                addNext()
            }
            return results.compactMap { $0 }
        }
    }
}
