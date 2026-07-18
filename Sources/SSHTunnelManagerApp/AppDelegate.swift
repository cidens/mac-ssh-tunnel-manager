import AppKit
import SSHTunnelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: TunnelManager?
    private var shortcutController: GlobalShortcutController?
    private var menuCoordinator: MenuPresentationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = TunnelManager()
        let registrar = CarbonGlobalShortcutRegistrar()
        let conflictChecker = CarbonSystemShortcutConflictChecker()
        let shortcutController = GlobalShortcutController(
            store: GlobalShortcutSettingsStore(settingsURL: Self.defaultSettingsURL()),
            registrar: registrar,
            conflictChecker: conflictChecker
        )
        let menuCoordinator = MenuPresentationCoordinator(
            manager: manager,
            shortcutController: shortcutController
        )
        shortcutController.setTriggerAction { [weak menuCoordinator] in
            menuCoordinator?.toggleFromGlobalShortcut()
        }

        self.manager = manager
        self.shortcutController = shortcutController
        self.menuCoordinator = menuCoordinator
        shortcutController.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuCoordinator?.showAndFocus()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutController?.prepareForTermination()
    }

    private static func defaultSettingsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appending(path: "ssh-tunnel-manager", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }
}
