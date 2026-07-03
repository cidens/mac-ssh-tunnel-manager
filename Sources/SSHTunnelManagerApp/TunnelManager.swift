import AppKit
import Foundation
import SSHTunnelCore

struct TunnelRuntimeState {
    var process: Process?
    var isPortListening = false
    var lastError = ""
    var stderrTail: StderrTailBuffer?
}

private enum SSHConfigLocalForwardStatus {
    case hasLocalForward
    case missingLocalForward
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

    private let store: TunnelConfigStore
    private let sshConfigResolver: any SSHConfigResolving
    private let commandBuilder = SSHCommandBuilder()
    private var refreshTimer: Timer?
    private var willTerminateObserver: NSObjectProtocol?

    init(
        store: TunnelConfigStore = TunnelManager.defaultStore(),
        sshConfigResolver: any SSHConfigResolving = SystemSSHConfigResolver()
    ) {
        self.store = store
        self.sshConfigResolver = sshConfigResolver
        do {
            tunnels = try store.load()
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

    @discardableResult
    func addTunnel(_ draft: TunnelDraft) -> Bool {
        addError = ""
        do {
            let tunnel = try validatedTunnel(from: draft)
            tunnels.append(tunnel)
            try save()
            return true
        } catch {
            addError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateTunnel(_ tunnel: TunnelConfig, with draft: TunnelDraft) -> Bool {
        addError = ""
        guard !isManagedProcessRunning(for: tunnel) else {
            addError = AppStrings.stopBeforeEditing()
            return false
        }

        do {
            let updatedTunnel = try validatedTunnel(from: draft, id: tunnel.id)
            guard let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) else {
                return false
            }
            tunnels[index] = updatedTunnel
            runtimes[tunnel.id]?.lastError = ""
            try save()
            refreshStatuses()
            return true
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
                case .hasLocalForward:
                    break
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
            refreshStatuses()
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

    func prepareForApplicationTermination() {
        stopAllManagedTunnels(forceKillAfterTimeout: true)
        refreshTimer?.invalidate()
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
            runtime.isPortListening = Self.shouldCheckLocalPort(for: tunnel)
                ? Self.isListening(host: tunnel.localHost, port: tunnel.localPort)
                : false
            if runtime.process?.isRunning == false {
                runtime.process = nil
            }
            runtimes[tunnel.id] = runtime
        }
    }

    private func save() throws {
        try store.save(tunnels)
    }

    private func validatedTunnel(from draft: TunnelDraft, id: TunnelConfig.ID = UUID()) throws -> TunnelConfig {
        let tunnel = try draft.makeConfig(id: id)
        try commandBuilder.validate(tunnel)
        try validateGeneratedForwardingHost(tunnel)
        if Self.shouldCheckLocalPort(for: tunnel) && Self.isListening(host: tunnel.localHost, port: tunnel.localPort) {
            throw TunnelValidationError.localPortOccupied(tunnel.localHost, tunnel.localPort)
        }
        if tunnel.mode == .sshConfig {
            let sshConfigName = tunnel.sshConfigName ?? ""
            switch sshConfigLocalForwardStatus(named: sshConfigName) {
            case .hasLocalForward:
                break
            case .missingLocalForward:
                throw TunnelValidationError.sshConfigMissingLocalForward(sshConfigName)
            case .timedOut:
                throw TunnelValidationError.sshConfigValidationTimedOut(
                    sshConfigName,
                    Self.sshConfigValidationTimeoutSeconds
                )
            }
        }
        return tunnel
    }

    private static func shouldCheckLocalPort(for tunnel: TunnelConfig) -> Bool {
        tunnel.mode == .localForward || tunnel.mode == .dynamicForward
    }

    private static let sshConfigValidationTimeoutSeconds = 10

    private func validateGeneratedForwardingHost(_ tunnel: TunnelConfig) throws {
        guard Self.shouldCheckLocalPort(for: tunnel) else {
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
            return SSHConfigOutputParser.hasLocalForward(text) ? .hasLocalForward : .missingLocalForward
        case .failed:
            return .missingLocalForward
        case .timedOut:
            return .timedOut
        }
    }

    private static func isListening(host: String, port: Int) -> Bool {
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

}
