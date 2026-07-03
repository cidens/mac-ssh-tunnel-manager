import Foundation
import SSHTunnelCore

enum AppStrings {
    static func string(_ key: String, language: String? = nil) -> String {
        string(key, language: language, defaultValue: key)
    }

    static func string(_ key: String, language: String? = nil, defaultValue: String) -> String {
        if let language,
           let value = stringsDictionary(language: language)[key] {
            return value
        }

        return NSLocalizedString(
            key,
            tableName: nil,
            bundle: Bundle.module,
            value: defaultValue,
            comment: ""
        )
    }

    static func format(_ key: String, language: String? = nil, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, language: language),
            arguments: arguments
        )
    }

    static func localizationKeys(language: String) throws -> Set<String> {
        Set(stringsDictionary(language: language).keys)
    }

    static func menuTitle(runningCount: Int, language: String? = nil) -> String {
        runningCount == 0
            ? string("menu.title.idle", language: language)
            : format("menu.title.running", language: language, runningCount)
    }

    static func modeName(_ mode: TunnelMode, language: String? = nil) -> String {
        switch mode {
        case .localForward:
            return modeLocalForward(language: language)
        case .dynamicForward:
            return modeDynamicForward(language: language)
        case .sshConfig:
            return modeSSHConfig(language: language)
        }
    }

    static func tunnelSummary(_ tunnel: TunnelConfig, language: String? = nil) -> String {
        switch tunnel.mode {
        case .localForward:
            return format(
                "row.summary.localForward",
                language: language,
                tunnel.localHost,
                tunnel.localPort,
                tunnel.sshHost,
                tunnel.remoteHost,
                tunnel.remotePort
            )
        case .dynamicForward:
            return format("row.summary.dynamicForward", language: language, tunnel.localHost, tunnel.localPort, tunnel.sshHost)
        case .sshConfig:
            return format("row.summary.sshConfig", language: language, tunnel.sshConfigName ?? "")
        }
    }

    static func failedToLoadTunnels(_ message: String, language: String? = nil) -> String {
        format("error.failedToLoadTunnels", language: language, message)
    }

    static func failedToSaveTunnels(_ message: String, language: String? = nil) -> String {
        format("error.failedToSaveTunnels", language: language, message)
    }

    static func localPortAlreadyListeningOutsideApp(host: String, port: Int, language: String? = nil) -> String {
        format("error.localPortAlreadyListeningOutsideApp", language: language, host, port)
    }

    static func stopBeforeEditing(language: String? = nil) -> String {
        string("error.stopBeforeEditing", language: language)
    }

    static func headerSubtitle(language: String? = nil) -> String {
        string("header.subtitle", language: language)
    }

    static func refresh(language: String? = nil) -> String {
        string("button.refresh", language: language)
    }

    static func refreshHelp(language: String? = nil) -> String {
        string("help.refresh", language: language)
    }

    static func emptyStateTitle(language: String? = nil) -> String {
        string("empty.title", language: language)
    }

    static func emptyStateBody(language: String? = nil) -> String {
        string("empty.body", language: language)
    }

    static func addTunnel(language: String? = nil) -> String {
        string("button.addTunnel", language: language)
    }

    static func collapseAddForm(language: String? = nil) -> String {
        string("button.collapseAddForm", language: language)
    }

    static func quit(language: String? = nil) -> String {
        string("button.quit", language: language)
    }

    static func quitHelp(language: String? = nil) -> String {
        string("help.quit", language: language)
    }

    static func stop(language: String? = nil) -> String {
        string("button.stop", language: language)
    }

    static func start(language: String? = nil) -> String {
        string("button.start", language: language)
    }

    static func open(language: String? = nil) -> String {
        string("button.open", language: language)
    }

    static func edit(language: String? = nil) -> String {
        string("button.edit", language: language)
    }

    static func collapseEdit(language: String? = nil) -> String {
        string("button.collapseEdit", language: language)
    }

    static func deleteTunnelHelp(language: String? = nil) -> String {
        string("help.deleteTunnel", language: language)
    }

    static func save(language: String? = nil) -> String {
        string("button.save", language: language)
    }

    static func update(language: String? = nil) -> String {
        string("button.update", language: language)
    }

    static func cancel(language: String? = nil) -> String {
        string("button.cancel", language: language)
    }

    static func formMode(language: String? = nil) -> String {
        string("form.mode", language: language)
    }

    static func formName(language: String? = nil) -> String {
        string("form.name", language: language)
    }

    static func formSSHHost(language: String? = nil) -> String {
        string("form.sshHost", language: language)
    }

    static func formLocal(language: String? = nil) -> String {
        string("form.local", language: language)
    }

    static func formSOCKS(language: String? = nil) -> String {
        string("form.socks", language: language)
    }

    static func formRemote(language: String? = nil) -> String {
        string("form.remote", language: language)
    }

    static func formPort(language: String? = nil) -> String {
        string("form.port", language: language)
    }

    static func formOpenURL(language: String? = nil) -> String {
        string("form.openURL", language: language)
    }

    static func modeLocalForward(language: String? = nil) -> String {
        string("mode.localForward", language: language)
    }

    static func modeDynamicForward(language: String? = nil) -> String {
        string("mode.dynamicForward", language: language)
    }

    static func modeSSHConfig(language: String? = nil) -> String {
        string("mode.sshConfig", language: language)
    }

    static func placeholderName(language: String? = nil) -> String {
        string("placeholder.name", language: language)
    }

    static func placeholderSSHHost(language: String? = nil) -> String {
        string("placeholder.sshHost", language: language)
    }

    static func placeholderPort(language: String? = nil) -> String {
        string("placeholder.port", language: language)
    }

    static func placeholderSSHConfig(language: String? = nil) -> String {
        string("placeholder.sshConfig", language: language)
    }

    static func placeholderOpenURL(language: String? = nil) -> String {
        string("placeholder.openURL", language: language)
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
        if let url = Bundle.module.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: languageDirectory
        ) {
            return url
        }

        return Bundle.module.urls(forResourcesWithExtension: "strings", subdirectory: nil)?
            .first { url in
                url.lastPathComponent == "Localizable.strings"
                    && url.deletingLastPathComponent().lastPathComponent.lowercased() == languageDirectory.lowercased()
            }
    }
}
