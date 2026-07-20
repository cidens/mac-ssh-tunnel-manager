import AppKit
import Foundation
import SSHTunnelCore

struct TunnelRuntimeState {
    var process: Process?
    var isPortListening = false
    var lastError = ""
    var stderrTail: StderrTailBuffer?
    var recovery = TunnelRecoveryState()
    var retryTask: Task<Void, Never>?
    var recoveryNotificationTask: Task<Void, Never>?
    var stableResetTask: Task<Void, Never>?
    var allowsRiskyRestart = false
    var statusChangedAt = Date()
    var lastExitCode: Int32?
    var nextRetryAt: Date?
    var errorCategory: TunnelFailureCategory?
    var notificationCycle = TunnelNotificationCycle()
    var localPortConflict: LocalPortEndpoint?
    var ruleHealthStates: [TunnelForwardRule.ID: RuleHealthCheckRuntimeState] = [:]
}

struct TunnelConnectionDetails {
    let statusChangedAt: Date
    let exitCode: Int32?
    let retryCount: Int
    let nextRetryAt: Date?
    let errorCategory: TunnelFailureCategory?
    let errorSummary: String
}

struct RuleHealthCheckDetails: Identifiable, Equatable {
    let id: TunnelForwardRule.ID
    let ruleNumber: Int
    let kind: TunnelHealthCheckKind
    let state: RuleHealthCheckRuntimeState
}

struct TunnelRiskWarning: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum TunnelSortOption: String, CaseIterable, Identifiable {
    case manual
    case name
    case status
    case lastUsed

    var id: String { rawValue }
}

private struct TunnelRiskConfirmationRequired: Error {
    let title: String
    let message: String

    init(title: String = AppStrings.riskyLocalBindTitle(), message: String) {
        self.title = title
        self.message = message
    }
}

private struct TunnelNameConflictError: LocalizedError {
    let name: String

    var errorDescription: String? {
        AppStrings.format("error.duplicateTunnelName", name)
    }
}

private enum TunnelStartTrigger {
    case manual
    case automatic
}

private enum SSHConfigForwardingStatus {
    case hasForwarding([SSHConfigForwardingDirective])
    case missingForwarding
    case timedOut
}

private enum SSHConfigForwardingDirectiveStatus {
    case hasForwardingDirective
    case noForwardingDirective
    case timedOut
}

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var tunnels: [TunnelConfig] = []
    @Published private(set) var runtimes: [TunnelConfig.ID: TunnelRuntimeState] = [:]
    @Published var addError = ""
    @Published var riskWarning: TunnelRiskWarning?
    @Published private(set) var validationPortConflict: LocalPortEndpoint?

    private let store: TunnelConfigStore
    private let sshConfigResolver: any SSHConfigResolving
    private let commandBuilder = SSHCommandBuilder()
    private let configurationTransfer = TunnelConfigurationTransfer()
    private var refreshTimer: Timer?
    private var statusRefreshTask: Task<Void, Never>?
    private var willTerminateObserver: NSObjectProtocol?
    private var pendingRiskOperation: (() -> Void)?
    private let recoveryMonitor: SystemRecoveryMonitor
    private let notificationSender: any ConnectionNotificationSending
    private let localPortSnapshotProvider: any LocalPortSnapshotProviding
    private let healthCheckScheduler: HealthCheckScheduler
    private var isNetworkAvailable = true
    private var isSystemSleeping = false

    init(
        store: TunnelConfigStore = TunnelManager.defaultStore(),
        sshConfigResolver: any SSHConfigResolving = SystemSSHConfigResolver(),
        recoveryMonitor: SystemRecoveryMonitor = SystemRecoveryMonitor(),
        notificationSender: any ConnectionNotificationSending = DisabledConnectionNotificationSender.shared,
        localPortSnapshotProvider: any LocalPortSnapshotProviding = SystemLocalPortSnapshotProvider(),
        healthProber: any HealthProbing = SystemHealthProber(),
        healthSchedulerClock: HealthCheckSchedulerClock = .live
    ) {
        self.store = store
        self.sshConfigResolver = sshConfigResolver
        self.recoveryMonitor = recoveryMonitor
        self.notificationSender = notificationSender
        self.localPortSnapshotProvider = localPortSnapshotProvider
        self.healthCheckScheduler = HealthCheckScheduler(
            prober: healthProber,
            clock: healthSchedulerClock
        )
        do {
            tunnels = try store.load()
            if tunnels.allSatisfy({ $0.manualOrder == nil }) {
                for index in tunnels.indices {
                    tunnels[index].manualOrder = index
                }
            } else {
                normalizeManualOrder()
            }
        } catch {
            addError = AppStrings.failedToLoadTunnels(error.localizedDescription)
        }

        healthCheckScheduler.onResult = { [weak self] target, result, date in
            self?.recordHealthCheckResult(target, result: result, at: date)
        }
        refreshStatuses()
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForApplicationTermination()
            }
        }
        recoveryMonitor.onNetworkAvailabilityChanged = { [weak self] isAvailable in
            self?.handleNetworkAvailabilityChanged(isAvailable)
        }
        recoveryMonitor.onSleep = { [weak self] in self?.handleSystemSleep() }
        recoveryMonitor.onWake = { [weak self] in self?.handleSystemWake() }
        recoveryMonitor.start()
    }

    var menuTitle: String {
        let running = tunnels.filter { isOperational(for: $0) }.count
        return AppStrings.menuTitle(runningCount: running)
    }

    var menuSystemImage: String {
        tunnels.contains { isOperational(for: $0) } ? "point.3.connected.trianglepath.dotted" : "circle.dotted"
    }

    var summary: TunnelSummary {
        TunnelSummary(statuses: tunnels.map { status(for: $0) })
    }

    static func defaultStore() -> TunnelConfigStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = base
            .appending(path: "ssh-tunnel-manager", directoryHint: .isDirectory)
            .appending(path: "tunnels.json")
        return TunnelConfigStore(configURL: url)
    }

    func status(for tunnel: TunnelConfig) -> TunnelRuntimeStatus {
        let runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        switch runtime.recovery.phase {
        case .connecting:
            return .connecting
        case .waitingForNetwork:
            return .waitingForNetwork
        case .waitingToReconnect:
            return .waitingToReconnect
        case .failed:
            return .failed
        case .stopped, .running:
            break
        }
        return TunnelRuntimeStatusResolver.status(
            isManagedProcessRunning: runtime.process?.isRunning == true,
            isPortListening: runtime.isPortListening,
            lastError: runtime.lastError
        )
    }

    func lastError(for tunnel: TunnelConfig) -> String {
        runtimes[tunnel.id]?.lastError ?? ""
    }

    func connectionDetails(for tunnel: TunnelConfig) -> TunnelConnectionDetails {
        let runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        return TunnelConnectionDetails(
            statusChangedAt: runtime.statusChangedAt,
            exitCode: runtime.lastExitCode,
            retryCount: runtime.recovery.failureCount,
            nextRetryAt: runtime.nextRetryAt,
            errorCategory: runtime.errorCategory,
            errorSummary: runtime.lastError
        )
    }

    func healthAggregatePhase(for tunnel: TunnelConfig) -> TunnelHealthAggregatePhase {
        Self.healthAggregatePhase(
            rules: tunnel.effectiveRules,
            states: runtimes[tunnel.id]?.ruleHealthStates ?? [:]
        )
    }

    func healthCheckDetails(for tunnel: TunnelConfig) -> [RuleHealthCheckDetails] {
        let states = runtimes[tunnel.id]?.ruleHealthStates ?? [:]
        return tunnel.effectiveRules.enumerated().compactMap { index, rule in
            guard rule.isEnabled, let healthCheck = rule.healthCheck else { return nil }
            return RuleHealthCheckDetails(
                id: rule.id,
                ruleNumber: index + 1,
                kind: healthCheck.kind,
                state: states[rule.id] ?? RuleHealthCheckRuntimeState()
            )
        }
    }

    nonisolated static func healthAggregatePhase(
        rules: [TunnelForwardRule],
        states: [TunnelForwardRule.ID: RuleHealthCheckRuntimeState]
    ) -> TunnelHealthAggregatePhase {
        let configured = rules.filter { $0.isEnabled && $0.healthCheck != nil }
        guard !configured.isEmpty else { return .notConfigured }
        if configured.contains(where: { states[$0.id]?.phase == .unhealthy }) {
            return .unhealthy
        }
        if configured.allSatisfy({ states[$0.id]?.phase == .healthy }) {
            return .healthy
        }
        return .waiting
    }

    func copyDiagnostics(for tunnel: TunnelConfig) {
        let runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        let report = TunnelDiagnosticReport(
            appVersion: AppVersion.current,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            mode: tunnel.mode,
            status: status(for: tunnel),
            statusChangedAt: runtime.statusChangedAt,
            exitCode: runtime.lastExitCode,
            retryCount: runtime.recovery.failureCount,
            nextRetryAt: runtime.nextRetryAt,
            errorCategory: runtime.errorCategory
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
    }

    func isManagedProcessRunning(for tunnel: TunnelConfig) -> Bool {
        runtimes[tunnel.id]?.process?.isRunning == true
    }

    func isRunRequested(for tunnel: TunnelConfig) -> Bool {
        runtimes[tunnel.id]?.recovery.wantsToRun == true
    }

    func localPortConflict(for tunnel: TunnelConfig) -> LocalPortEndpoint? {
        runtimes[tunnel.id]?.localPortConflict
    }

    func clearValidationPortConflict() {
        validationPortConflict = nil
    }

    func recommendedLocalPort(
        for fingerprint: LocalPortRecommendationFingerprint,
        in draft: TunnelDraft,
        editingTunnelID: TunnelConfig.ID?
    ) async throws -> Int {
        guard let rule = draft.rules.first(where: { $0.id == fingerprint.ruleID }),
              rule.localPortRecommendationFingerprint == fingerprint else {
            throw LocalPortRecommendationError.unsupportedRule
        }
        do {
            try commandBuilder.validateLocalListenerHost(fingerprint.host)
        } catch {
            throw LocalPortRecommendationError.invalidListenerHost
        }

        let tunnelSnapshot = tunnels
        let draftEndpoints = draft.rules.compactMap { candidate -> LocalPortEndpoint? in
            guard candidate.id != fingerprint.ruleID,
                  candidate.mode == .localForward || candidate.mode == .dynamicForward,
                  let port = Int(candidate.localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            let host = candidate.localHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else { return nil }
            return LocalPortEndpoint(host: host, port: port)
        }
        let provider = localPortSnapshotProvider
        let currentPort = Int(fingerprint.portText)

        let task = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { throw CancellationError() }
            let storedEndpoints = tunnelSnapshot
                .filter { $0.id != editingTunnelID }
                .flatMap(Self.configuredLocalListenerEndpoints(for:))
            let output = try provider.snapshot()
            guard !Task.isCancelled else { throw CancellationError() }
            let endpoints = storedEndpoints + draftEndpoints
                + PortStatusParser.listeningEndpoints(lsofOutput: output)
            let index = LocalPortOccupancyIndex(endpoints: endpoints)
            guard let port = index.firstAvailablePort(
                host: fingerprint.host,
                startingAfter: currentPort
            ) else {
                throw LocalPortRecommendationError.noAvailablePort
            }
            return port
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func isOperational(for tunnel: TunnelConfig) -> Bool {
        let currentStatus = status(for: tunnel)
        return currentStatus == .running || currentStatus == .portListening
    }

    func displayedTunnels(
        searchQuery: String,
        selectedTag: String?,
        favoritesOnly: Bool,
        sort: TunnelSortOption
    ) -> [TunnelConfig] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = tunnels.filter { tunnel in
            let matchesTag = selectedTag.map { selected in
                tunnel.tags.contains { $0.caseInsensitiveCompare(selected) == .orderedSame }
            } ?? true
            let searchable = searchableText(for: tunnel).lowercased()
            return matchesTag && (!favoritesOnly || tunnel.isFavorite) && (query.isEmpty || searchable.contains(query))
        }

        switch sort {
        case .manual:
            return result.sorted { ($0.manualOrder ?? Int.max, $0.name) < ($1.manualOrder ?? Int.max, $1.name) }
        case .name:
            return result.sorted {
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame
                    ? manualOrder(of: $0) < manualOrder(of: $1)
                    : comparison == .orderedAscending
            }
        case .status:
            return result.sorted {
                let left = statusSortRank(status(for: $0))
                let right = statusSortRank(status(for: $1))
                guard left == right else { return left < right }
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame
                    ? manualOrder(of: $0) < manualOrder(of: $1)
                    : comparison == .orderedAscending
            }
        case .lastUsed:
            return result.sorted {
                let left = $0.lastUsedAt ?? .distantPast
                let right = $1.lastUsedAt ?? .distantPast
                return left == right ? manualOrder(of: $0) < manualOrder(of: $1) : left > right
            }
        }
    }

    var availableTags: [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for tag in tunnels.flatMap(\.tags) {
            let comparisonKey = tag.folding(options: .caseInsensitive, locale: nil)
            if seen.insert(comparisonKey).inserted {
                tags.append(tag)
            }
        }
        return tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var existingSSHConfigAliases: [String] {
        tunnels.compactMap { tunnel in
            tunnel.mode == .sshConfig ? tunnel.sshConfigName : nil
        }
    }

    func exportConfigurationData(selectedIDs: Set<TunnelConfig.ID>) throws -> Data {
        let selected = tunnels.filter { selectedIDs.contains($0.id) }
        return try configurationTransfer.exportData(
            configs: selected,
            appVersion: AppVersion.current
        )
    }

    func decodeConfigurationImport(_ data: Data) throws -> TunnelConfigurationDocument {
        try configurationTransfer.decode(data)
    }

    func previewConfigurationImport(
        _ document: TunnelConfigurationDocument,
        strategy: TunnelImportConflictStrategy
    ) -> TunnelImportPreview {
        configurationTransfer.preview(document: document, existing: tunnels, strategy: strategy)
    }

    @discardableResult
    func commitConfigurationImport(
        _ preview: TunnelImportPreview,
        beforeSave: (() throws -> Void)? = nil
    ) -> Bool {
        addError = ""
        guard preview.canCommit else {
            addError = AppStrings.configurationImportHasConflicts()
            return false
        }
        guard !tunnels.contains(where: { isRunRequested(for: $0) }) else {
            addError = AppStrings.configurationImportStopTunnels()
            return false
        }

        let previousTunnels = tunnels
        let hadOriginalFile = FileManager.default.fileExists(atPath: store.configURL.path)
        do {
            _ = try store.createPreImportBackup()
            try beforeSave?()
            try store.save(preview.mergedConfigs)
            tunnels = preview.mergedConfigs
            runtimes = runtimes.filter { id, _ in tunnels.contains(where: { $0.id == id }) }
            refreshStatuses()
            return true
        } catch {
            tunnels = previousTunnels
            do {
                try store.restorePreImportState(hadOriginalFile: hadOriginalFile)
            } catch {
                addError = AppStrings.configurationImportRestoreFailed(error.localizedDescription)
                return false
            }
            addError = AppStrings.configurationImportSaveFailed(error.localizedDescription)
            return false
        }
    }

    func toggleFavorite(_ tunnel: TunnelConfig) {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return }
        persistChanges {
            tunnels[index].isFavorite.toggle()
        }
    }

    func moveManualOrder(_ tunnel: TunnelConfig, direction: Int) {
        let ordered = displayedTunnels(searchQuery: "", selectedTag: nil, favoritesOnly: false, sort: .manual)
        guard let current = ordered.firstIndex(where: { $0.id == tunnel.id }) else { return }
        let target = current + direction
        guard ordered.indices.contains(target) else { return }
        var ids = ordered.map(\.id)
        ids.swapAt(current, target)
        let lookup = Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0) })
        persistChanges {
            tunnels = ids.compactMap { lookup[$0] }
            assignManualOrderFromCurrentSequence()
        }
    }

    @discardableResult
    func addTunnel(_ draft: TunnelDraft, onSuccess: (() -> Void)? = nil) -> Bool {
        addTunnel(draft, allowRiskyBind: false, onSuccess: onSuccess)
    }

    @discardableResult
    func importSSHConfigAliases(_ aliases: [String]) -> Bool {
        addError = ""
        let existingKeys = Set(existingSSHConfigAliases.map {
            $0.folding(options: .caseInsensitive, locale: nil)
        })
        var seen = existingKeys
        var nameKeys = Set(tunnels.map { TunnelConfig.nameComparisonKey($0.name) })
        var imported: [TunnelConfig] = []
        var nextManualOrder = (tunnels.compactMap(\.manualOrder).max() ?? -1) + 1

        do {
            for rawAlias in aliases {
                let alias = rawAlias.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = alias.folding(options: .caseInsensitive, locale: nil)
                guard seen.insert(key).inserted else { continue }
                guard nameKeys.insert(TunnelConfig.nameComparisonKey(alias)).inserted else {
                    throw TunnelNameConflictError(name: alias)
                }
                var tunnel = TunnelConfig(name: alias, sshConfigName: alias, openURL: nil)
                try commandBuilder.validate(tunnel)
                tunnel.manualOrder = nextManualOrder
                nextManualOrder += 1
                imported.append(tunnel)
            }
        } catch {
            addError = error.localizedDescription
            return false
        }

        guard !imported.isEmpty else {
            addError = AppStrings.importNoNewHosts()
            return false
        }

        let previousTunnels = tunnels
        tunnels.append(contentsOf: imported)
        do {
            try save()
            return true
        } catch {
            tunnels = previousTunnels
            addError = AppStrings.failedToSaveTunnels(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    private func addTunnel(
        _ draft: TunnelDraft,
        allowRiskyBind: Bool,
        onSuccess: (() -> Void)?
    ) -> Bool {
        addError = ""
        validationPortConflict = nil
        do {
            var tunnel = try validatedTunnel(from: draft, allowRiskyBind: allowRiskyBind)
            tunnel.manualOrder = (tunnels.map { $0.manualOrder ?? -1 }.max() ?? -1) + 1
            let previousTunnels = tunnels
            tunnels.append(tunnel)
            do {
                try save()
            } catch {
                tunnels = previousTunnels
                throw error
            }
            onSuccess?()
            return true
        } catch let confirmation as TunnelRiskConfirmationRequired {
            requestRiskConfirmation(title: confirmation.title, message: confirmation.message) { [weak self] in
                _ = self?.addTunnel(draft, allowRiskyBind: true, onSuccess: onSuccess)
            }
            return false
        } catch {
            validationPortConflict = Self.localPortConflict(from: error)
            addError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateTunnel(
        _ tunnel: TunnelConfig,
        with draft: TunnelDraft,
        onSuccess: (() -> Void)? = nil
    ) -> Bool {
        updateTunnel(tunnel, with: draft, allowRiskyBind: false, onSuccess: onSuccess)
    }

    @discardableResult
    private func updateTunnel(
        _ tunnel: TunnelConfig,
        with draft: TunnelDraft,
        allowRiskyBind: Bool,
        onSuccess: (() -> Void)?
    ) -> Bool {
        addError = ""
        validationPortConflict = nil
        let existingKind: TunnelConfigurationKind = tunnel.mode == .sshConfig
            ? .sshConfigReference
            : .connectionGroup
        guard draft.configurationKind == existingKind else {
            addError = AppStrings.string("error.configurationTypeImmutable")
            return false
        }
        if isRunRequested(for: tunnel) {
            requestRiskConfirmation(
                title: AppStrings.string("edit.restart.title"),
                message: AppStrings.string("edit.restart.message")
            ) { [weak self] in
                guard let self else { return }
                self.stop(tunnel)
                let updated = self.updateTunnel(
                    tunnel,
                    with: draft,
                    allowRiskyBind: allowRiskyBind,
                    onSuccess: onSuccess
                )
                if updated,
                   let saved = self.tunnels.first(where: { $0.id == tunnel.id }),
                   saved.mode == .sshConfig || saved.effectiveRules.contains(where: \.isEnabled) {
                    self.start(saved)
                }
            }
            return false
        }

        do {
            var updatedTunnel = try validatedTunnel(
                from: draft,
                id: tunnel.id,
                allowRiskyBind: allowRiskyBind
            )
            guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else {
                return false
            }
            let previousTunnels = tunnels
            updatedTunnel.isFavorite = tunnel.isFavorite
            updatedTunnel.manualOrder = tunnel.manualOrder
            updatedTunnel.lastUsedAt = tunnel.lastUsedAt
            tunnels[index] = updatedTunnel
            runtimes[tunnel.id]?.lastError = ""
            runtimes[tunnel.id]?.localPortConflict = nil
            runtimes[tunnel.id]?.ruleHealthStates = [:]
            do {
                try save()
            } catch {
                tunnels = previousTunnels
                throw error
            }
            refreshStatuses()
            onSuccess?()
            return true
        } catch let confirmation as TunnelRiskConfirmationRequired {
            requestRiskConfirmation(title: confirmation.title, message: confirmation.message) { [weak self] in
                _ = self?.updateTunnel(
                    tunnel,
                    with: draft,
                    allowRiskyBind: true,
                    onSuccess: onSuccess
                )
            }
            return false
        } catch {
            validationPortConflict = Self.localPortConflict(from: error)
            addError = error.localizedDescription
            return false
        }
    }

    func deleteTunnel(_ tunnel: TunnelConfig) {
        stop(tunnel)
        let previousTunnels = tunnels
        tunnels.removeAll { $0.id == tunnel.id }
        runtimes.removeValue(forKey: tunnel.id)
        reconcileHealthChecks()
        do {
            try save()
        } catch {
            tunnels = previousTunnels
            addError = AppStrings.failedToSaveTunnels(error.localizedDescription)
        }
    }

    func start(_ tunnel: TunnelConfig) {
        start(tunnel, allowRiskyBind: false, trigger: .manual)
    }

    func startAutomaticallyConfiguredTunnels() {
        for tunnel in tunnels where tunnel.isAutoStartEnabled {
            start(tunnel, allowRiskyBind: false, trigger: .automatic)
        }
    }

    private func start(
        _ tunnel: TunnelConfig,
        allowRiskyBind: Bool,
        trigger: TunnelStartTrigger
    ) {
        var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        guard runtime.process?.isRunning != true else { return }
        runtime.retryTask?.cancel()
        runtime.recoveryNotificationTask?.cancel()
        runtime.stableResetTask?.cancel()
        runtime.retryTask = nil
        runtime.recoveryNotificationTask = nil
        runtime.stableResetTask = nil
        _ = runtime.recovery.setNetworkAvailable(tunnel.isAutoReconnectEnabled ? isNetworkAvailable : true)
        _ = runtime.recovery.setSleeping(tunnel.isAutoReconnectEnabled ? isSystemSleeping : false)
        let previousPhase = runtime.recovery.phase
        let generation = runtime.recovery.requestStart()
        updateStatusChangedAt(&runtime, from: previousPhase)
        runtime.lastError = ""
        runtime.lastExitCode = nil
        runtime.nextRetryAt = nil
        runtime.errorCategory = nil
        runtime.localPortConflict = nil
        runtime.notificationCycle.reset()
        runtime.allowsRiskyRestart = allowRiskyBind
        runtime.ruleHealthStates = [:]
        runtimes[tunnel.id] = runtime

        guard case .connecting = runtime.recovery.phase else { return }
        launch(
            tunnel,
            generation: generation,
            allowRiskyBind: allowRiskyBind,
            isAutomaticRecovery: trigger == .automatic
        )
    }

    private func launch(
        _ tunnel: TunnelConfig,
        generation: UInt64,
        allowRiskyBind: Bool,
        isAutomaticRecovery: Bool
    ) {
        do {
            try commandBuilder.validateForStart(tunnel)
            try validateGeneratedForwardingHost(tunnel)
            try validateLocalEndpointConflicts(for: tunnel)
            if tunnel.mode == .sshConfig {
                let sshConfigName = tunnel.sshConfigName ?? ""
                switch sshConfigForwardingStatus(named: sshConfigName) {
                case .hasForwarding(let directives):
                    try validateSSHConfigRisk(directives, allowRiskyBind: allowRiskyBind)
                case .missingForwarding:
                    var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
                    runtime.process = nil
                    runtime.lastError = sanitizedDiagnostic(
                        TunnelValidationError.sshConfigMissingForwardingDirective(sshConfigName)
                            .localizedDescription,
                        for: tunnel
                    )
                    let previousPhase = runtime.recovery.phase
                    _ = runtime.recovery.requestStop(reason: .nonRetryableFailure)
                    updateStatusChangedAt(&runtime, from: previousPhase)
                    recordFailure(
                        in: &runtime,
                        diagnostic: runtime.lastError,
                        nextRetryAt: nil
                    )
                    runtimes[tunnel.id] = runtime
                    return
                case .timedOut:
                    let error = TunnelValidationError.sshConfigValidationTimedOut(
                        sshConfigName,
                        Self.sshConfigValidationTimeoutSeconds
                    )
                    recordLaunchFailure(
                        error.localizedDescription,
                        for: tunnel,
                        generation: generation,
                        retryable: isAutomaticRecovery,
                        isAutomaticRecovery: isAutomaticRecovery
                    )
                    return
                }
            } else {
                try validateRiskyBind(tunnel, allowRiskyBind: allowRiskyBind)
            }

            let command = commandBuilder.buildStartCommand(for: tunnel)
            let process = Process()
            let stderr = Pipe()
            let stderrTail = StderrTailBuffer(maxLines: 6)
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else {
                    return
                }
                stderrTail.append(text)
            }

            var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
            guard runtime.recovery.generation == generation,
                  runtime.recovery.wantsToRun else { return }
            runtime.lastError = ""
            runtime.process = process
            runtime.stderrTail = stderrTail
            runtimes[tunnel.id] = runtime

            process.terminationHandler = { [weak self] finishedProcess in
                stderr.fileHandleForReading.readabilityHandler = nil
                let message = stderrTail.text
                Task { @MainActor in
                    guard var current = self?.runtimes[tunnel.id],
                          current.process === finishedProcess else {
                        return
                    }
                    current.process = nil
                    current.recoveryNotificationTask?.cancel()
                    current.recoveryNotificationTask = nil
                    current.stableResetTask?.cancel()
                    current.stableResetTask = nil
                    let rawDiagnostic = message.isEmpty
                        ? AppStrings.sshProcessExited(code: finishedProcess.terminationStatus)
                        : message
                    let currentTunnel = self?.tunnels.first(where: { $0.id == tunnel.id }) ?? tunnel
                    let retryable = TunnelFailureClassifier.isRetryable(stderr: rawDiagnostic)
                    current.lastError = self?.sanitizedDiagnostic(rawDiagnostic, for: currentTunnel)
                        ?? rawDiagnostic
                    current.lastExitCode = finishedProcess.terminationStatus
                    let previousPhase = current.recovery.phase
                    let delay = current.recovery.processExited(
                        generation: generation,
                        retryable: retryable,
                        autoReconnectEnabled: currentTunnel.isAutoReconnectEnabled
                    )
                    self?.updateStatusChangedAt(&current, from: previousPhase)
                    let nextRetryAt = delay.map { Date().addingTimeInterval($0) }
                    self?.recordFailure(
                        in: &current,
                        diagnostic: current.lastError,
                        nextRetryAt: nextRetryAt
                    )
                    self?.runtimes[tunnel.id] = current
                    if let delay {
                        self?.scheduleRetry(for: currentTunnel, generation: generation, delay: delay)
                    }
                    self?.refreshStatuses()
                }
            }

            try process.run()
            runtime = runtimes[tunnel.id] ?? runtime
            let previousPhase = runtime.recovery.phase
            guard runtime.recovery.markRunning(generation: generation) else {
                ManagedProcessTerminator.terminateAndWait(process, timeout: 1, forceKillAfterTimeout: true)
                return
            }
            updateStatusChangedAt(&runtime, from: previousPhase)
            runtime.nextRetryAt = nil
            runtime.lastExitCode = nil
            runtime.errorCategory = nil
            runtime.localPortConflict = nil
            runtime.recoveryNotificationTask = recoveryNotificationTask(
                for: tunnel.id,
                generation: generation,
                process: process
            )
            runtime.stableResetTask = stableResetTask(for: tunnel.id, generation: generation)
            runtimes[tunnel.id] = runtime
            markTunnelUsed(tunnel.id)
            refreshStatuses()
        } catch let confirmation as TunnelRiskConfirmationRequired {
            if isAutomaticRecovery {
                recordLaunchFailure(
                    AppStrings.autoStartRiskConfirmationRequired(),
                    for: tunnel,
                    generation: generation,
                    retryable: false,
                    isAutomaticRecovery: false
                )
                return
            }
            stopRecoveryTasks(for: tunnel.id, reason: .userRequested, clearError: true)
            requestRiskConfirmation(title: confirmation.title, message: confirmation.message) { [weak self] in
                guard let self, let confirmed = self.persistRiskConfirmations(for: tunnel) else { return }
                self.start(confirmed, allowRiskyBind: true, trigger: .manual)
            }
        } catch {
            let retryableValidationError = (error as? TunnelValidationError)
                .map(TunnelFailureClassifier.isRetryable(validationError:))
                ?? false
            recordLaunchFailure(
                error.localizedDescription,
                for: tunnel,
                generation: generation,
                retryable: isAutomaticRecovery && retryableValidationError,
                isAutomaticRecovery: isAutomaticRecovery
            )
            if let conflict = Self.localPortConflict(from: error) {
                runtimes[tunnel.id]?.localPortConflict = conflict
            }
        }
    }

    private func recordLaunchFailure(
        _ message: String,
        for tunnel: TunnelConfig,
        generation: UInt64,
        retryable: Bool,
        isAutomaticRecovery: Bool
    ) {
        guard var runtime = runtimes[tunnel.id],
              runtime.recovery.generation == generation,
              runtime.recovery.wantsToRun else { return }
        runtime.process = nil
        runtime.lastError = sanitizedDiagnostic(message, for: tunnel)
        let previousPhase = runtime.recovery.phase
        if isAutomaticRecovery && retryable {
            let delay = runtime.recovery.processExited(
                generation: generation,
                retryable: true,
                autoReconnectEnabled: tunnel.isAutoReconnectEnabled
            )
            updateStatusChangedAt(&runtime, from: previousPhase)
            let nextRetryAt = delay.map { Date().addingTimeInterval($0) }
            recordFailure(in: &runtime, diagnostic: runtime.lastError, nextRetryAt: nextRetryAt)
            runtimes[tunnel.id] = runtime
            if let delay {
                scheduleRetry(for: tunnel, generation: generation, delay: delay)
            }
        } else {
            _ = runtime.recovery.requestStop(reason: .nonRetryableFailure)
            updateStatusChangedAt(&runtime, from: previousPhase)
            recordFailure(in: &runtime, diagnostic: runtime.lastError, nextRetryAt: nil)
            runtimes[tunnel.id] = runtime
        }
    }

    func stop(_ tunnel: TunnelConfig) {
        guard var runtime = runtimes[tunnel.id] else {
            return
        }
        let previousPhase = runtime.recovery.phase
        _ = runtime.recovery.requestStop(reason: .userRequested)
        updateStatusChangedAt(&runtime, from: previousPhase)
        runtime.retryTask?.cancel()
        runtime.recoveryNotificationTask?.cancel()
        runtime.stableResetTask?.cancel()
        runtime.retryTask = nil
        runtime.recoveryNotificationTask = nil
        runtime.stableResetTask = nil
        runtime.lastError = ""
        runtime.lastExitCode = nil
        runtime.nextRetryAt = nil
        runtime.errorCategory = nil
        runtime.localPortConflict = nil
        runtime.notificationCycle.reset()
        runtime.ruleHealthStates = [:]
        let process = runtime.process
        runtimes[tunnel.id] = runtime
        reconcileHealthChecks()
        if let process {
            ManagedProcessTerminator.terminateAndWait(
                process,
                timeout: 1,
                forceKillAfterTimeout: true
            )
        }
        runtime.process = nil
        runtimes[tunnel.id] = runtime
        refreshStatuses()
    }

    private func scheduleRetry(for tunnel: TunnelConfig, generation: UInt64, delay: TimeInterval) {
        var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        runtime.retryTask?.cancel()
        runtime.retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  var current = self.runtimes[tunnel.id],
                  current.recovery.generation == generation else {
                return
            }
            let previousPhase = current.recovery.phase
            guard current.recovery.beginScheduledRetry(generation: generation) else { return }
            self.updateStatusChangedAt(&current, from: previousPhase)
            current.retryTask = nil
            current.nextRetryAt = nil
            let allowsRiskyRestart = current.allowsRiskyRestart
            self.runtimes[tunnel.id] = current
            self.launch(
                tunnel,
                generation: generation,
                allowRiskyBind: allowsRiskyRestart,
                isAutomaticRecovery: true
            )
        }
        runtimes[tunnel.id] = runtime
    }

    private func stableResetTask(for tunnelID: TunnelConfig.ID, generation: UInt64) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(TunnelRecoveryPolicy.stableRunResetInterval))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  var runtime = self.runtimes[tunnelID],
                  runtime.recovery.markStable(generation: generation) else {
                return
            }
            runtime.stableResetTask = nil
            self.runtimes[tunnelID] = runtime
        }
    }

    private func recoveryNotificationTask(
        for tunnelID: TunnelConfig.ID,
        generation: UInt64,
        process: Process
    ) -> Task<Void, Never> {
        Task { [weak self, weak process] in
            do {
                try await Task.sleep(for: .seconds(TunnelRecoveryPolicy.networkStabilityInterval))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, let process,
                  var runtime = self.runtimes[tunnelID],
                  runtime.recovery.generation == generation,
                  runtime.process === process,
                  process.isRunning else {
                return
            }
            runtime.recoveryNotificationTask = nil
            if runtime.notificationCycle.recover() {
                self.notificationSender.send(.connectionRecovered)
            }
            self.runtimes[tunnelID] = runtime
        }
    }

    private func stopRecoveryTasks(
        for tunnelID: TunnelConfig.ID,
        reason: TunnelStopReason,
        clearError: Bool
    ) {
        guard var runtime = runtimes[tunnelID] else { return }
        let previousPhase = runtime.recovery.phase
        _ = runtime.recovery.requestStop(reason: reason)
        updateStatusChangedAt(&runtime, from: previousPhase)
        runtime.retryTask?.cancel()
        runtime.recoveryNotificationTask?.cancel()
        runtime.stableResetTask?.cancel()
        runtime.retryTask = nil
        runtime.recoveryNotificationTask = nil
        runtime.stableResetTask = nil
        runtime.nextRetryAt = nil
        runtime.notificationCycle.reset()
        if clearError {
            runtime.lastError = ""
            runtime.lastExitCode = nil
            runtime.errorCategory = nil
        }
        runtimes[tunnelID] = runtime
        reconcileHealthChecks()
    }

    func handleNetworkAvailabilityChanged(_ available: Bool) {
        isNetworkAvailable = available
        for tunnel in tunnels where tunnel.isAutoReconnectEnabled {
            guard var runtime = runtimes[tunnel.id], runtime.recovery.wantsToRun else { continue }
            let previousPhase = runtime.recovery.phase
            let shouldRecover = runtime.recovery.setNetworkAvailable(available)
            updateStatusChangedAt(&runtime, from: previousPhase)
            if !available {
                runtime.retryTask?.cancel()
                runtime.recoveryNotificationTask?.cancel()
                runtime.stableResetTask?.cancel()
                runtime.retryTask = nil
                runtime.recoveryNotificationTask = nil
                runtime.stableResetTask = nil
                runtime.nextRetryAt = nil
            }
            runtimes[tunnel.id] = runtime
            if shouldRecover { scheduleNetworkRecovery(for: tunnel) }
        }
        reconcileHealthChecks()
    }

    func handleSystemSleep() {
        isSystemSleeping = true
        for tunnel in tunnels where tunnel.isAutoReconnectEnabled {
            guard var runtime = runtimes[tunnel.id], runtime.recovery.wantsToRun else { continue }
            let previousPhase = runtime.recovery.phase
            _ = runtime.recovery.setSleeping(true)
            updateStatusChangedAt(&runtime, from: previousPhase)
            runtime.retryTask?.cancel()
            runtime.recoveryNotificationTask?.cancel()
            runtime.stableResetTask?.cancel()
            runtime.retryTask = nil
            runtime.recoveryNotificationTask = nil
            runtime.stableResetTask = nil
            runtime.nextRetryAt = nil
            runtimes[tunnel.id] = runtime
        }
        reconcileHealthChecks()
    }

    func handleSystemWake() {
        isSystemSleeping = false
        for tunnel in tunnels where tunnel.isAutoReconnectEnabled {
            guard var runtime = runtimes[tunnel.id], runtime.recovery.wantsToRun else { continue }
            let previousPhase = runtime.recovery.phase
            let shouldRecover = runtime.recovery.setSleeping(false)
            updateStatusChangedAt(&runtime, from: previousPhase)
            runtimes[tunnel.id] = runtime
            if shouldRecover { scheduleNetworkRecovery(for: tunnel) }
        }
        reconcileHealthChecks()
    }

    private func scheduleNetworkRecovery(for tunnel: TunnelConfig) {
        var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
        runtime.retryTask?.cancel()
        runtime.retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(TunnelRecoveryPolicy.networkStabilityInterval))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.isNetworkAvailable, !self.isSystemSleeping,
                  var current = self.runtimes[tunnel.id] else { return }
            current.retryTask = nil
            if current.process?.isRunning == true {
                let previousPhase = current.recovery.phase
                if current.recovery.resumeRunningProcessAfterRecovery() {
                    self.updateStatusChangedAt(&current, from: previousPhase)
                    if let process = current.process {
                        current.recoveryNotificationTask = self.recoveryNotificationTask(
                            for: tunnel.id,
                            generation: current.recovery.generation,
                            process: process
                        )
                    }
                    current.stableResetTask = self.stableResetTask(
                        for: tunnel.id,
                        generation: current.recovery.generation
                    )
                }
                self.runtimes[tunnel.id] = current
                return
            }
            let previousPhase = current.recovery.phase
            guard let generation = current.recovery.beginRecoveryAfterNetworkStabilized() else {
                self.runtimes[tunnel.id] = current
                return
            }
            self.updateStatusChangedAt(&current, from: previousPhase)
            let allowsRiskyRestart = current.allowsRiskyRestart
            self.runtimes[tunnel.id] = current
            self.launch(
                tunnel,
                generation: generation,
                allowRiskyBind: allowsRiskyRestart,
                isAutomaticRecovery: true
            )
        }
        runtimes[tunnel.id] = runtime
    }

    @discardableResult
    func stopAllManagedTunnels(forceKillAfterTimeout: Bool = false) -> Int {
        var stoppedCount = 0
        for (id, storedRuntime) in runtimes {
            var runtime = storedRuntime
            let previousPhase = runtime.recovery.phase
            _ = runtime.recovery.requestStop(reason: .applicationTerminating)
            updateStatusChangedAt(&runtime, from: previousPhase)
            runtime.retryTask?.cancel()
            runtime.recoveryNotificationTask?.cancel()
            runtime.stableResetTask?.cancel()
            runtime.retryTask = nil
            runtime.recoveryNotificationTask = nil
            runtime.stableResetTask = nil
            runtime.nextRetryAt = nil
            runtime.notificationCycle.reset()
            if let process = runtime.process, process.isRunning {
                ManagedProcessTerminator.terminateAndWait(
                    process,
                    timeout: 1,
                    forceKillAfterTimeout: forceKillAfterTimeout
                )
                stoppedCount += 1
            }
            runtime.process = nil
            runtimes[id] = runtime
        }
        refreshStatuses()
        return stoppedCount
    }

    func quitApplication() {
        prepareForApplicationTermination()
        NSApplication.shared.terminate(nil)
    }

    func confirmRiskyOperation() {
        let operation = pendingRiskOperation
        pendingRiskOperation = nil
        riskWarning = nil
        operation?()
    }

    func cancelRiskyOperation() {
        pendingRiskOperation = nil
        riskWarning = nil
    }

    func prepareForApplicationTermination() {
        healthCheckScheduler.updateTargets([])
        stopAllManagedTunnels(forceKillAfterTimeout: true)
        healthCheckScheduler.shutdown()
        recoveryMonitor.stop()
        refreshTimer?.invalidate()
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        if let willTerminateObserver {
            NotificationCenter.default.removeObserver(willTerminateObserver)
            self.willTerminateObserver = nil
        }
    }

    func openURL(for tunnel: TunnelConfig) {
        guard let url = tunnel.effectiveRules.compactMap(\.openURL).first ?? tunnel.openURL else {
            return
        }
        openURL(url)
    }

    func openURL(_ url: URL) {
        guard Self.isAllowedOpenURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    func openURLs(for tunnel: TunnelConfig) -> [URL] {
        let values = tunnel.mode == .sshConfig
            ? [tunnel.openURL].compactMap { $0 }
            : tunnel.effectiveRules.filter(\.isEnabled).compactMap(\.openURL)
        return Array(NSOrderedSet(array: values))
            .compactMap { $0 as? URL }
            .filter(Self.isAllowedOpenURL)
    }

    nonisolated static func isAllowedOpenURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private func reconcileHealthChecks() {
        var tunnelsByID: [TunnelConfig.ID: TunnelConfig] = [:]
        for tunnel in tunnels where tunnelsByID[tunnel.id] == nil {
            tunnelsByID[tunnel.id] = tunnel
        }
        for (tunnelID, storedRuntime) in runtimes {
            guard let tunnel = tunnelsByID[tunnelID] else { continue }
            let configuredRuleIDs = Set(tunnel.effectiveRules.compactMap { rule in
                rule.isEnabled && rule.healthCheck != nil ? rule.id : nil
            })
            var runtime = storedRuntime
            let filteredStates = runtime.ruleHealthStates.filter { configuredRuleIDs.contains($0.key) }
            if runtime.ruleHealthStates != filteredStates {
                runtime.ruleHealthStates = filteredStates
            }
            if !runtime.recovery.wantsToRun,
               runtime.ruleHealthStates.values.contains(where: { $0 != RuleHealthCheckRuntimeState() }) {
                runtime.ruleHealthStates = Dictionary(
                    uniqueKeysWithValues: configuredRuleIDs.map { ($0, RuleHealthCheckRuntimeState()) }
                )
            }
            if runtime.ruleHealthStates != storedRuntime.ruleHealthStates {
                runtimes[tunnelID] = runtime
            }
        }

        healthCheckScheduler.setSuspended(!isNetworkAvailable || isSystemSleeping)
        healthCheckScheduler.updateTargets(Self.healthCheckTargets(tunnels: tunnels, runtimes: runtimes))
    }

    static func healthCheckTargets(
        tunnels: [TunnelConfig],
        runtimes: [TunnelConfig.ID: TunnelRuntimeState]
    ) -> [ScheduledHealthCheckTarget] {
        tunnels.flatMap { tunnel -> [ScheduledHealthCheckTarget] in
            guard let runtime = runtimes[tunnel.id],
                  runtime.recovery.wantsToRun,
                  runtime.process?.isRunning == true,
                  runtime.isPortListening else {
                return []
            }
            return tunnel.effectiveRules.compactMap { rule in
                makeHealthCheckTarget(for: rule, tunnelID: tunnel.id, generation: runtime.recovery.generation)
            }
        }
    }

    private static func makeHealthCheckTarget(
        for rule: TunnelForwardRule,
        tunnelID: TunnelConfig.ID,
        generation: UInt64
    ) -> ScheduledHealthCheckTarget? {
        guard rule.isEnabled,
              let configuration = rule.healthCheck,
              rule.mode == .localForward || rule.mode == .dynamicForward else {
            return nil
        }
        return ScheduledHealthCheckTarget(request: HealthProbeRequest(
            key: RuleHealthCheckKey(tunnelID: tunnelID, ruleID: rule.id),
            generation: generation,
            listenerHost: rule.localHost,
            listenerPort: rule.localPort,
            configuration: configuration
        ))
    }

    private func recordHealthCheckResult(
        _ target: ScheduledHealthCheckTarget,
        result: HealthProbeResult,
        at date: Date
    ) {
        let request = target.request
        guard isNetworkAvailable,
              !isSystemSleeping,
              let tunnel = tunnels.first(where: { $0.id == request.key.tunnelID }),
              let rule = tunnel.effectiveRules.first(where: { $0.id == request.key.ruleID }),
              let expectedTarget = Self.makeHealthCheckTarget(
                for: rule,
                tunnelID: tunnel.id,
                generation: request.generation
              ),
              expectedTarget == target,
              var runtime = runtimes[tunnel.id],
              runtime.recovery.generation == request.generation,
              runtime.recovery.wantsToRun,
              runtime.process?.isRunning == true,
              runtime.isPortListening else {
            return
        }
        var state = runtime.ruleHealthStates[rule.id] ?? RuleHealthCheckRuntimeState()
        state.record(result, at: date)
        runtime.ruleHealthStates[rule.id] = state
        runtimes[tunnel.id] = runtime
    }

    func refreshStatuses() {
        scheduleNextAutomaticStatusRefresh()
        for tunnel in tunnels {
            guard !Self.shouldCheckLocalPort(for: tunnel),
                  var runtime = runtimes[tunnel.id],
                  Self.updatePortListening(false, in: &runtime) else {
                continue
            }
            runtimes[tunnel.id] = runtime
        }
        reconcileHealthChecks()

        guard statusRefreshTask == nil else {
            return
        }

        let endpoints = Set(tunnels.flatMap(Self.localListenerEndpoints(for:)))
        guard !endpoints.isEmpty else {
            reconcileHealthChecks()
            return
        }

        statusRefreshTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return [LocalPortEndpoint: Bool]() }
                let output = Self.listeningPortsSnapshot()
                return Dictionary(uniqueKeysWithValues: endpoints.map { endpoint in
                    (endpoint, PortStatusParser.isListening(
                        lsofOutput: output,
                        host: endpoint.host,
                        port: endpoint.port
                    ))
                })
            }.value

            guard let self else {
                return
            }
            self.statusRefreshTask = nil
            guard !Task.isCancelled else {
                return
            }

            for tunnel in self.tunnels where Self.shouldCheckLocalPort(for: tunnel) {
                let tunnelEndpoints = Self.localListenerEndpoints(for: tunnel)
                let isListening = !tunnelEndpoints.isEmpty && tunnelEndpoints.allSatisfy { results[$0] == true }
                var runtime = self.runtimes[tunnel.id] ?? TunnelRuntimeState()
                if Self.updatePortListening(isListening, in: &runtime) {
                    self.runtimes[tunnel.id] = runtime
                }
            }
            self.reconcileHealthChecks()
            self.scheduleNextAutomaticStatusRefresh()
        }
    }

    private func scheduleNextAutomaticStatusRefresh() {
        refreshTimer?.invalidate()
        let requiresFastRefresh = tunnels.contains { tunnel in
            Self.requiresFastStatusRefresh(
                for: tunnel,
                runtime: runtimes[tunnel.id] ?? TunnelRuntimeState()
            )
        }
        let interval = requiresFastRefresh
            ? Self.activeStatusRefreshInterval
            : Self.stableStatusRefreshInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatuses()
            }
        }
    }

    static func requiresFastStatusRefresh(
        for tunnel: TunnelConfig,
        runtime: TunnelRuntimeState
    ) -> Bool {
        shouldCheckLocalPort(for: tunnel)
            && runtime.recovery.wantsToRun
            && !runtime.isPortListening
    }

    @discardableResult
    static func updatePortListening(
        _ isListening: Bool,
        in runtime: inout TunnelRuntimeState
    ) -> Bool {
        guard runtime.isPortListening != isListening else { return false }
        runtime.isPortListening = isListening
        return true
    }

    private func save() throws {
        normalizeManualOrder()
        try store.save(tunnels)
    }

    private func persistChanges(_ changes: () -> Void) {
        let previousTunnels = tunnels
        changes()
        do {
            try save()
        } catch {
            tunnels = previousTunnels
            addError = AppStrings.failedToSaveTunnels(error.localizedDescription)
        }
    }

    private func normalizeManualOrder() {
        tunnels.sort { ($0.manualOrder ?? Int.max, $0.name) < ($1.manualOrder ?? Int.max, $1.name) }
        assignManualOrderFromCurrentSequence()
    }

    private func assignManualOrderFromCurrentSequence() {
        for index in tunnels.indices { tunnels[index].manualOrder = index }
    }

    private func markTunnelUsed(_ id: TunnelConfig.ID) {
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        persistChanges {
            tunnels[index].lastUsedAt = Date()
        }
    }

    private func statusSortRank(_ status: TunnelRuntimeStatus) -> Int {
        switch status {
        case .failed: return 0
        case .connecting, .waitingForNetwork, .waitingToReconnect: return 1
        case .running, .portListening: return 2
        case .externalListening: return 3
        case .stopped: return 4
        }
    }

    private func manualOrder(of tunnel: TunnelConfig) -> Int {
        tunnel.manualOrder ?? Int.max
    }

    private func searchableText(for tunnel: TunnelConfig) -> String {
        var fields = [
            tunnel.name,
            tunnel.tags.joined(separator: " "),
            tunnel.mode.rawValue,
            AppStrings.modeName(tunnel.mode)
        ]
        if tunnel.mode == .sshConfig {
            fields.append(tunnel.sshConfigName ?? "")
        } else {
            fields.append(tunnel.sshHost)
            for rule in tunnel.effectiveRules {
                fields += [
                    rule.mode.rawValue, AppStrings.modeName(rule.mode),
                    rule.localHost, String(rule.localPort),
                    rule.remoteHost, String(rule.remotePort),
                    rule.openURL?.absoluteString ?? ""
                ]
            }
        }
        return fields.joined(separator: " ")
    }

    private func updateStatusChangedAt(
        _ runtime: inout TunnelRuntimeState,
        from previousPhase: TunnelLifecyclePhase
    ) {
        if runtime.recovery.phase != previousPhase {
            runtime.statusChangedAt = Date()
        }
    }

    private func recordFailure(
        in runtime: inout TunnelRuntimeState,
        diagnostic: String,
        nextRetryAt: Date?
    ) {
        let category = TunnelFailureCategory.classify(diagnostic)
        runtime.errorCategory = category
        runtime.nextRetryAt = nextRetryAt
        guard runtime.notificationCycle.beginFailure() else { return }
        notificationSender.send(.connectionFailed(
            category: category,
            retryCount: runtime.recovery.failureCount,
            willRetry: runtime.recovery.wantsToRun
        ))
    }

    private func sanitizedDiagnostic(_ message: String, for tunnel: TunnelConfig) -> String {
        let ruleValues = tunnel.effectiveRules.flatMap { rule in
            [rule.localHost, rule.remoteHost]
        }
        let sanitized = TunnelDiagnosticSanitizer.sanitize(
            message,
            sensitiveValues: [
                tunnel.sshHost,
                tunnel.sshConfigName ?? "",
                tunnel.localHost,
                tunnel.remoteHost
            ] + ruleValues
        )
        guard tunnel.mode != .sshConfig,
              let match = tunnel.effectiveRules.enumerated().first(where: { _, rule in
                  message.contains(String(rule.listenerPort))
              }) else {
            return sanitized
        }
        return AppStrings.format(
            "error.ruleFailure",
            match.offset + 1,
            AppStrings.modeName(match.element.mode),
            sanitized
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private func validatedTunnel(
        from draft: TunnelDraft,
        id: TunnelConfig.ID = UUID(),
        allowRiskyBind: Bool
    ) throws -> TunnelConfig {
        var tunnel = try draft.makeConfig(id: id)
        try commandBuilder.validate(tunnel)
        try validateUniqueName(tunnel.name, excluding: tunnel.id)
        try validateLocalEndpointConflicts(for: tunnel)
        try validateGeneratedForwardingHost(tunnel)
        if tunnel.mode == .sshConfig {
            let sshConfigName = tunnel.sshConfigName ?? ""
            switch sshConfigForwardingStatus(named: sshConfigName) {
            case .hasForwarding(let directives):
                try validateSSHConfigRisk(directives, allowRiskyBind: allowRiskyBind)
            case .missingForwarding:
                throw TunnelValidationError.sshConfigMissingForwardingDirective(sshConfigName)
            case .timedOut:
                throw TunnelValidationError.sshConfigValidationTimedOut(
                    sshConfigName,
                    Self.sshConfigValidationTimeoutSeconds
                )
            }
        } else {
            try validateRiskyBind(tunnel, allowRiskyBind: allowRiskyBind)
            if allowRiskyBind {
                tunnel.replaceRules(tunnel.effectiveRules.map { rule in
                    var confirmed = rule
                    if rule.isEnabled && Self.isPotentiallyExposedBindHost(rule.listenerHost) {
                        confirmed.riskConfirmationSignature = rule.currentRiskSignature
                    }
                    return confirmed
                })
            }
        }
        return tunnel
    }

    private func validateUniqueName(_ name: String, excluding id: TunnelConfig.ID) throws {
        let key = TunnelConfig.nameComparisonKey(name)
        guard !tunnels.contains(where: {
            $0.id != id && TunnelConfig.nameComparisonKey($0.name) == key
        }) else {
            throw TunnelNameConflictError(name: name)
        }
    }

    static func shouldCheckLocalPort(for tunnel: TunnelConfig) -> Bool {
        !localListenerEndpoints(for: tunnel).isEmpty
    }

    private static func localListenerEndpoints(for tunnel: TunnelConfig) -> [LocalPortEndpoint] {
        tunnel.effectiveRules.compactMap { rule in
            guard rule.isEnabled, rule.mode == .localForward || rule.mode == .dynamicForward else {
                return nil
            }
            return LocalPortEndpoint(host: rule.localHost, port: rule.localPort)
        }
    }

    nonisolated private static func configuredLocalListenerEndpoints(
        for tunnel: TunnelConfig
    ) -> [LocalPortEndpoint] {
        tunnel.effectiveRules.compactMap { rule in
            guard rule.mode == .localForward || rule.mode == .dynamicForward else {
                return nil
            }
            return LocalPortEndpoint(host: rule.localHost, port: rule.localPort)
        }
    }

    private static func usesGeneratedForwardingArguments(_ tunnel: TunnelConfig) -> Bool {
        tunnel.mode == .localForward || tunnel.mode == .remoteForward || tunnel.mode == .dynamicForward
    }

    private static let sshConfigValidationTimeoutSeconds = 10
    private static let activeStatusRefreshInterval: TimeInterval = 2
    private static let stableStatusRefreshInterval: TimeInterval = 30

    private func validateRiskyBind(_ tunnel: TunnelConfig, allowRiskyBind: Bool) throws {
        guard !allowRiskyBind else { return }
        let unconfirmed = tunnel.effectiveRules.enumerated().filter { _, rule in
            rule.isEnabled && Self.isPotentiallyExposedBindHost(rule.listenerHost) && !rule.hasValidRiskConfirmation
        }
        guard !unconfirmed.isEmpty else { return }
        if unconfirmed.count == 1, let rule = unconfirmed.first?.element {
            if rule.mode == .remoteForward {
                throw TunnelRiskConfirmationRequired(
                    title: AppStrings.riskyRemoteBindTitle(),
                    message: AppStrings.riskyRemoteBindMessage(
                        host: rule.remoteHost,
                        port: rule.remotePort
                    )
                )
            }
            throw TunnelRiskConfirmationRequired(message: AppStrings.riskyLocalBindMessage())
        }
        let endpoints = unconfirmed.map { index, rule in
            "\(index + 1). \(AppStrings.modeName(rule.mode)) \(rule.listenerHost):\(rule.listenerPort)"
        }.joined(separator: "\n")
        throw TunnelRiskConfirmationRequired(
            title: AppStrings.string("security.riskyGroup.title"),
            message: AppStrings.format("security.riskyGroup.message", endpoints)
        )
    }

    private func persistRiskConfirmations(for tunnel: TunnelConfig) -> TunnelConfig? {
        guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return nil }
        let previous = tunnels[index]
        var confirmed = previous
        confirmed.replaceRules(previous.effectiveRules.map { rule in
            var value = rule
            if rule.isEnabled && Self.isPotentiallyExposedBindHost(rule.listenerHost) {
                value.riskConfirmationSignature = rule.currentRiskSignature
            }
            return value
        })
        tunnels[index] = confirmed
        do {
            try save()
            return confirmed
        } catch {
            tunnels[index] = previous
            addError = AppStrings.failedToSaveTunnels(error.localizedDescription)
            return nil
        }
    }

    private func validateLocalEndpointConflicts(for tunnel: TunnelConfig) throws {
        let candidateEndpoints = Self.localListenerEndpoints(for: tunnel)
        let listeningPorts = candidateEndpoints.isEmpty ? "" : Self.listeningPortsSnapshot()
        for (index, endpoint) in candidateEndpoints.enumerated() {
            if candidateEndpoints.dropFirst(index + 1).contains(where: {
                $0.port == endpoint.port && Self.listenerHostsOverlap($0.host, endpoint.host)
            }) {
                throw TunnelValidationError.localPortOccupied(endpoint.host, endpoint.port)
            }
            for other in tunnels where other.id != tunnel.id {
                if Self.localListenerEndpoints(for: other).contains(where: {
                    $0.port == endpoint.port && Self.listenerHostsOverlap($0.host, endpoint.host)
                }) {
                    throw TunnelValidationError.localPortOccupied(endpoint.host, endpoint.port)
                }
            }
            if PortStatusParser.isListening(
                lsofOutput: listeningPorts,
                host: endpoint.host,
                port: endpoint.port
            ) {
                throw TunnelValidationError.localPortOccupied(endpoint.host, endpoint.port)
            }
        }
    }

    private static func listenerHostsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        LocalPortOccupancyIndex.hostsOverlap(lhs, rhs)
    }

    private static func localPortConflict(from error: Error) -> LocalPortEndpoint? {
        guard case let TunnelValidationError.localPortOccupied(host, port) = error else {
            return nil
        }
        return LocalPortEndpoint(host: host, port: port)
    }

    private func validateSSHConfigRisk(
        _ directives: [SSHConfigForwardingDirective],
        allowRiskyBind: Bool
    ) throws {
        guard !allowRiskyBind else { return }
        if let remote = directives.first(where: { $0.kind == .remote && $0.isPotentiallyExposed }) {
            throw TunnelRiskConfirmationRequired(
                title: AppStrings.riskyRemoteBindTitle(),
                message: AppStrings.riskyRemoteBindMessage(
                    host: remote.listenHost,
                    port: remote.listenPort ?? 0
                )
            )
        }
        if directives.contains(where: {
            ($0.kind == .local || $0.kind == .dynamic) && $0.isPotentiallyExposed
        }) {
            throw TunnelRiskConfirmationRequired(message: AppStrings.riskyLocalBindMessage())
        }
    }

    private static func isPotentiallyExposedBindHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["127.0.0.1", "localhost", "::1", "[::1]"].contains(normalized)
    }

    private func validateGeneratedForwardingHost(_ tunnel: TunnelConfig) throws {
        guard Self.usesGeneratedForwardingArguments(tunnel) else {
            return
        }

        switch sshConfigForwardingDirectiveStatus(named: tunnel.sshHost) {
        case .hasForwardingDirective:
            throw TunnelValidationError.sshHostContainsForwardingDirectives(tunnel.sshHost)
        case .noForwardingDirective:
            break
        case .timedOut:
            throw TunnelValidationError.sshConfigValidationTimedOut(
                tunnel.sshHost,
                Self.sshConfigValidationTimeoutSeconds
            )
        }
    }

    private func sshConfigForwardingDirectiveStatus(named name: String) -> SSHConfigForwardingDirectiveStatus {
        switch sshConfigResolver.resolveConfig(
            named: name,
            timeout: TimeInterval(Self.sshConfigValidationTimeoutSeconds)
        ) {
        case .resolved(let text):
            return SSHConfigOutputParser.hasAnyForwardingDirective(text)
                ? .hasForwardingDirective
                : .noForwardingDirective
        case .failed:
            return .noForwardingDirective
        case .timedOut:
            return .timedOut
        }
    }

    private func sshConfigForwardingStatus(named name: String) -> SSHConfigForwardingStatus {
        switch sshConfigResolver.resolveConfig(
            named: name,
            timeout: TimeInterval(Self.sshConfigValidationTimeoutSeconds)
        ) {
        case .resolved(let text):
            let directives = SSHConfigOutputParser.forwardingDirectives(text)
            return directives.isEmpty ? .missingForwarding : .hasForwarding(directives)
        case .failed:
            return .missingForwarding
        case .timedOut:
            return .timedOut
        }
    }

    nonisolated private static func listeningPortsSnapshot() -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func requestRiskConfirmation(
        title: String,
        message: String,
        operation: @escaping () -> Void
    ) {
        pendingRiskOperation = operation
        riskWarning = TunnelRiskWarning(title: title, message: message)
    }

}
