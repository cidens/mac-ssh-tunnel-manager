import Foundation

public enum SSHConfigOutputParser {
    public static func hasLocalForward(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains { $0.hasPrefix("localforward ") }
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
}
