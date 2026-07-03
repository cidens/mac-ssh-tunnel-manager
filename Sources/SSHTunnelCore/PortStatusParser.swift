import Foundation

public enum PortStatusParser {
    public static func isListening(lsofOutput: String, host: String, port: Int) -> Bool {
        return lsofOutput
            .split(whereSeparator: \.isNewline)
            .contains { line in
                guard line.contains("(LISTEN)"),
                      let endpoint = listeningEndpoint(from: String(line)) else {
                    return false
                }
                return endpoint.port == port && hostMatches(requested: host, actual: endpoint.host)
            }
    }

    private static func listeningEndpoint(from line: String) -> (host: String, port: Int)? {
        guard let tcpRange = line.range(of: "TCP "),
              let listenRange = line.range(of: " (LISTEN)", range: tcpRange.upperBound..<line.endIndex) else {
            return nil
        }

        let endpoint = String(line[tcpRange.upperBound..<listenRange.lowerBound])
        return parseEndpoint(endpoint)
    }

    private static func parseEndpoint(_ endpoint: String) -> (host: String, port: Int)? {
        if endpoint.hasPrefix("["),
           let closingBracket = endpoint.firstIndex(of: "]") {
            let afterBracket = endpoint.index(after: closingBracket)
            guard afterBracket < endpoint.endIndex,
                  endpoint[afterBracket] == ":" else {
                return nil
            }

            let portStart = endpoint.index(after: afterBracket)
            let portText = String(endpoint[portStart...])
            guard let port = Int(portText) else {
                return nil
            }
            return (String(endpoint[...closingBracket]), port)
        }

        guard let separator = endpoint.lastIndex(of: ":") else {
            return nil
        }

        let host = String(endpoint[..<separator])
        let portStart = endpoint.index(after: separator)
        guard let port = Int(String(endpoint[portStart...])) else {
            return nil
        }
        return (host, port)
    }

    private static func hostMatches(requested: String, actual: String) -> Bool {
        let requestedHost = normalizedHost(requested)
        let actualHost = normalizedHost(actual)
        if isWildcardHost(requestedHost) || isWildcardHost(actualHost) {
            return true
        }
        if requestedHost == "localhost" {
            return ["localhost", "127.0.0.1", "[::1]", "::1"].contains(actualHost)
        }
        if actualHost == "localhost" {
            return ["localhost", "127.0.0.1", "[::1]", "::1"].contains(requestedHost)
        }
        return requestedHost == actualHost
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isWildcardHost(_ host: String) -> Bool {
        ["*", "0.0.0.0", "::", "[::]"].contains(host)
    }
}
