import AppKit
import Network

@MainActor
final class SystemRecoveryMonitor {
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "ssh-tunnel-manager.network-monitor")
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    var onNetworkAvailabilityChanged: ((Bool) -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    init(pathMonitor: NWPathMonitor = NWPathMonitor()) {
        self.pathMonitor = pathMonitor
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.onNetworkAvailabilityChanged?(path.status == .satisfied)
            }
        }
        pathMonitor.start(queue: monitorQueue)

        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onSleep?() }
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        }
    }

    func stop() {
        pathMonitor.cancel()
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver { center.removeObserver(sleepObserver) }
        if let wakeObserver { center.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
    }
}
