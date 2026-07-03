import Foundation
import SSHTunnelCore

struct TunnelDraft {
    var mode: TunnelMode = .localForward
    var name = ""
    var sshHost = ""
    var localHost = ""
    var localPort = ""
    var remoteHost = ""
    var remotePort = ""
    var sshConfigName = ""
    var openURL = ""

    init() {}

    init(tunnel: TunnelConfig) {
        mode = tunnel.mode
        name = tunnel.name
        openURL = tunnel.openURL?.absoluteString ?? ""

        switch tunnel.mode {
        case .localForward:
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
        switch mode {
        case .sshConfig:
            let url = try TunnelInputParser.optionalURL(from: openURL)
            return TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshConfigName: sshConfigName.trimmingCharacters(in: .whitespacesAndNewlines),
                openURL: url
            )
        case .dynamicForward:
            guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("localPort")
            }
            let url = try TunnelInputParser.optionalURL(from: openURL)

            return TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: localPortNumber,
                openURL: url
            )
        case .localForward:
            guard let localPortNumber = Int(localPort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("localPort")
            }
            guard let remotePortNumber = Int(remotePort.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TunnelValidationError.invalidPort("remotePort")
            }
            let url = try TunnelInputParser.optionalURL(from: openURL)

            return TunnelConfig(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sshHost: sshHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localHost: localHost.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: localPortNumber,
                remoteHost: remoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePort: remotePortNumber,
                openURL: url
            )
        }
    }
}
