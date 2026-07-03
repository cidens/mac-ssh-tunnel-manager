public enum TunnelRuntimeStatus: String, Equatable, Sendable {
    case stopped = "Stopped"
    case running = "Running"
    case portListening = "Listening"
    case externalListening = "Port occupied"
    case failed = "Failed"

    public func displayText(language: String? = nil) -> String {
        switch self {
        case .stopped:
            return CoreStrings.string("status.stopped", language: language)
        case .running:
            return CoreStrings.string("status.running", language: language)
        case .portListening:
            return CoreStrings.string("status.portListening", language: language)
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
