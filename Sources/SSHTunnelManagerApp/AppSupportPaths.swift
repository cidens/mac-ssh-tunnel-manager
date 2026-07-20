import Foundation

enum AppSupportPaths {
    static let overrideEnvironmentKey = "SSH_TUNNEL_MANAGER_APPLICATION_SUPPORT_DIRECTORY"

    static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultApplicationSupportDirectory: URL? = nil
    ) -> URL {
        if let override = environment[overrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           override.hasPrefix("/") {
            return URL(filePath: override, directoryHint: .isDirectory).standardizedFileURL
        }

        let base = defaultApplicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appending(path: "ssh-tunnel-manager", directoryHint: .isDirectory)
    }
}
