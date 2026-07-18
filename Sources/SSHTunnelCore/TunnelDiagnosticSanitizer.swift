import Foundation

public enum TunnelDiagnosticSanitizer {
    public static func sanitize(
        _ message: String,
        sensitiveValues: [String],
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        var result = message
        let values = Set(
            sensitiveValues
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 3 && !isPublicLoopbackValue($0) }
        )
        for value in values.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(
                of: value,
                with: "<redacted>",
                options: [.caseInsensitive]
            )
        }
        if !homeDirectory.isEmpty {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        return result
    }

    private static func isPublicLoopbackValue(_ value: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0", "*"].contains(value.lowercased())
    }
}
