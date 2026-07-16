import Carbon
import Foundation
import SSHTunnelCore

struct ShortcutRegistrationToken: Hashable, Sendable {
    let id: UInt32
}

enum ShortcutRegistrationError: Error, Equatable {
    case conflict
    case registrationFailed(Int32)
}

enum SystemShortcutConflictResult: Equatable {
    case available
    case conflict
    case queryFailed(Int32)
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    var onHotKey: ((ShortcutRegistrationToken) -> Void)? { get set }
    func register(_ shortcut: GlobalShortcut) -> Result<ShortcutRegistrationToken, ShortcutRegistrationError>
    func unregister(_ token: ShortcutRegistrationToken)
    func unregisterAll()
}

@MainActor
protocol SystemShortcutConflictChecking {
    func check(_ shortcut: GlobalShortcut) -> SystemShortcutConflictResult
}

@MainActor
final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    var onHotKey: ((ShortcutRegistrationToken) -> Void)?

    private static let signature: OSType = 0x5353544D // SSTM
    private var nextID: UInt32 = 1
    private var registrations: [ShortcutRegistrationToken: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    func register(_ shortcut: GlobalShortcut) -> Result<ShortcutRegistrationToken, ShortcutRegistrationError> {
        if let handlerError = ensureEventHandler() {
            return .failure(.registrationFailed(handlerError))
        }

        let token = ShortcutRegistrationToken(id: nextID)
        nextID &+= 1
        if nextID == 0 {
            nextID = 1
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: token.id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            if status == eventHotKeyExistsErr {
                return .failure(.conflict)
            }
            return .failure(.registrationFailed(status))
        }

        registrations[token] = hotKeyRef
        return .success(token)
    }

    func unregister(_ token: ShortcutRegistrationToken) {
        guard let ref = registrations.removeValue(forKey: token) else {
            return
        }
        UnregisterEventHotKey(ref)
    }

    func unregisterAll() {
        for token in Array(registrations.keys) {
            unregister(token)
        }
    }

    private func ensureEventHandler() -> OSStatus? {
        guard eventHandlerRef == nil else {
            return nil
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        return status == noErr ? nil : status
    }

    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }
        var hotKeyID = EventHotKeyID()
        var actualSize = 0
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            &actualSize,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }

        let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let signature = hotKeyID.signature
        let id = hotKeyID.id
        return MainActor.assumeIsolated {
            registrar.handle(signature: signature, id: id)
        }
    }

    private func handle(signature: OSType, id: UInt32) -> OSStatus {
        guard signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let token = ShortcutRegistrationToken(id: id)
        guard registrations[token] != nil else {
            return OSStatus(eventNotHandledErr)
        }
        onHotKey?(token)
        return noErr
    }
}

@MainActor
struct CarbonSystemShortcutConflictChecker: SystemShortcutConflictChecking {
    func check(_ shortcut: GlobalShortcut) -> SystemShortcutConflictResult {
        var unmanagedHotKeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&unmanagedHotKeys)
        guard status == noErr else {
            return .queryFailed(status)
        }
        guard let hotKeys = unmanagedHotKeys?.takeRetainedValue() as NSArray? else {
            return .available
        }

        let expectedModifiers = carbonModifiers(for: shortcut.modifiers)
        for case let hotKey as NSDictionary in hotKeys {
            guard (hotKey[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let keyCode = (hotKey[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value,
                  let modifiers = (hotKey[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value else {
                continue
            }
            if keyCode == shortcut.keyCode,
               normalizedCarbonModifiers(modifiers) == normalizedCarbonModifiers(expectedModifiers) {
                return .conflict
            }
        }
        return .available
    }
}

private func carbonModifiers(for modifiers: Set<GlobalShortcutModifier>) -> UInt32 {
    modifiers.reduce(into: UInt32(0)) { result, modifier in
        switch modifier {
        case .control:
            result |= UInt32(controlKey)
        case .option:
            result |= UInt32(optionKey)
        case .shift:
            result |= UInt32(shiftKey)
        case .command:
            result |= UInt32(cmdKey)
        }
    }
}

private func normalizedCarbonModifiers(_ modifiers: UInt32) -> UInt32 {
    let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    return modifiers & supported
}
