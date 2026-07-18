import AppKit
import Foundation
import SSHTunnelCore

struct TunnelRuntimeState {
    var process: Process?
    var isPortListening = false
    var lastError = ""
    var stderrTail: StderrTailBuffer?
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

private enum SSHConfigLocalForwardStatus {
    case hasLocalForward(isPotentiallyExposed: Bool)
    case missingLocalForward
    case timedOut
}

private enum SSHConfigForwardingDirectiveStatus {
    case hasForwardingDirective
    case noForwardingDirective
    case timedOut
}

private struct LocalPortEndpoint: Hashable, Sendable {
    let host: String
    let port: Int
}

@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var tunnels: [TunnelConfig] = []
    @Published private(set) var runtimes: [TunnelConfig.ID: TunnelRuntimeState] = [:]
    @Published var addError = ""
    @Published var riskWarning: TunnelRiskWarning?

    private let store: TunnelConfigStore
    private let sshConfigResolver: any SSHConfigResolving
    private let commandBuilder = SSHCommandBuilder()
    private var refreshTimer: Timer?
    private var statusRefreshTask: Task<Void, Never>?
    private var willTerminateObserver: NSObjectProtocol?
    private var pendingRiskOperation: (() -> Void)?

    init(
        store: TunnelConfigStore = TunnelManager.defaultStore(),
        sshConfigResolver: any SSHConfigResolving = SystemSSHConfigResolver()
    ) {
        self.store = store
        self.sshConfigResolver = sshConfigResolver
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

        refreshStatuses()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatuses()
            }
        }
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForApplicationTermination()
            }
        }
    }

    var menuTitle: String {
        let running = tunnels.filter { isManagedProcessRunning(for: $0) }.count
        return AppStrings.menuTitle(runningCount: running)
    }

    var menuSystemImage: String {
        tunnels.contains { isManagedProcessRunning(for: $0) } ? "point.3.connected.trianglepath.dotted" : "circle.dotted"
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
        return TunnelRuntimeStatusResolver.status(
            isManagedProcessRunning: runtime.process?.isRunning == true,
            isPortListening: runtime.isPortListening,
            lastError: runtime.lastError
        )
    }

    func lastError(for tunnel: TunnelConfig) -> String {
        runtimes[tunnel.id]?.lastError ?? ""
    }

    func isManagedProcessRunning(for tunnel: TunnelConfig) -> Bool {
        runtimes[tunnel.id]?.process?.isRunning == true
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
    private func addTunnel(
        _ draft: TunnelDraft,
        allowRiskyBind: Bool,
        onSuccess: (() -> Void)?
    ) -> Bool {
        addError = ""
        do {
            var tunnel = try validatedTunnel(from: draft, allowRiskyBind: allowRiskyBind)
            tunnel.manualOrder = (tunnels.map { $0.manualOrder ?? -1 }.max() ?? -1) + 1
            tunnels.append(tunnel)
            try save()
            onSuccess?()
            return true
        } catch let confirmation as TunnelRiskConfirmationRequired {
            requestRiskConfirmation(title: confirmation.title, message: confirmation.message) { [weak self] in
                _ = self?.addTunnel(draft, allowRiskyBind: true, onSuccess: onSuccess)
            }
            return false
        } catch {
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
        guard !isManagedProcessRunning(for: tunnel) else {
            addError = AppStrings.stopBeforeEditing()
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
            updatedTunnel.isFavorite = tunnel.isFavorite
            updatedTunnel.manualOrder = tunnel.manualOrder
            updatedTunnel.lastUsedAt = tunnel.lastUsedAt
            tunnels[index] = updatedTunnel
            runtimes[tunnel.id]?.lastError = ""
            try save()
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
            addError = error.localizedDescription
            return false
        }
    }

    func deleteTunnel(_ tunnel: TunnelConfig) {
        stop(tunnel)
        tunnels.removeAll { $0.id == tunnel.id }
        runtimes.removeValue(forKey: tunnel.id)
        do {
            try save()
        } catch {
            addError = AppStrings.failedToSaveTunnels(error.localizedDescription)
        }
    }

    func start(_ tunnel: TunnelConfig) {
        start(tunnel, allowRiskyBind: false)
    }

    private func start(_ tunnel: TunnelConfig, allowRiskyBind: Bool) {
        do {
            try commandBuilder.validate(tunnel)
            try validateGeneratedForwardingHost(tunnel)
            if Self.shouldCheckLocalPort(for: tunnel) && Self.isListening(host: tunnel.localHost, port: tunnel.localPort) {
                var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
                runtime.process = nil
                runtime.isPortListening = true
                runtime.lastError = AppStrings.localPortAlreadyListeningOutsideApp(
                    host: tunnel.localHost,
                    port: tunnel.localPort
                )
                runtimes[tunnel.id] = runtime
                return
            }
            if tunnel.mode == .sshConfig {
                let sshConfigName = tunnel.sshConfigName ?? ""
                switch sshConfigLocalForwardStatus(named: sshConfigName) {
                case .hasLocalForward(let isPotentiallyExposed):
                    if isPotentiallyExposed && !allowRiskyBind {
                        throw TunnelRiskConfirmationRequired(
                            message: AppStrings.riskyLocalBindMessage()
                        )
                    }
                case .missingLocalForward:
                    var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
                    runtime.process = nil
                    runtime.lastError = TunnelValidationError.sshConfigMissingLocalForward(sshConfigName).localizedDescription
                    runtimes[tunnel.id] = runtime
                    return
                case .timedOut:
                    var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
                    runtime.process = nil
                    runtime.lastError = TunnelValidationError.sshConfigValidationTimedOut(
                        sshConfigName,
                        Self.sshConfigValidationTimeoutSeconds
                    ).localizedDescription
                    runtimes[tunnel.id] = runtime
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
                    current.lastError = message
                    self?.runtimes[tunnel.id] = current
                    self?.refreshStatuses()
                }
            }

            try process.run()
            markTunnelUsed(tunnel.id)
            refreshStatuses()
        } catch let confirmation as TunnelRiskConfirmationRequired {
            requestRiskConfirmation(title: confirmation.title, message: confirmation.message) { [weak self] in
                self?.start(tunnel, allowRiskyBind: true)
            }
        } catch {
            var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
            runtime.process = nil
            runtime.lastError = error.localizedDescription
            runtimes[tunnel.id] = runtime
        }
    }

    func stop(_ tunnel: TunnelConfig) {
        guard let runtime = runtimes[tunnel.id] else {
            return
        }
        if let process = runtime.process {
            ManagedProcessTerminator.terminateAndWait(process, timeout: 1)
        }
        var stoppedRuntime = runtime
        stoppedRuntime.process = nil
        runtimes[tunnel.id] = stoppedRuntime
        refreshStatuses()
    }

    @discardableResult
    func stopAllManagedTunnels(forceKillAfterTimeout: Bool = false) -> Int {
        var stoppedCount = 0
        for (id, runtime) in runtimes {
            guard let process = runtime.process,
                  process.isRunning else {
                continue
            }

            ManagedProcessTerminator.terminateAndWait(
                process,
                timeout: 1,
                forceKillAfterTimeout: forceKillAfterTimeout
            )
            var stoppedRuntime = runtime
            stoppedRuntime.process = nil
            runtimes[id] = stoppedRuntime
            stoppedCount += 1
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
        stopAllManagedTunnels(forceKillAfterTimeout: true)
        refreshTimer?.invalidate()
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        if let willTerminateObserver {
            NotificationCenter.default.removeObserver(willTerminateObserver)
            self.willTerminateObserver = nil
        }
    }

    func openURL(for tunnel: TunnelConfig) {
        guard let url = tunnel.openURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshStatuses() {
        for tunnel in tunnels {
            var runtime = runtimes[tunnel.id] ?? TunnelRuntimeState()
            if !Self.shouldCheckLocalPort(for: tunnel) {
                runtime.isPortListening = false
            }
            if runtime.process?.isRunning == false {
                runtime.process = nil
            }
            runtimes[tunnel.id] = runtime
        }

        guard statusRefreshTask == nil else {
            return
        }

        let endpoints = Set(tunnels.compactMap { tunnel -> LocalPortEndpoint? in
            guard Self.shouldCheckLocalPort(for: tunnel) else {
                return nil
            }
            return LocalPortEndpoint(host: tunnel.localHost, port: tunnel.localPort)
        })
        guard !endpoints.isEmpty else {
            return
        }

        statusRefreshTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) {
                var results: [LocalPortEndpoint: Bool] = [:]
                for endpoint in endpoints {
                    guard !Task.isCancelled else {
                        break
                    }
                    results[endpoint] = Self.isListening(host: endpoint.host, port: endpoint.port)
                }
                return results
            }.value

            guard let self else {
                return
            }
            self.statusRefreshTask = nil
            guard !Task.isCancelled else {
                return
            }

            for tunnel in self.tunnels where Self.shouldCheckLocalPort(for: tunnel) {
                let endpoint = LocalPortEndpoint(host: tunnel.localHost, port: tunnel.localPort)
                guard let isListening = results[endpoint] else {
                    continue
                }
                var runtime = self.runtimes[tunnel.id] ?? TunnelRuntimeState()
                runtime.isPortListening = isListening
                self.runtimes[tunnel.id] = runtime
            }
        }
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
        case .running, .portListening: return 1
        case .externalListening: return 2
        case .stopped: return 3
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
        switch tunnel.mode {
        case .localForward:
            fields += [
                tunnel.sshHost, tunnel.localHost, String(tunnel.localPort),
                tunnel.remoteHost, String(tunnel.remotePort)
            ]
        case .remoteForward:
            fields += [
                tunnel.sshHost, tunnel.remoteHost, String(tunnel.remotePort),
                tunnel.localHost, String(tunnel.localPort)
            ]
        case .dynamicForward:
            fields += [tunnel.sshHost, tunnel.localHost, String(tunnel.localPort)]
        case .sshConfig:
            fields.append(tunnel.sshConfigName ?? "")
        }
        return fields.joined(separator: " ")
    }

    private func validatedTunnel(
        from draft: TunnelDraft,
        id: TunnelConfig.ID = UUID(),
        allowRiskyBind: Bool
    ) throws -> TunnelConfig {
        let tunnel = try draft.makeConfig(id: id)
        try commandBuilder.validate(tunnel)
        try validateGeneratedForwardingHost(tunnel)
        if Self.shouldCheckLocalPort(for: tunnel) && Self.isListening(host: tunnel.localHost, port: tunnel.localPort) {
            throw TunnelValidationError.localPortOccupied(tunnel.localHost, tunnel.localPort)
        }
        if tunnel.mode == .sshConfig {
            let sshConfigName = tunnel.sshConfigName ?? ""
            switch sshConfigLocalForwardStatus(named: sshConfigName) {
            case .hasLocalForward(let isPotentiallyExposed):
                if isPotentiallyExposed && !allowRiskyBind {
                    throw TunnelRiskConfirmationRequired(
                        message: AppStrings.riskyLocalBindMessage()
                    )
                }
            case .missingLocalForward:
                throw TunnelValidationError.sshConfigMissingLocalForward(sshConfigName)
            case .timedOut:
                throw TunnelValidationError.sshConfigValidationTimedOut(
                    sshConfigName,
                    Self.sshConfigValidationTimeoutSeconds
                )
            }
        } else {
            try validateRiskyBind(tunnel, allowRiskyBind: allowRiskyBind)
        }
        return tunnel
    }

    static func shouldCheckLocalPort(for tunnel: TunnelConfig) -> Bool {
        tunnel.mode == .localForward || tunnel.mode == .dynamicForward
    }

    private static func usesGeneratedForwardingArguments(_ tunnel: TunnelConfig) -> Bool {
        tunnel.mode == .localForward || tunnel.mode == .remoteForward || tunnel.mode == .dynamicForward
    }

    private static let sshConfigValidationTimeoutSeconds = 10

    private func validateRiskyBind(_ tunnel: TunnelConfig, allowRiskyBind: Bool) throws {
        guard !allowRiskyBind else {
            return
        }

        if Self.shouldCheckLocalPort(for: tunnel),
           Self.isPotentiallyExposedBindHost(tunnel.localHost) {
            throw TunnelRiskConfirmationRequired(message: AppStrings.riskyLocalBindMessage())
        }

        if tunnel.mode == .remoteForward,
           Self.isPotentiallyExposedBindHost(tunnel.remoteHost) {
            throw TunnelRiskConfirmationRequired(
                title: AppStrings.riskyRemoteBindTitle(),
                message: AppStrings.riskyRemoteBindMessage(
                    host: tunnel.remoteHost,
                    port: tunnel.remotePort
                )
            )
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

    private func sshConfigLocalForwardStatus(named name: String) -> SSHConfigLocalForwardStatus {
        switch sshConfigResolver.resolveConfig(
            named: name,
            timeout: TimeInterval(Self.sshConfigValidationTimeoutSeconds)
        ) {
        case .resolved(let text):
            guard SSHConfigOutputParser.hasLocalForward(text) else {
                return .missingLocalForward
            }
            let isPotentiallyExposed = SSHConfigOutputParser
                .localForwardBindHosts(text)
                .contains(where: Self.isPotentiallyExposedBindHost)
            return .hasLocalForward(isPotentiallyExposed: isPotentiallyExposed)
        case .failed:
            return .missingLocalForward
        case .timedOut:
            return .timedOut
        }
    }

    nonisolated private static func isListening(host: String, port: Int) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return PortStatusParser.isListening(lsofOutput: text, host: host, port: port)
        } catch {
            return false
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
