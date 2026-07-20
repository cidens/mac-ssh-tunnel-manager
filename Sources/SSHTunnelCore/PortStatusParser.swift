import Foundation

public enum PortStatusParser {
    public static func isListening(lsofOutput: String, host: String, port: Int) -> Bool {
        listeningEndpoints(lsofOutput: lsofOutput).contains { endpoint in
            endpoint.port == port && LocalPortOccupancyIndex.hostsOverlap(host, endpoint.host)
        }
    }

    public static func listeningEndpoints(lsofOutput: String) -> [LocalPortEndpoint] {
        lsofOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard line.contains("(LISTEN)") else { return nil }
                return listeningEndpoint(from: String(line))
            }
    }

    private static func listeningEndpoint(from line: String) -> LocalPortEndpoint? {
        guard let tcpRange = line.range(of: "TCP "),
              let listenRange = line.range(of: " (LISTEN)", range: tcpRange.upperBound..<line.endIndex) else {
            return nil
        }

        let endpoint = String(line[tcpRange.upperBound..<listenRange.lowerBound])
        return parseEndpoint(endpoint)
    }

    private static func parseEndpoint(_ endpoint: String) -> LocalPortEndpoint? {
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
            return LocalPortEndpoint(host: String(endpoint[...closingBracket]), port: port)
        }

        guard let separator = endpoint.lastIndex(of: ":") else {
            return nil
        }

        let host = String(endpoint[..<separator])
        let portStart = endpoint.index(after: separator)
        guard let port = Int(String(endpoint[portStart...])) else {
            return nil
        }
        return LocalPortEndpoint(host: host, port: port)
    }
}
