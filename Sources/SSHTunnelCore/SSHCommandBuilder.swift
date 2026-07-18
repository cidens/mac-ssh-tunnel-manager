import Foundation

public struct SSHStartCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}

public struct SSHCommandBuilder: Sendable {
    public init() {}

    public func validate(_ tunnel: TunnelConfig) throws {
        try validateNonEmpty(tunnel.name, field: "name")
        switch tunnel.mode {
        case .localForward:
            try validateNonEmpty(tunnel.sshHost, field: "sshHost")
            try validateNonEmpty(tunnel.localHost, field: "localHost")
            try validateNonEmpty(tunnel.remoteHost, field: "remoteHost")
            try validateHostLike(tunnel.sshHost, field: "sshHost")
            try validateLocalForwardHostLike(tunnel.localHost, field: "localHost")
            try validateRemoteForwardHostLike(tunnel.remoteHost, field: "remoteHost")
            try validatePort(tunnel.localPort, field: "localPort")
            try validatePort(tunnel.remotePort, field: "remotePort")
        case .remoteForward:
            try validateNonEmpty(tunnel.sshHost, field: "sshHost")
            try validateNonEmpty(tunnel.remoteHost, field: "remoteHost")
            try validateNonEmpty(tunnel.localHost, field: "localHost")
            try validateHostLike(tunnel.sshHost, field: "sshHost")
            try validateLocalForwardHostLike(tunnel.remoteHost, field: "remoteHost")
            try validateRemoteForwardHostLike(tunnel.localHost, field: "localHost")
            try validatePort(tunnel.remotePort, field: "remotePort")
            try validatePort(tunnel.localPort, field: "localPort")
        case .dynamicForward:
            try validateNonEmpty(tunnel.sshHost, field: "sshHost")
            try validateNonEmpty(tunnel.localHost, field: "localHost")
            try validateHostLike(tunnel.sshHost, field: "sshHost")
            try validateLocalForwardHostLike(tunnel.localHost, field: "localHost")
            try validatePort(tunnel.localPort, field: "localPort")
        case .sshConfig:
            guard let sshConfigName = tunnel.sshConfigName else {
                throw TunnelValidationError.emptyField("sshConfigName")
            }
            try validateNonEmpty(sshConfigName, field: "sshConfigName")
            try validateHostLike(sshConfigName, field: "sshConfigName")
        }
    }

    public func buildStartCommand(for tunnel: TunnelConfig) -> SSHStartCommand {
        let arguments: [String]
        switch tunnel.mode {
        case .localForward:
            arguments = [
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                "-L", "\(tunnel.localHost):\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)",
                tunnel.sshHost
            ]
        case .remoteForward:
            arguments = [
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                "-R", "\(tunnel.remoteHost):\(tunnel.remotePort):\(tunnel.localHost):\(tunnel.localPort)",
                tunnel.sshHost
            ]
        case .dynamicForward:
            arguments = [
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                "-D", "\(tunnel.localHost):\(tunnel.localPort)",
                tunnel.sshHost
            ]
        case .sshConfig:
            arguments = [
                "-N",
                "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=30",
                tunnel.sshConfigName ?? ""
            ]
        }

        return SSHStartCommand(
            executable: "/usr/bin/ssh",
            arguments: arguments
        )
    }

    private func validateNonEmpty(_ value: String, field: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TunnelValidationError.emptyField(field)
        }
    }

    private func validatePort(_ value: Int, field: String) throws {
        guard (1...65_535).contains(value) else {
            throw TunnelValidationError.invalidPort(field)
        }
    }

    private func validateHostLike(_ value: String, field: String) throws {
        if value.hasPrefix("-") {
            throw TunnelValidationError.invalidHost(field)
        }

        let forbidden = CharacterSet.whitespacesAndNewlines
            .union(.controlCharacters)
            .union(CharacterSet(charactersIn: "\"'`;$|&(){}<>\\*"))
        guard value.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw TunnelValidationError.invalidHost(field)
        }
    }

    private func validateLocalForwardHostLike(_ value: String, field: String) throws {
        if value == "*" {
            return
        }
        try validateForwardHostLike(value, field: field)
    }

    private func validateForwardHostLike(_ value: String, field: String) throws {
        try validateHostLike(value, field: field)

        let isBracketedIPv6 = value.hasPrefix("[") && value.hasSuffix("]")
        if isBracketedIPv6 {
            let innerStart = value.index(after: value.startIndex)
            let innerEnd = value.index(before: value.endIndex)
            guard innerStart < innerEnd,
                  value[innerStart..<innerEnd].contains(":") else {
                throw TunnelValidationError.invalidHost(field)
            }
        }
        if value.contains(":") && !isBracketedIPv6 {
            throw TunnelValidationError.invalidHost(field)
        }
        if value.contains("[") || value.contains("]") {
            guard isBracketedIPv6 else {
                throw TunnelValidationError.invalidHost(field)
            }
        }
    }

    private func validateRemoteForwardHostLike(_ value: String, field: String) throws {
        try validateForwardHostLike(value, field: field)
    }
}
