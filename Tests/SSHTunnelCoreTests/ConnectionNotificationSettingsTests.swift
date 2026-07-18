import Foundation
import Testing
@testable import SSHTunnelCore

@Test func connectionNotificationsDefaultToDisabled() throws {
    let settings = ConnectionNotificationSettings.defaultSettings
    #expect(settings.schemaVersion == 1)
    #expect(settings.isEnabled == false)
    try settings.validate()
}

@Test func connectionNotificationStoreRoundTripsWithPrivatePermissions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-notification-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "nested/connection-notifications.json")
    let store = ConnectionNotificationSettingsStore(settingsURL: url)
    let settings = ConnectionNotificationSettings(
        schemaVersion: ConnectionNotificationSettings.currentSchemaVersion,
        isEnabled: true
    )

    try store.save(settings)

    #expect(try store.load() == settings)
    #expect(try notificationPermissions(of: url.deletingLastPathComponent()) == 0o700)
    #expect(try notificationPermissions(of: url) == 0o600)
}

@Test func connectionNotificationStoreRejectsUnknownSchemaVersion() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-notification-version-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "connection-notifications.json")
    try Data(#"{"schemaVersion":99,"isEnabled":true}"#.utf8).write(to: url)
    let store = ConnectionNotificationSettingsStore(settingsURL: url)

    #expect(throws: ConnectionNotificationSettingsError.unsupportedSchemaVersion(99)) {
        _ = try store.load()
    }
}

private func notificationPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
