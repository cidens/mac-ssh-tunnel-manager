import Foundation
import SSHTunnelCore
import UserNotifications

enum ConnectionNotificationAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case failed
    case unsupported
}

enum ConnectionNotificationEvent: Equatable {
    case connectionFailed(category: TunnelFailureCategory, retryCount: Int, willRetry: Bool)
    case connectionRecovered
}

protocol ConnectionNotificationSettingsStoring {
    func load() throws -> ConnectionNotificationSettings?
    func save(_ settings: ConnectionNotificationSettings) throws
}

extension ConnectionNotificationSettingsStore: ConnectionNotificationSettingsStoring {}

@MainActor
protocol ConnectionNotificationDelivering: AnyObject {
    func authorizationState() async -> ConnectionNotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func deliver(_ event: ConnectionNotificationEvent) async throws
}

@MainActor
protocol ConnectionNotificationSending: AnyObject {
    func send(_ event: ConnectionNotificationEvent)
}

@MainActor
final class UnavailableConnectionNotificationCenter: ConnectionNotificationDelivering {
    func authorizationState() async -> ConnectionNotificationAuthorizationState { .unsupported }
    func requestAuthorization() async throws -> Bool { false }
    func deliver(_ event: ConnectionNotificationEvent) async throws {}
}

@MainActor
final class SystemConnectionNotificationCenter: NSObject, ConnectionNotificationDelivering,
    @preconcurrency UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func authorizationState() async -> ConnectionNotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        @unknown default: return .failed
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ event: ConnectionNotificationEvent) async throws {
        let content = UNMutableNotificationContent()
        switch event {
        case let .connectionFailed(category, retryCount, willRetry):
            content.title = AppStrings.notificationFailureTitle()
            content.body = AppStrings.notificationFailureBody(
                category: category,
                retryCount: retryCount,
                willRetry: willRetry
            )
        case .connectionRecovered:
            content.title = AppStrings.notificationRecoveryTitle()
            content.body = AppStrings.notificationRecoveryBody()
        }
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor
final class ConnectionNotificationController: ObservableObject, ConnectionNotificationSending {
    @Published private(set) var isEnabled = false
    @Published private(set) var authorizationState: ConnectionNotificationAuthorizationState = .notDetermined
    @Published private(set) var errorMessage = ""

    private let store: any ConnectionNotificationSettingsStoring
    private let delivery: any ConnectionNotificationDelivering

    init(
        store: any ConnectionNotificationSettingsStoring,
        delivery: any ConnectionNotificationDelivering
    ) {
        self.store = store
        self.delivery = delivery
    }

    @discardableResult
    func start() -> Task<Void, Never> {
        do {
            isEnabled = try store.load()?.isEnabled ?? false
        } catch {
            isEnabled = false
            errorMessage = AppStrings.notificationSettingsLoadFailed()
        }
        return Task { [weak self] in
            guard let self else { return }
            let state = await delivery.authorizationState()
            self.authorizationState = state
            if state == .unsupported {
                errorMessage = AppStrings.notificationUnavailableOutsideApp()
            } else if isEnabled, state != .authorized {
                isEnabled = false
                try? store.save(.defaultSettings)
            }
        }
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        errorMessage = ""
        if enabled {
            if await delivery.authorizationState() == .unsupported {
                authorizationState = .unsupported
                errorMessage = AppStrings.notificationUnavailableOutsideApp()
                return false
            }
            do {
                guard try await delivery.requestAuthorization() else {
                    authorizationState = .denied
                    isEnabled = false
                    try? store.save(.defaultSettings)
                    return false
                }
                authorizationState = .authorized
            } catch {
                authorizationState = .failed
                isEnabled = false
                errorMessage = AppStrings.notificationPermissionFailed()
                return false
            }
        }

        let candidate = ConnectionNotificationSettings(
            schemaVersion: ConnectionNotificationSettings.currentSchemaVersion,
            isEnabled: enabled
        )
        do {
            try store.save(candidate)
            isEnabled = enabled
            if !enabled { authorizationState = await delivery.authorizationState() }
            return true
        } catch {
            errorMessage = AppStrings.notificationSettingsSaveFailed()
            return false
        }
    }

    func send(_ event: ConnectionNotificationEvent) {
        Task { [weak self] in
            await self?.deliverIfEnabled(event)
        }
    }

    func deliverIfEnabled(_ event: ConnectionNotificationEvent) async {
        guard isEnabled, authorizationState == .authorized else { return }
        do {
            try await delivery.deliver(event)
        } catch {
            errorMessage = AppStrings.notificationDeliveryFailed()
        }
    }
}

@MainActor
final class DisabledConnectionNotificationSender: ConnectionNotificationSending {
    static let shared = DisabledConnectionNotificationSender()
    private init() {}
    func send(_ event: ConnectionNotificationEvent) {}
}
