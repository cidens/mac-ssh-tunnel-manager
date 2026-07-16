import Foundation
import Testing
@testable import SSHTunnelCore

@Test func globalShortcutDefaultsToControlOptionCommandT() throws {
    let settings = GlobalShortcutSettings.defaultSettings

    #expect(settings.schemaVersion == 1)
    #expect(settings.isEnabled)
    #expect(settings.shortcut.keyCode == 0x11)
    #expect(settings.shortcut.modifiers == [.control, .option, .command])
    try settings.validate()
}

@Test func globalShortcutRejectsUnsafeCombinations() {
    #expect(throws: GlobalShortcutValidationError.missingRequiredModifier) {
        try GlobalShortcut(keyCode: 0x00, modifiers: []).validate()
    }
    #expect(throws: GlobalShortcutValidationError.missingRequiredModifier) {
        try GlobalShortcut(keyCode: 0x00, modifiers: [.shift]).validate()
    }
    #expect(throws: GlobalShortcutValidationError.unsupportedKey) {
        try GlobalShortcut(keyCode: 0x37, modifiers: [.command]).validate()
    }
    #expect(throws: GlobalShortcutValidationError.unsupportedKey) {
        try GlobalShortcut(keyCode: 0x80, modifiers: [.command]).validate()
    }
}

@Test func globalShortcutEncodingUsesStableModifierOrder() throws {
    let shortcut = GlobalShortcut(
        keyCode: 0x11,
        modifiers: [.command, .shift, .control, .option]
    )
    let data = try JSONEncoder().encode(shortcut)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let modifiers = try #require(object["modifiers"] as? [String])

    #expect(modifiers == ["control", "option", "shift", "command"])
    #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == shortcut)
}

@Test func globalShortcutStoreReturnsNilWhenFileDoesNotExist() throws {
    let directory = try shortcutTemporaryDirectory()
    let store = GlobalShortcutSettingsStore(settingsURL: directory.appending(path: "settings.json"))

    #expect(try store.load() == nil)
}

@Test func globalShortcutStoreRoundTripsAndProtectsSettingsFile() throws {
    let directory = try shortcutTemporaryDirectory()
    let url = directory.appending(path: "nested/settings.json")
    let store = GlobalShortcutSettingsStore(settingsURL: url)

    try store.save(.defaultSettings)

    #expect(try store.load() == .defaultSettings)
    #expect(try shortcutPermissions(of: url.deletingLastPathComponent()) == 0o700)
    #expect(try shortcutPermissions(of: url) == 0o600)
}

@Test func globalShortcutStoreRejectsUnknownSchemaVersion() throws {
    let directory = try shortcutTemporaryDirectory()
    let url = directory.appending(path: "settings.json")
    let json = """
    {
      "schemaVersion": 99,
      "isEnabled": true,
      "shortcut": {
        "keyCode": 17,
        "modifiers": ["control", "option", "command"]
      }
    }
    """
    try Data(json.utf8).write(to: url)
    let store = GlobalShortcutSettingsStore(settingsURL: url)

    #expect(throws: GlobalShortcutSettingsError.unsupportedSchemaVersion(99)) {
        _ = try store.load()
    }
}

private func shortcutTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-shortcut-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func shortcutPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
