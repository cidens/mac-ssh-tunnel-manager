import Foundation

public enum SSHConfigForwardingKind: String, Equatable, Sendable {
    case local
    case remote
    case dynamic
}

public struct SSHConfigForwardingDirective: Equatable, Sendable {
    public let kind: SSHConfigForwardingKind
    public let listenHost: String
    public let listenPort: Int?
    public let target: String?
    public let isPotentiallyExposed: Bool

    public init(
        kind: SSHConfigForwardingKind,
        listenHost: String,
        listenPort: Int?,
        target: String?,
        isPotentiallyExposed: Bool
    ) {
        self.kind = kind
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.target = target
        self.isPotentiallyExposed = isPotentiallyExposed
    }
}

public enum SSHConfigOutputParser {
    public static func hasLocalForward(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains { $0.hasPrefix("localforward ") }
    }

    public static func localForwardBindHosts(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2,
                      fields[0].lowercased() == "localforward" else {
                    return nil
                }
                return bindHost(from: String(fields[1]))
            }
    }

    public static func hasAnyForwardingDirective(_ output: String) -> Bool {
        !forwardingDirectives(output).isEmpty
    }

    public static func forwardingDirectives(_ output: String) -> [SSHConfigForwardingDirective] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let gatewayPorts = lines.first { line in
            line.split(whereSeparator: \.isWhitespace).first?.lowercased() == "gatewayports"
        }?.split(whereSeparator: \.isWhitespace).dropFirst().first?.lowercased()

        return lines.compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2 else { return nil }
            let keyword = fields[0].lowercased()
            let kind: SSHConfigForwardingKind
            switch keyword {
            case "localforward": kind = .local
            case "remoteforward": kind = .remote
            case "dynamicforward": kind = .dynamic
            default: return nil
            }

            var endpoint = parsedEndpoint(fields[1])
            if (kind == .local || kind == .dynamic),
               !endpoint.hasExplicitHost,
               gatewayPorts == "yes" {
                endpoint.host = "*"
            }
            return SSHConfigForwardingDirective(
                kind: kind,
                listenHost: endpoint.host,
                listenPort: endpoint.port,
                target: fields.count >= 3 ? fields[2] : nil,
                isPotentiallyExposed: endpoint.port != nil && isPotentiallyExposed(endpoint.host)
            )
        }
    }

    private static func bindHost(from endpoint: String) -> String {
        parsedEndpoint(endpoint).host
    }

    private static func parsedEndpoint(_ endpoint: String) -> (host: String, port: Int?, hasExplicitHost: Bool) {
        if endpoint.hasPrefix("["),
           let closingBracket = endpoint.firstIndex(of: "]") {
            let host = String(endpoint[...closingBracket])
            let remainder = endpoint[endpoint.index(after: closingBracket)...]
            let portText = remainder.first == ":" ? remainder.dropFirst() : remainder
            return (host, Int(portText), true)
        }

        guard let separator = endpoint.lastIndex(of: ":") else {
            if let port = Int(endpoint) {
                return ("localhost", port, false)
            }
            return (endpoint, nil, true)
        }
        return (
            String(endpoint[..<separator]),
            Int(endpoint[endpoint.index(after: separator)...]),
            true
        )
    }

    private static func isPotentiallyExposed(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["127.0.0.1", "localhost", "::1", "[::1]"].contains(normalized)
    }
}
