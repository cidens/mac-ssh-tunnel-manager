public enum TunnelRuntimeStatus: String, Equatable, Sendable {
    case stopped = "Stopped"
    case connecting = "Connecting"
    case running = "Running"
    case portListening = "Listening"
    case waitingForNetwork = "Waiting for network"
    case waitingToReconnect = "Waiting to reconnect"
    case externalListening = "Port occupied"
    case failed = "Failed"

    public func displayText(language: String? = nil) -> String {
        switch self {
        case .stopped:
            return CoreStrings.string("status.stopped", language: language)
        case .connecting:
            return CoreStrings.string("status.connecting", language: language)
        case .running:
            return CoreStrings.string("status.running", language: language)
        case .portListening:
            return CoreStrings.string("status.portListening", language: language)
        case .waitingForNetwork:
            return CoreStrings.string("status.waitingForNetwork", language: language)
        case .waitingToReconnect:
            return CoreStrings.string("status.waitingToReconnect", language: language)
        case .externalListening:
            return CoreStrings.string("status.externalListening", language: language)
        case .failed:
            return CoreStrings.string("status.failed", language: language)
        }
    }
}

public enum TunnelRuntimeStatusResolver {
    public static func status(
        isManagedProcessRunning: Bool,
        isPortListening: Bool,
        lastError: String
    ) -> TunnelRuntimeStatus {
        if isManagedProcessRunning {
            return isPortListening ? .portListening : .running
        }
        if isPortListening {
            return .externalListening
        }
        if !lastError.isEmpty {
            return .failed
        }
        return .stopped
    }
}
