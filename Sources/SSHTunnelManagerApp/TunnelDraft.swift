import Foundation
import SSHTunnelCore

enum TunnelConfigurationKind: String, CaseIterable, Equatable {
    case connectionGroup
    case sshConfigReference
}

struct TunnelRuleDraft: Identifiable, Equatable {
    var id = UUID()
    var mode: TunnelMode = .localForward {
        didSet {
            if mode == .remoteForward && oldValue != .remoteForward && remoteHost.isEmpty {
                remoteHost = "localhost"
            }
        }
    }
    var localHost = "127.0.0.1"
    var localPort = ""
    var remoteHost = ""
    var remotePort = ""
    var openURL = ""
    var isEnabled = true
    var riskConfirmationSignature: String?

    var hasRequiredFields: Bool {
        guard mode != .sshConfig,
              !localHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.isValidPort(localPort) else { return false }
        return mode == .dynamicForward || (
            !remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.isValidPort(remotePort)
        )
    }

    var compactEndpointSummary: String {
        let local = Self.endpoint(host: localHost, port: localPort)
        switch mode {
        case .localForward:
            return "\(local) → \(Self.endpoint(host: remoteHost, port: remotePort))"
        case .remoteForward:
            return "\(Self.endpoint(host: remoteHost, port: remotePort)) → \(local)"
        case .dynamicForward:
            return local
        case .sshConfig:
            return "—"
        }
    }

    var localPortRecommendationFingerprint: LocalPortRecommendationFingerprint? {
        guard mode == .localForward || mode == .dynamicForward else { return nil }
        let host = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        return LocalPortRecommendationFingerprint(
            ruleID: id,
            mode: mode,
            host: host,
            portText: localPort.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    init() {}

    init(rule: TunnelForwardRule) {
        id = rule.id
        mode = rule.mode
        localHost = rule.localHost
        localPort = rule.localPort == 0 ? "" : String(rule.localPort)
        remoteHost = rule.remoteHost
        remotePort = rule.remotePort == 0 ? "" : String(rule.remotePort)
        openURL = rule.openURL?.absoluteString ?? ""
        isEnabled = rule.isEnabled
        riskConfirmationSignature = rule.riskConfirmationSignature
    }

    func makeRule() throws -> TunnelForwardRule {
        guard mode != .sshConfig else { throw TunnelValidationError.invalidHost("rules") }
        guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw TunnelValidationError.invalidPort("localPort")
        }
        let remotePortNumber: Int
        if mode == .dynamicForward {
            remotePortNumber = 0
        } else if let value = Int(remotePort.trimmingCharacters(in: .whitespacesAndNewlines)) {
            remotePortNumber = value
        } else {
            throw TunnelValidationError.invalidPort("remotePort")
        }
        let url = try TunnelInputParser.optionalURL(from: openURL)
        var rule = TunnelForwardRule(
            id: id,
            mode: mode,
            localHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
            localPort: localPortNumber,
            remoteHost: mode == .dynamicForward ? "" : remoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
            remotePort: remotePortNumber,
            openURL: url,
            isEnabled: isEnabled,
            riskConfirmationSignature: riskConfirmationSignature
        )
        if !rule.hasValidRiskConfirmation {
            rule.riskConfirmationSignature = nil
        }
        return rule
    }

    private static func isValidPort(_ value: String) -> Bool {
        guard let port = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (1...65_535).contains(port)
    }

    private static func endpoint(host: String, port: String) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedHost.isEmpty ? "—" : normalizedHost):\(normalizedPort.isEmpty ? "—" : normalizedPort)"
    }
}

struct LocalPortRecommendationFingerprint: Equatable, Sendable {
    let ruleID: UUID
    let mode: TunnelMode
    let host: String
    let portText: String
}

struct TunnelDraft: Equatable {
    var mode: TunnelMode = .localForward {
        didSet {
            if mode == .remoteForward && oldValue != .remoteForward {
                remoteHost = "localhost"
            }
        }
    }
    var name = ""
    var sshHost = ""
    var localHost = ""
    var localPort = ""
    var remoteHost = ""
    var remotePort = ""
    var sshConfigName = ""
    var openURL = ""
    var tags = ""
    var isAutoReconnectEnabled = false
    var isAutoStartEnabled = false
    var primaryRuleID = UUID()
    var isPrimaryRuleEnabled = true
    var primaryRiskConfirmationSignature: String?
    var additionalRules: [TunnelRuleDraft] = []

    var configurationKind: TunnelConfigurationKind {
        get { mode == .sshConfig ? .sshConfigReference : .connectionGroup }
        set {
            switch newValue {
            case .connectionGroup where mode == .sshConfig:
                mode = .localForward
            case .sshConfigReference:
                mode = .sshConfig
            default:
                break
            }
        }
    }

    var rules: [TunnelRuleDraft] {
        get {
            guard mode != .sshConfig else { return [] }
            var primary = TunnelRuleDraft()
            primary.id = primaryRuleID
            primary.mode = mode
            primary.localHost = localHost
            primary.localPort = localPort
            primary.remoteHost = remoteHost
            primary.remotePort = remotePort
            primary.openURL = openURL
            primary.isEnabled = isPrimaryRuleEnabled
            primary.riskConfirmationSignature = primaryRiskConfirmationSignature
            return [primary] + additionalRules
        }
        set {
            guard let primary = newValue.first else { return }
            primaryRuleID = primary.id
            mode = primary.mode
            localHost = primary.localHost
            localPort = primary.localPort
            remoteHost = primary.remoteHost
            remotePort = primary.remotePort
            openURL = primary.openURL
            isPrimaryRuleEnabled = primary.isEnabled
            primaryRiskConfirmationSignature = primary.riskConfirmationSignature
            additionalRules = Array(newValue.dropFirst())
        }
    }

    var canAddRule: Bool {
        configurationKind == .connectionGroup
            && rules.count < TunnelConfig.maximumRuleCount
            && rules.allSatisfy(\.hasRequiredFields)
    }

    var hasReachedRuleLimit: Bool {
        rules.count >= TunnelConfig.maximumRuleCount
    }

    func hasSameEditableContent(as other: TunnelDraft) -> Bool {
        guard configurationKind == other.configurationKind,
              name == other.name,
              tags == other.tags,
              isAutoReconnectEnabled == other.isAutoReconnectEnabled,
              isAutoStartEnabled == other.isAutoStartEnabled else {
            return false
        }
        switch configurationKind {
        case .connectionGroup:
            return sshHost == other.sshHost && rules == other.rules
        case .sshConfigReference:
            return sshConfigName == other.sshConfigName && openURL == other.openURL
        }
    }

    @discardableResult
    mutating func removeRule(id: UUID) -> Bool {
        var currentRules = rules
        guard currentRules.count > 1,
              let index = currentRules.firstIndex(where: { $0.id == id }) else {
            return false
        }
        currentRules.remove(at: index)
        rules = currentRules
        return true
    }

    @discardableResult
    mutating func applyRecommendedLocalPort(_ port: Int, to ruleID: UUID) -> Bool {
        guard (LocalPortOccupancyIndex.minimumPort...LocalPortOccupancyIndex.maximumPort).contains(port) else {
            return false
        }
        var currentRules = rules
        guard let index = currentRules.firstIndex(where: { $0.id == ruleID }),
              currentRules[index].mode == .localForward || currentRules[index].mode == .dynamicForward else {
            return false
        }

        var rule = currentRules[index]
        let previousPort = Int(rule.localPort.trimmingCharacters(in: .whitespacesAndNewlines))
        rule.openURL = Self.updatedOpenURL(
            rule.openURL,
            listenerHost: rule.localHost,
            previousPort: previousPort,
            recommendedPort: port
        )
        rule.localPort = String(port)
        rule.riskConfirmationSignature = nil
        currentRules[index] = rule
        rules = currentRules
        return true
    }

    init() {}

    init(tunnel: TunnelConfig) {
        mode = tunnel.mode
        name = tunnel.name
        openURL = tunnel.openURL?.absoluteString ?? ""
        tags = tunnel.tags.joined(separator: ", ")
        isAutoReconnectEnabled = tunnel.isAutoReconnectEnabled
        isAutoStartEnabled = tunnel.isAutoStartEnabled

        if tunnel.mode != .sshConfig, let primary = tunnel.effectiveRules.first {
            primaryRuleID = primary.id
            isPrimaryRuleEnabled = primary.isEnabled
            primaryRiskConfirmationSignature = primary.riskConfirmationSignature
            additionalRules = tunnel.effectiveRules.dropFirst().map(TunnelRuleDraft.init(rule:))
        }

        switch tunnel.mode {
        case .localForward, .remoteForward:
            sshHost = tunnel.sshHost
            localHost = tunnel.localHost
            localPort = String(tunnel.localPort)
            remoteHost = tunnel.remoteHost
            remotePort = String(tunnel.remotePort)
        case .dynamicForward:
            sshHost = tunnel.sshHost
            localHost = tunnel.localHost
            localPort = String(tunnel.localPort)
        case .sshConfig:
            sshConfigName = tunnel.sshConfigName ?? ""
        }
    }

    func makeConfig(id: TunnelConfig.ID = UUID()) throws -> TunnelConfig {
        let normalizedTags = try TunnelConfig.normalizedTags(tags.components(separatedBy: ","))
        switch mode {
        case .sshConfig:
            let url = try TunnelInputParser.optionalURL(from: openURL)
            var config = TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshConfigName: sshConfigName.trimmingCharacters(in: .whitespacesAndNewlines),
                openURL: url
            )
            config.tags = normalizedTags
            config.isAutoReconnectEnabled = isAutoReconnectEnabled
            config.isAutoStartEnabled = isAutoStartEnabled
            return config
        case .dynamicForward:
            guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("localPort")
            }
            let url = try TunnelInputParser.optionalURL(from: openURL)

            var config = TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: localPortNumber,
                openURL: url
            )
            config.tags = normalizedTags
            config.isAutoReconnectEnabled = isAutoReconnectEnabled
            config.isAutoStartEnabled = isAutoStartEnabled
            try applyRules(to: &config)
            return config
        case .remoteForward:
            guard let remotePortNumber = Int(remotePort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("remotePort")
            }
            guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("localPort")
            }
            let url = try TunnelInputParser.optionalURL(from: openURL)

            var config = TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
                remoteBindHost: remoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePort: remotePortNumber,
                localTargetHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: localPortNumber,
                openURL: url
            )
            config.tags = normalizedTags
            config.isAutoReconnectEnabled = isAutoReconnectEnabled
            config.isAutoStartEnabled = isAutoStartEnabled
            try applyRules(to: &config)
            return config
        case .localForward:
            guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("localPort")
            }
            guard let remotePortNumber = Int(remotePort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("remotePort")
            }
            let url = try TunnelInputParser.optionalURL(from: openURL)

            var config = TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: localPortNumber,
                remoteHost: remoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePort: remotePortNumber,
                openURL: url
            )
            config.tags = normalizedTags
            config.isAutoReconnectEnabled = isAutoReconnectEnabled
            config.isAutoStartEnabled = isAutoStartEnabled
            try applyRules(to: &config)
            return config
        }
    }

    private func applyRules(to config: inout TunnelConfig) throws {
        guard var primary = config.rules.first else { return }
        primary.id = primaryRuleID
        primary.isEnabled = isPrimaryRuleEnabled
        primary.riskConfirmationSignature = primaryRiskConfirmationSignature
        if !primary.hasValidRiskConfirmation {
            primary.riskConfirmationSignature = nil
        }
        let remaining = try additionalRules.map { try $0.makeRule() }
        config.replaceRules([primary] + remaining)
    }

    private static func updatedOpenURL(
        _ value: String,
        listenerHost: String,
        previousPort: Int?,
        recommendedPort: Int
    ) -> String {
        guard let previousPort,
              var components = URLComponents(string: value),
              let urlHost = components.host,
              components.port == previousPort,
              LocalPortOccupancyIndex.hostsOverlap(listenerHost, urlHost) else {
            return value
        }
        components.port = recommendedPort
        return components.string ?? value
    }
}
