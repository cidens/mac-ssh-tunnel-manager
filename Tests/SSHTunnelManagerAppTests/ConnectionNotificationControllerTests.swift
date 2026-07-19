import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@MainActor
@Test func notificationControllerRequestsPermissionOnlyWhenEnabling() async {
    let store = NotificationMemoryStore(settings: nil)
    let delivery = NotificationFakeDelivery(state: .notDetermined, requestResult: true)
    let controller = ConnectionNotificationController(store: store, delivery: delivery)

    await controller.start().value
    #expect(delivery.requestCount == 0)
    #expect(controller.isEnabled == false)

    #expect(await controller.setEnabled(true))
    #expect(delivery.requestCount == 1)
    #expect(controller.isEnabled)
    #expect(store.settings?.isEnabled == true)

    #expect(await controller.setEnabled(false))
    #expect(delivery.requestCount == 1)
    #expect(controller.isEnabled == false)
}

@MainActor
@Test func deniedNotificationPermissionDoesNotEnableOrSend() async {
    let store = NotificationMemoryStore(settings: nil)
    let delivery = NotificationFakeDelivery(state: .denied, requestResult: false)
    let controller = ConnectionNotificationController(store: store, delivery: delivery)

    await controller.start().value
    #expect(await controller.setEnabled(true) == false)
    await controller.deliverIfEnabled(
        .connectionFailed(category: .unknown, retryCount: 0, willRetry: false)
    )

    #expect(controller.isEnabled == false)
    #expect(delivery.events.isEmpty)
}

@MainActor
@Test func enabledNotificationControllerDeliversFailureAndRecovery() async {
    let store = NotificationMemoryStore(
        settings: ConnectionNotificationSettings(schemaVersion: 1, isEnabled: true)
    )
    let delivery = NotificationFakeDelivery(state: .authorized, requestResult: true)
    let controller = ConnectionNotificationController(store: store, delivery: delivery)

    await controller.start().value
    await controller.deliverIfEnabled(
        .connectionFailed(category: .network, retryCount: 2, willRetry: true)
    )
    await controller.deliverIfEnabled(.connectionRecovered)

    #expect(delivery.events == [
        .connectionFailed(category: .network, retryCount: 2, willRetry: true),
        .connectionRecovered
    ])
}

@MainActor
@Test func revokedPermissionDisablesPersistedNotificationsOnStartup() async {
    let store = NotificationMemoryStore(
        settings: ConnectionNotificationSettings(
            schemaVersion: ConnectionNotificationSettings.currentSchemaVersion,
            isEnabled: true
        )
    )
    let delivery = NotificationFakeDelivery(state: .denied, requestResult: false)
    let controller = ConnectionNotificationController(store: store, delivery: delivery)

    await controller.start().value

    #expect(!controller.isEnabled)
    #expect(controller.authorizationState == .denied)
    #expect(store.settings == .defaultSettings)
}

@MainActor
@Test func unavailableNotificationsDoNotCrashOrRewritePersistedPreference() async {
    let persisted = ConnectionNotificationSettings(
        schemaVersion: ConnectionNotificationSettings.currentSchemaVersion,
        isEnabled: true
    )
    let store = NotificationMemoryStore(settings: persisted)
    let controller = ConnectionNotificationController(
        store: store,
        delivery: UnavailableConnectionNotificationCenter()
    )

    await controller.start().value

    #expect(controller.authorizationState == .unsupported)
    #expect(controller.isEnabled)
    #expect(store.settings == persisted)
    #expect(!controller.errorMessage.isEmpty)
    #expect(await controller.setEnabled(true) == false)
    #expect(store.settings == persisted)
}

private final class NotificationMemoryStore: ConnectionNotificationSettingsStoring {
    var settings: ConnectionNotificationSettings?
    init(settings: ConnectionNotificationSettings?) { self.settings = settings }
    func load() throws -> ConnectionNotificationSettings? { settings }
    func save(_ settings: ConnectionNotificationSettings) throws { self.settings = settings }
}

@MainActor
private final class NotificationFakeDelivery: ConnectionNotificationDelivering {
    var state: ConnectionNotificationAuthorizationState
    let requestResult: Bool
    var requestCount = 0
    var events: [ConnectionNotificationEvent] = []

    init(state: ConnectionNotificationAuthorizationState, requestResult: Bool) {
        self.state = state
        self.requestResult = requestResult
    }

    func authorizationState() async -> ConnectionNotificationAuthorizationState { state }
    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        state = requestResult ? .authorized : .denied
        return requestResult
    }
    func deliver(_ event: ConnectionNotificationEvent) async throws {
        events.append(event)
    }
}
