import Foundation
import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@MainActor
@Test func shortcutControllerRegistersDefaultOnStartup() {
    let store = ShortcutMemoryStore(settings: nil)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )

    controller.start()

    #expect(controller.settings == .defaultSettings)
    #expect(controller.runtimeState == .active)
    #expect(controller.issue == nil)
    #expect(registrar.registeredShortcuts.values.contains(.defaultShortcut))
}

@MainActor
@Test func shortcutControllerKeepsOldShortcutWhenCandidatePersistenceFails() throws {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .available])
    var showCount = 0
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker,
        triggerAction: { showCount += 1 }
    )
    controller.start()
    let oldToken = registrar.registeredShortcuts.keys.first
    store.saveError = ShortcutTestError.writeFailed
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x01, modifiers: [.control, .command])
    )

    #expect(controller.save(candidate) == false)
    #expect(controller.settings == .defaultSettings)
    #expect(controller.runtimeState == .active)
    #expect(controller.issue == .persistenceFailed)
    #expect(registrar.registeredShortcuts.count == 1)
    #expect(registrar.registeredShortcuts[try #require(oldToken)] == .defaultShortcut)

    registrar.fire(try #require(oldToken))
    #expect(showCount == 1)
}

@MainActor
@Test func shortcutControllerCommitsCandidateBeforeUnregisteringOldShortcut() throws {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    let oldToken = try #require(registrar.registeredShortcuts.keys.first)
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x01, modifiers: [.option, .command])
    )

    #expect(controller.save(candidate))

    #expect(store.settings == candidate)
    #expect(controller.settings == candidate)
    #expect(controller.runtimeState == .active)
    #expect(registrar.unregisteredTokens.contains(oldToken))
    #expect(registrar.registeredShortcuts.values.contains(candidate.shortcut))
    #expect(registrar.registeredShortcuts.count == 1)
}

@MainActor
@Test func shortcutControllerReportsSystemConflictWithoutRegisteringCandidate() {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .conflict])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x02, modifiers: [.control, .option])
    )

    #expect(controller.save(candidate) == false)
    #expect(controller.issue == .systemConflict)
    #expect(controller.runtimeState == .active)
    #expect(registrar.registerCallCount == 1)
    #expect(store.settings == .defaultSettings)
}

@MainActor
@Test func shortcutControllerKeepsOldShortcutWhenSystemQueryFails() {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .queryFailed(-50)])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x02, modifiers: [.control, .command])
    )

    #expect(controller.save(candidate) == false)
    #expect(controller.issue == .systemQueryFailed(-50))
    #expect(controller.runtimeState == .active)
    #expect(registrar.registerCallCount == 1)
    #expect(store.settings == .defaultSettings)
}

@MainActor
@Test func shortcutControllerKeepsOldShortcutOnExclusiveRegistrationConflict() {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    registrar.nextError = .conflict
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x02, modifiers: [.option, .command])
    )

    #expect(controller.save(candidate) == false)
    #expect(controller.issue == .systemConflict)
    #expect(controller.runtimeState == .active)
    #expect(Set(registrar.registeredShortcuts.values) == [.defaultShortcut])
    #expect(store.settings == .defaultSettings)
}

@MainActor
@Test func shortcutControllerKeepsOldShortcutOnGeneralRegistrationFailure() {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available, .available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    registrar.nextError = .registrationFailed(-1)
    let candidate = GlobalShortcutSettings(
        schemaVersion: 1,
        isEnabled: true,
        shortcut: GlobalShortcut(keyCode: 0x02, modifiers: [.control, .option])
    )

    #expect(controller.save(candidate) == false)
    #expect(controller.issue == .registrationFailed(-1))
    #expect(controller.runtimeState == .active)
    #expect(Set(registrar.registeredShortcuts.values) == [.defaultShortcut])
    #expect(store.settings == .defaultSettings)
}

@MainActor
@Test func shortcutControllerInvokesTriggerActionForEachActiveEvent() throws {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available])
    var triggerCount = 0
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker,
        triggerAction: { triggerCount += 1 }
    )
    controller.start()
    let activeToken = try #require(registrar.registeredShortcuts.keys.first)

    registrar.fire(activeToken)
    registrar.fire(activeToken)

    #expect(triggerCount == 2)
}

@MainActor
@Test func shortcutControllerRetriesUnchangedShortcutAfterStartupConflict() {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.conflict, .available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )

    controller.start()
    #expect(controller.runtimeState == .conflict)
    #expect(controller.issue == .systemConflict)

    #expect(controller.retry())
    #expect(controller.runtimeState == .active)
    #expect(controller.issue == nil)
    #expect(registrar.registerCallCount == 1)
}

@MainActor
@Test func shortcutControllerCapturesCurrentShortcutDuringRecordingWithoutShowingMenu() throws {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available])
    var showCount = 0
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker,
        triggerAction: { showCount += 1 }
    )
    controller.start()
    let activeToken = try #require(registrar.registeredShortcuts.keys.first)

    controller.beginRecording()
    registrar.fire(activeToken)

    #expect(controller.isRecording == false)
    #expect(controller.recordedShortcut == .defaultShortcut)
    #expect(showCount == 0)
}

@MainActor
@Test func shortcutControllerKeepsActiveShortcutWhenDisablingCannotBeSaved() throws {
    let store = ShortcutMemoryStore(settings: .defaultSettings)
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )
    controller.start()
    let activeToken = try #require(registrar.registeredShortcuts.keys.first)
    store.saveError = ShortcutTestError.writeFailed
    var disabled = GlobalShortcutSettings.defaultSettings
    disabled.isEnabled = false

    #expect(controller.save(disabled) == false)
    #expect(controller.runtimeState == .active)
    #expect(controller.settings.isEnabled)
    #expect(registrar.registeredShortcuts[activeToken] == .defaultShortcut)
}

@MainActor
@Test func shortcutControllerUsesDefaultAndRepairsInvalidStoredSettings() {
    let store = ShortcutMemoryStore(settings: nil)
    store.loadError = ShortcutTestError.invalidData
    let registrar = ShortcutFakeRegistrar()
    let checker = ShortcutFakeConflictChecker(results: [.available])
    let controller = GlobalShortcutController(
        store: store,
        registrar: registrar,
        conflictChecker: checker
    )

    controller.start()

    #expect(controller.runtimeState == .active)
    #expect(controller.hasInvalidStoredSettings)
    #expect(controller.settings == .defaultSettings)

    #expect(controller.save(.defaultSettings))
    #expect(controller.hasInvalidStoredSettings == false)
    #expect(store.settings == .defaultSettings)
    #expect(registrar.registeredShortcuts.count == 1)
}

private enum ShortcutTestError: Error {
    case writeFailed
    case invalidData
}

@MainActor
private final class ShortcutMemoryStore: GlobalShortcutSettingsStoring {
    var settings: GlobalShortcutSettings?
    var loadError: Error?
    var saveError: Error?

    init(settings: GlobalShortcutSettings?) {
        self.settings = settings
    }

    func load() throws -> GlobalShortcutSettings? {
        if let loadError {
            throw loadError
        }
        return settings
    }

    func save(_ settings: GlobalShortcutSettings) throws {
        if let saveError {
            throw saveError
        }
        self.settings = settings
    }
}

@MainActor
private final class ShortcutFakeRegistrar: GlobalShortcutRegistering {
    var onHotKey: ((ShortcutRegistrationToken) -> Void)?
    var nextID: UInt32 = 1
    var nextError: ShortcutRegistrationError?
    var registeredShortcuts: [ShortcutRegistrationToken: GlobalShortcut] = [:]
    var unregisteredTokens: [ShortcutRegistrationToken] = []
    var registerCallCount = 0

    func register(_ shortcut: GlobalShortcut) -> Result<ShortcutRegistrationToken, ShortcutRegistrationError> {
        registerCallCount += 1
        if let nextError {
            self.nextError = nil
            return .failure(nextError)
        }
        let token = ShortcutRegistrationToken(id: nextID)
        nextID += 1
        registeredShortcuts[token] = shortcut
        return .success(token)
    }

    func unregister(_ token: ShortcutRegistrationToken) {
        registeredShortcuts.removeValue(forKey: token)
        unregisteredTokens.append(token)
    }

    func unregisterAll() {
        for token in Array(registeredShortcuts.keys) {
            unregister(token)
        }
    }

    func fire(_ token: ShortcutRegistrationToken) {
        onHotKey?(token)
    }
}

@MainActor
private final class ShortcutFakeConflictChecker: SystemShortcutConflictChecking {
    private var results: [SystemShortcutConflictResult]

    init(results: [SystemShortcutConflictResult]) {
        self.results = results
    }

    func check(_ shortcut: GlobalShortcut) -> SystemShortcutConflictResult {
        guard !results.isEmpty else {
            return .available
        }
        return results.removeFirst()
    }
}
