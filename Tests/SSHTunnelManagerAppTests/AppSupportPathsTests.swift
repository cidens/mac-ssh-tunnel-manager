import Foundation
import Testing
@testable import SSHTunnelManagerApp

@Test func applicationSupportOverrideRequiresAnAbsolutePath() {
    let fallback = URL(filePath: "/private/tmp/default-app-support", directoryHint: .isDirectory)

    let overridden = AppSupportPaths.directory(
        environment: [
            AppSupportPaths.overrideEnvironmentKey: "  /private/tmp/isolated-ssh-tunnel-manager  "
        ],
        defaultApplicationSupportDirectory: fallback
    )
    let relative = AppSupportPaths.directory(
        environment: [AppSupportPaths.overrideEnvironmentKey: "relative/path"],
        defaultApplicationSupportDirectory: fallback
    )

    #expect(overridden.path == "/private/tmp/isolated-ssh-tunnel-manager")
    #expect(relative.path == "/private/tmp/default-app-support/ssh-tunnel-manager")
}
