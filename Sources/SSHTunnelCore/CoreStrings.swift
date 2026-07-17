import Foundation

public enum CoreStrings {
    public static func string(_ key: String, language: String? = nil) -> String {
        string(key, language: language, defaultValue: key)
    }

    public static func string(_ key: String, language: String? = nil, defaultValue: String) -> String {
        if let language,
           let value = stringsDictionary(language: language)[key] {
            return value
        }

        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: resourceBundle,
            value: defaultValue,
            comment: ""
        )
    }

    public static func format(_ key: String, language: String? = nil, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, language: language),
            arguments: arguments
        )
    }

    public static func localizationKeys(language: String) throws -> Set<String> {
        Set(stringsDictionary(language: language).keys)
    }

    private static func stringsDictionary(language: String) -> [String: String] {
        guard let url = stringsURL(language: language),
              let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return [:]
        }
        return dictionary
    }

    private static func stringsURL(language: String) -> URL? {
        let languageDirectory = "\(language).lproj"
        if let url = resourceBundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: languageDirectory
        ) {
            return url
        }

        return resourceBundle.urls(forResourcesWithExtension: "strings", subdirectory: nil)?
            .first { url in
                url.lastPathComponent == "Localizable.strings"
                    && url.deletingLastPathComponent().lastPathComponent.lowercased() == languageDirectory.lowercased()
            }
    }

    private static let resourceBundle: Bundle = {
        let bundleName = "ssh-tunnel-manager_SSHTunnelCore.bundle"
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let bundle = Bundle(url: resourceURL) {
            return bundle
        }
        return Bundle.module
    }()
}
