import Foundation
import SSHTunnelCore

@MainActor
protocol GlobalShortcutSettingsStoring {
    func load() throws -> GlobalShortcutSettings?
    func save(_ settings: GlobalShortcutSettings) throws
}

extension GlobalShortcutSettingsStore: GlobalShortcutSettingsStoring {}

enum GlobalShortcutRuntimeState: Equatable {
    case disabled
    case active
    case conflict
    case failed
}

enum GlobalShortcutIssue: Equatable {
    case invalidShortcut(GlobalShortcutValidationError)
    case systemConflict
    case systemQueryFailed(Int32)
    case registrationFailed(Int32)
    case persistenceFailed
}

@MainActor
final class GlobalShortcutController: ObservableObject {
    @Published private(set) var settings = GlobalShortcutSettings.defaultSettings
    @Published private(set) var runtimeState: GlobalShortcutRuntimeState = .disabled
    @Published private(set) var issue: GlobalShortcutIssue?
    @Published private(set) var hasInvalidStoredSettings = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordedShortcut: GlobalShortcut?

    private let store: any GlobalShortcutSettingsStoring
    private let registrar: any GlobalShortcutRegistering
    private let conflictChecker: any SystemShortcutConflictChecking
    private var activeToken: ShortcutRegistrationToken?
    private var triggerAction: () -> Void

    init(
        store: any GlobalShortcutSettingsStoring,
        registrar: any GlobalShortcutRegistering,
        conflictChecker: any SystemShortcutConflictChecking,
        triggerAction: @escaping () -> Void = {}
    ) {
        self.store = store
        self.registrar = registrar
        self.conflictChecker = conflictChecker
        self.triggerAction = triggerAction
        registrar.onHotKey = { [weak self] token in
            self?.handleHotKey(token)
        }
    }

    func setTriggerAction(_ action: @escaping () -> Void) {
        triggerAction = action
    }

    func start() {
        do {
            settings = try store.load() ?? .defaultSettings
            hasInvalidStoredSettings = false
            issue = nil
        } catch {
            settings = .defaultSettings
            hasInvalidStoredSettings = true
            issue = nil
        }

        guard settings.isEnabled else {
            runtimeState = .disabled
            return
        }
        activateSavedShortcut()
    }

    @discardableResult
    func save(_ candidate: GlobalShortcutSettings) -> Bool {
        do {
            try candidate.validate()
        } catch let error as GlobalShortcutValidationError {
            issue = .invalidShortcut(error)
            return false
        } catch {
            issue = .persistenceFailed
            return false
        }

        if candidate == settings, !(candidate.isEnabled && activeToken == nil) {
            if hasInvalidStoredSettings {
                return persistExistingActiveSettings(candidate)
            }
            issue = nil
            return true
        }

        if !candidate.isEnabled {
            do {
                try store.save(candidate)
            } catch {
                issue = .persistenceFailed
                return false
            }
            if let activeToken {
                registrar.unregister(activeToken)
                self.activeToken = nil
            }
            settings = candidate
            runtimeState = .disabled
            hasInvalidStoredSettings = false
            issue = nil
            return true
        }

        switch conflictChecker.check(candidate.shortcut) {
        case .conflict:
            runtimeState = activeToken == nil ? .conflict : .active
            issue = .systemConflict
            return false
        case let .queryFailed(code):
            runtimeState = activeToken == nil ? .failed : .active
            issue = .systemQueryFailed(code)
            return false
        case .available:
            break
        }

        let candidateToken: ShortcutRegistrationToken
        switch registrar.register(candidate.shortcut) {
        case let .success(token):
            candidateToken = token
        case .failure(.conflict):
            runtimeState = activeToken == nil ? .conflict : .active
            issue = .systemConflict
            return false
        case let .failure(.registrationFailed(code)):
            runtimeState = activeToken == nil ? .failed : .active
            issue = .registrationFailed(code)
            return false
        }

        do {
            try store.save(candidate)
        } catch {
            registrar.unregister(candidateToken)
            runtimeState = activeToken == nil ? .failed : .active
            issue = .persistenceFailed
            return false
        }

        let oldToken = activeToken
        activeToken = candidateToken
        if let oldToken {
            registrar.unregister(oldToken)
        }
        settings = candidate
        runtimeState = .active
        hasInvalidStoredSettings = false
        issue = nil
        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard settings.isEnabled else {
            runtimeState = .disabled
            issue = nil
            return true
        }
        guard activeToken == nil else {
            runtimeState = .active
            issue = nil
            return true
        }
        return activateSavedShortcut()
    }

    func beginRecording() {
        recordedShortcut = nil
        isRecording = true
    }

    func finishRecording(with shortcut: GlobalShortcut) {
        recordedShortcut = shortcut
        isRecording = false
    }

    func cancelRecording() {
        isRecording = false
        recordedShortcut = nil
    }

    func consumeRecordedShortcut() {
        recordedShortcut = nil
    }

    func prepareForTermination() {
        isRecording = false
        activeToken = nil
        registrar.unregisterAll()
    }

    private func persistExistingActiveSettings(_ candidate: GlobalShortcutSettings) -> Bool {
        do {
            try store.save(candidate)
        } catch {
            issue = .persistenceFailed
            return false
        }
        settings = candidate
        hasInvalidStoredSettings = false
        runtimeState = .active
        issue = nil
        return true
    }

    @discardableResult
    private func activateSavedShortcut() -> Bool {
        switch conflictChecker.check(settings.shortcut) {
        case .conflict:
            runtimeState = .conflict
            issue = .systemConflict
            return false
        case let .queryFailed(code):
            runtimeState = .failed
            issue = .systemQueryFailed(code)
            return false
        case .available:
            break
        }

        switch registrar.register(settings.shortcut) {
        case let .success(token):
            activeToken = token
            runtimeState = .active
            issue = nil
            return true
        case .failure(.conflict):
            runtimeState = .conflict
            issue = .systemConflict
            return false
        case let .failure(.registrationFailed(code)):
            runtimeState = .failed
            issue = .registrationFailed(code)
            return false
        }
    }

    private func handleHotKey(_ token: ShortcutRegistrationToken) {
        guard token == activeToken else {
            return
        }
        if isRecording {
            finishRecording(with: settings.shortcut)
            return
        }
        triggerAction()
    }
}
