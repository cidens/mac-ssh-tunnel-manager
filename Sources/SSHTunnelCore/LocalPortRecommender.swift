import Foundation

public struct LocalPortEndpoint: Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public struct LocalPortOccupancyIndex: Sendable {
    private struct PortOccupancy: Sendable {
        var hasWildcard = false
        var hosts = Set<String>()
    }

    public static let minimumPort = 1_024
    public static let maximumPort = 65_535

    private let occupancies: [Int: PortOccupancy]

    public init(endpoints: some Sequence<LocalPortEndpoint>) {
        var values: [Int: PortOccupancy] = [:]
        values.reserveCapacity(endpoints.underestimatedCount)
        for endpoint in endpoints where (Self.minimumPort...Self.maximumPort).contains(endpoint.port) {
            let host = Self.normalizedHost(endpoint.host)
            var occupancy = values[endpoint.port] ?? PortOccupancy()
            if Self.isWildcardHost(host) {
                occupancy.hasWildcard = true
            } else {
                occupancy.hosts.insert(host)
            }
            values[endpoint.port] = occupancy
        }
        occupancies = values
    }

    public func isOccupied(host: String, port: Int) -> Bool {
        guard let occupancy = occupancies[port] else { return false }
        let requestedHost = Self.normalizedHost(host)
        if Self.isWildcardHost(requestedHost) {
            return occupancy.hasWildcard || !occupancy.hosts.isEmpty
        }
        if occupancy.hasWildcard {
            return true
        }
        if requestedHost == "localhost" {
            return !occupancy.hosts.isDisjoint(with: Self.loopbackHosts)
        }
        if Self.loopbackHosts.contains(requestedHost), occupancy.hosts.contains("localhost") {
            return true
        }
        return occupancy.hosts.contains(requestedHost)
    }

    public func firstAvailablePort(host: String, startingAfter requestedPort: Int?) -> Int? {
        let startingPort = requestedPort.flatMap {
            (Self.minimumPort...Self.maximumPort).contains($0) ? $0 : nil
        } ?? (Self.minimumPort - 1)

        if startingPort < Self.maximumPort {
            for port in (startingPort + 1)...Self.maximumPort where !isOccupied(host: host, port: port) {
                return port
            }
        }
        if startingPort > Self.minimumPort {
            for port in Self.minimumPort..<startingPort where !isOccupied(host: host, port: port) {
                return port
            }
        }
        return nil
    }

    public static func hostsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedHost(lhs)
        let right = normalizedHost(rhs)
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
