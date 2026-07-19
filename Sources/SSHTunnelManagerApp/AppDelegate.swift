import AppKit
import SSHTunnelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: TunnelManager?
    private var shortcutController: GlobalShortcutController?
    private var notificationController: ConnectionNotificationController?
    private var loginItemController: LoginItemController?
    private var menuCoordinator: MenuPresentationCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notificationDelivery: any ConnectionNotificationDelivering = if Self.isPackagedApplication {
            SystemConnectionNotificationCenter()
        } else {
            UnavailableConnectionNotificationCenter()
        }
        let notificationController = ConnectionNotificationController(
            store: ConnectionNotificationSettingsStore(settingsURL: Self.notificationSettingsURL()),
            delivery: notificationDelivery
        )
        let manager = TunnelManager(notificationSender: notificationController)
        let loginItemController = LoginItemController()
        let registrar = CarbonGlobalShortcutRegistrar()
        let conflictChecker = CarbonSystemShortcutConflictChecker()
        let shortcutController = GlobalShortcutController(
            store: GlobalShortcutSettingsStore(settingsURL: Self.defaultSettingsURL()),
            registrar: registrar,
            conflictChecker: conflictChecker
        )
        let menuCoordinator = MenuPresentationCoordinator(
            manager: manager,
            shortcutController: shortcutController,
            notificationController: notificationController,
            loginItemController: loginItemController
        )
        shortcutController.setTriggerAction { [weak menuCoordinator] in
            menuCoordinator?.toggleFromGlobalShortcut()
        }

        self.manager = manager
        self.shortcutController = shortcutController
        self.notificationController = notificationController
        self.loginItemController = loginItemController
        self.menuCoordinator = menuCoordinator
        shortcutController.start()
        if ProcessInfo.processInfo.environment["SSH_TUNNEL_MANAGER_SHOW_PANEL"] == "1" {
            menuCoordinator.showAndFocus()
        }
        let notificationStartupTask = notificationController.start()
        Task { @MainActor in
            await notificationStartupTask.value
            manager.startAutomaticallyConfiguredTunnels()
        }
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

    private static func notificationSettingsURL() -> URL {
        defaultSettingsURL()
            .deletingLastPathComponent()
            .appending(path: "connection-notifications.json")
    }

    private static var isPackagedApplication: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
