import Foundation

public enum TunnelInputParser {
    public static func optionalURL(from rawValue: String) throws -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw TunnelValidationError.invalidURL("openURL")
        }
        return url
    }
}
