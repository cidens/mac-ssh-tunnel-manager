import Foundation

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
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains { line in
                line.hasPrefix("localforward ")
                    || line.hasPrefix("remoteforward ")
                    || line.hasPrefix("dynamicforward ")
            }
    }

    private static func bindHost(from endpoint: String) -> String {
        if endpoint.hasPrefix("["),
           let closingBracket = endpoint.firstIndex(of: "]") {
            return String(endpoint[...closingBracket])
        }

        guard let separator = endpoint.lastIndex(of: ":") else {
            return "localhost"
        }
        return String(endpoint[..<separator])
    }
}
