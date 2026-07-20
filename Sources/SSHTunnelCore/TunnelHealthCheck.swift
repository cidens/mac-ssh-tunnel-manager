import Foundation

public enum TunnelHealthCheckKind: String, Codable, CaseIterable, Equatable, Sendable {
    case tcp
    case http
    case socks5
}

public struct TunnelHealthCheckConfiguration: Codable, Equatable, Sendable {
    public static let defaultInterval: TimeInterval = 30
    public static let defaultTimeout: TimeInterval = 3
    public static let intervalRange: ClosedRange<TimeInterval> = 5...3_600
    public static let timeoutRange: ClosedRange<TimeInterval> = 1...30

    public var kind: TunnelHealthCheckKind
    public var url: URL?
    public var interval: TimeInterval
    public var timeout: TimeInterval

    public init(
        kind: TunnelHealthCheckKind,
        url: URL? = nil,
        interval: TimeInterval = defaultInterval,
        timeout: TimeInterval = defaultTimeout
    ) {
        self.kind = kind
        self.url = url
        self.interval = interval
        self.timeout = timeout
    }

    public func validate(for rule: TunnelForwardRule) throws {
        guard Self.intervalRange.contains(interval) else {
            throw TunnelHealthCheckValidationError.invalidInterval
        }
        guard Self.timeoutRange.contains(timeout), timeout <= interval else {
            throw TunnelHealthCheckValidationError.invalidTimeout
        }

        switch (rule.mode, kind) {
        case (.localForward, .tcp):
            guard url == nil else {
                throw TunnelHealthCheckValidationError.unexpectedURL
            }
        case (.localForward, .http):
            try validateHTTPURL(for: rule)
        case (.dynamicForward, .socks5):
            guard url == nil else {
                throw TunnelHealthCheckValidationError.unexpectedURL
            }
        case (.remoteForward, _), (.sshConfig, _):
            throw TunnelHealthCheckValidationError.unsupportedRuleMode
        case (.localForward, .socks5), (.dynamicForward, .tcp), (.dynamicForward, .http):
            throw TunnelHealthCheckValidationError.unsupportedCheckKind
        }
    }

    private func validateHTTPURL(for rule: TunnelForwardRule) throws {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            throw TunnelHealthCheckValidationError.invalidURL
        }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        guard port == rule.localPort,
              Self.healthURLHost(host, matchesListenerHost: rule.localHost) else {
            throw TunnelHealthCheckValidationError.urlDoesNotMatchListener
        }
    }

    private static func healthURLHost(_ urlHost: String, matchesListenerHost listenerHost: String) -> Bool {
        let listener = normalizedHost(listenerHost)
        let candidate = normalizedHost(urlHost)
        switch listener {
        case "*", "0.0.0.0":
            return ["localhost", "127.0.0.1"].contains(candidate)
        case "::":
            return ["localhost", "::1"].contains(candidate)
        default:
            return LocalPortOccupancyIndex.hostsOverlap(listener, candidate)
        }
    }

    private static func normalizedHost(_ host: String) -> String {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("["), value.hasSuffix("]") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

public enum TunnelHealthCheckValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedRuleMode
    case unsupportedCheckKind
    case invalidURL
    case unexpectedURL
    case urlDoesNotMatchListener
    case invalidInterval
    case invalidTimeout

    public var errorDescription: String? {
        switch self {
        case .unsupportedRuleMode:
            return CoreStrings.string("health.error.unsupportedRuleMode")
        case .unsupportedCheckKind:
            return CoreStrings.string("health.error.unsupportedCheckKind")
        case .invalidURL:
            return CoreStrings.string("health.error.invalidURL")
        case .unexpectedURL:
            return CoreStrings.string("health.error.unexpectedURL")
        case .urlDoesNotMatchListener:
            return CoreStrings.string("health.error.urlDoesNotMatchListener")
        case .invalidInterval:
            return CoreStrings.format(
                "health.error.invalidInterval",
                Int(TunnelHealthCheckConfiguration.intervalRange.lowerBound),
                Int(TunnelHealthCheckConfiguration.intervalRange.upperBound)
            )
        case .invalidTimeout:
            return CoreStrings.format(
                "health.error.invalidTimeout",
                Int(TunnelHealthCheckConfiguration.timeoutRange.lowerBound),
                Int(TunnelHealthCheckConfiguration.timeoutRange.upperBound)
            )
        }
    }
}
