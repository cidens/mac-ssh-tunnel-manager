import Foundation

public struct SSHStartCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}

public struct SSHCommandBuilder: Sendable {
    public init() {}

    public func validate(_ tunnel: TunnelConfig) throws {
        try validateNonEmpty(tunnel.name, field: "name")
        if tunnel.mode == .sshConfig {
            guard tunnel.rules.isEmpty else {
                throw TunnelValidationError.invalidRule(1, CoreStrings.string("error.sshConfigRulesForbidden"))
            }
            guard let sshConfigName = tunnel.sshConfigName else {
                throw TunnelValidationError.emptyField("sshConfigName")
            }
            try validateNonEmpty(sshConfigName, field: "sshConfigName")
            try validateHostLike(sshConfigName, field: "sshConfigName")
            return
        }

        try validateNonEmpty(tunnel.sshHost, field: "sshHost")
        try validateHostLike(tunnel.sshHost, field: "sshHost")
        let rules = tunnel.effectiveRules
        guard !rules.isEmpty else {
            throw TunnelValidationError.emptyField("rules")
        }
        guard rules.count <= TunnelConfig.maximumRuleCount else {
            throw TunnelValidationError.invalidRule(
                TunnelConfig.maximumRuleCount + 1,
                CoreStrings.format("error.tooManyRules", TunnelConfig.maximumRuleCount)
            )
        }
        for (index, rule) in rules.enumerated() {
            do {
                try validate(rule)
            } catch {
                throw TunnelValidationError.invalidRule(index + 1, error.localizedDescription)
            }
        }
    }

    public func validateForStart(_ tunnel: TunnelConfig) throws {
        try validate(tunnel)
        if tunnel.mode != .sshConfig, !tunnel.effectiveRules.contains(where: \.isEnabled) {
            throw TunnelValidationError.noEnabledRules
        }
    }

    public func validateLocalListenerHost(_ host: String) throws {
        try validateNonEmpty(host, field: "localHost")
        try validateLocalForwardHostLike(host, field: "localHost")
    }

    private func validate(_ rule: TunnelForwardRule) throws {
        switch rule.mode {
        case .localForward:
            try validateNonEmpty(rule.localHost, field: "localHost")
            try validateNonEmpty(rule.remoteHost, field: "remoteHost")
            try validateLocalForwardHostLike(rule.localHost, field: "localHost")
            try validateRemoteForwardHostLike(rule.remoteHost, field: "remoteHost")
            try validatePort(rule.localPort, field: "localPort")
            try validatePort(rule.remotePort, field: "remotePort")
        case .remoteForward:
            try validateNonEmpty(rule.remoteHost, field: "remoteHost")
            try validateNonEmpty(rule.localHost, field: "localHost")
            try validateLocalForwardHostLike(rule.remoteHost, field: "remoteHost")
            try validateRemoteForwardHostLike(rule.localHost, field: "localHost")
            try validatePort(rule.remotePort, field: "remotePort")
            try validatePort(rule.localPort, field: "localPort")
        case .dynamicForward:
            try validateNonEmpty(rule.localHost, field: "localHost")
            try validateLocalForwardHostLike(rule.localHost, field: "localHost")
            try validatePort(rule.localPort, field: "localPort")
        case .sshConfig:
            throw TunnelValidationError.invalidHost("rules")
        }
    }

    public func buildStartCommand(for tunnel: TunnelConfig) -> SSHStartCommand {
        if tunnel.mode == .sshConfig {
            return SSHStartCommand(
                executable: "/usr/bin/ssh",
                arguments: [
                    "-N",
                    "-o", "ExitOnForwardFailure=yes",
                    "-o", "ServerAliveInterval=30",
                    tunnel.sshConfigName ?? ""
                ]
            )
        }

        var arguments = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30"
        ]
        for rule in tunnel.effectiveRules where rule.isEnabled {
            switch rule.mode {
            case .localForward:
                arguments += ["-L", "\(rule.localHost):\(rule.localPort):\(rule.remoteHost):\(rule.remotePort)"]
            case .remoteForward:
                arguments += ["-R", "\(rule.remoteHost):\(rule.remotePort):\(rule.localHost):\(rule.localPort)"]
            case .dynamicForward:
                arguments += ["-D", "\(rule.localHost):\(rule.localPort)"]
            case .sshConfig:
                break
            }
        }
        arguments.append(tunnel.sshHost)
        return SSHStartCommand(executable: "/usr/bin/ssh", arguments: arguments)
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
