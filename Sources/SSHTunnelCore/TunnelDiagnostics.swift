import Foundation

public enum TunnelFailureCategory: String, Codable, Equatable, Sendable {
    case authentication
    case hostKey
    case portConflict
    case configuration
    case network
    case unknown

    public static func classify(_ diagnostic: String) -> TunnelFailureCategory {
        let text = diagnostic.lowercased()
        if text.contains("permission denied") || text.contains("authentication failed") {
            return .authentication
        }
        if text.contains("host key verification failed")
            || text.contains("remote host identification has changed") {
            return .hostKey
        }
        if text.contains("address already in use")
            || text.contains("cannot listen to port")
            || text.contains("forwarding failed") {
            return .portConflict
        }
        if text.contains("configuration")
            || text.contains("bad configuration option")
            || text.contains("illegal option")
            || text.contains("unknown option")
            || text.contains("could not resolve hostname") {
            return .configuration
        }
        if text.contains("network is unreachable")
            || text.contains("connection timed out")
            || text.contains("connection reset")
            || text.contains("connection closed")
            || text.contains("no route to host") {
            return .network
        }
        return .unknown
    }
}

public struct TunnelNotificationCycle: Equatable, Sendable {
    public private(set) var isFailureActive = false

    public init() {}

    public mutating func beginFailure() -> Bool {
        guard !isFailureActive else { return false }
        isFailureActive = true
        return true
    }

    public mutating func recover() -> Bool {
        guard isFailureActive else { return false }
        isFailureActive = false
        return true
    }

    public mutating func reset() {
        isFailureActive = false
    }
}

public struct TunnelDiagnosticReport: Equatable, Sendable {
    public let appVersion: String
    public let systemVersion: String
    public let architecture: String
    public let mode: TunnelMode
    public let status: TunnelRuntimeStatus
    public let statusChangedAt: Date
    public let exitCode: Int32?
    public let retryCount: Int
    public let nextRetryAt: Date?
    public let errorCategory: TunnelFailureCategory?

    public init(
        appVersion: String,
        systemVersion: String,
        architecture: String,
        mode: TunnelMode,
        status: TunnelRuntimeStatus,
        statusChangedAt: Date,
        exitCode: Int32?,
        retryCount: Int,
        nextRetryAt: Date?,
        errorCategory: TunnelFailureCategory?
    ) {
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.architecture = architecture
        self.mode = mode
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.exitCode = exitCode
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.errorCategory = errorCategory
    }

    public var text: String {
        let formatter = ISO8601DateFormatter()
        return [
            "appVersion=\(appVersion)",
            "systemVersion=\(systemVersion)",
            "architecture=\(architecture)",
            "mode=\(mode.rawValue)",
            "status=\(status.rawValue)",
            "statusChangedAt=\(formatter.string(from: statusChangedAt))",
            "exitCode=\(exitCode.map(String.init) ?? "none")",
            "retryCount=\(retryCount)",
            "nextRetryAt=\(nextRetryAt.map(formatter.string(from:)) ?? "none")",
            "errorCategory=\(errorCategory?.rawValue ?? "none")"
        ].joined(separator: "\n")
    }
}
