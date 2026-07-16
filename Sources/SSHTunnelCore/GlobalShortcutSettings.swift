import Foundation

public enum GlobalShortcutModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case control
    case option
    case shift
    case command

    public var sortOrder: Int {
        switch self {
        case .control: 0
        case .option: 1
        case .shift: 2
        case .command: 3
        }
    }
}

public enum GlobalShortcutValidationError: Error, Equatable, Sendable {
    case missingPrimaryKey
    case missingRequiredModifier
    case unsupportedKey
}

public struct GlobalShortcut: Equatable, Hashable, Sendable {
    public static let defaultShortcut = GlobalShortcut(
        keyCode: 0x11,
        modifiers: [.control, .option, .command]
    )

    public var keyCode: UInt32
    public var modifiers: Set<GlobalShortcutModifier>

    public init(keyCode: UInt32, modifiers: Set<GlobalShortcutModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public func validate() throws {
        guard keyCode <= 0x7F, !Self.modifierKeyCodes.contains(keyCode) else {
            throw GlobalShortcutValidationError.unsupportedKey
        }
        guard modifiers.contains(.control) || modifiers.contains(.option) || modifiers.contains(.command) else {
            throw GlobalShortcutValidationError.missingRequiredModifier
        }
    }

    private static let modifierKeyCodes: Set<UInt32> = [
        0x36, // Right Command
        0x37, // Command
        0x38, // Shift
        0x39, // Caps Lock
        0x3A, // Option
        0x3B, // Control
        0x3C, // Right Shift
        0x3D, // Right Option
        0x3E, // Right Control
        0x3F  // Function
    ]
}

extension GlobalShortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = Set(try container.decode([GlobalShortcutModifier].self, forKey: .modifiers))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.sorted { $0.sortOrder < $1.sortOrder }, forKey: .modifiers)
    }
}

public struct GlobalShortcutSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultSettings = GlobalShortcutSettings(
        schemaVersion: currentSchemaVersion,
        isEnabled: true,
        shortcut: .defaultShortcut
    )

    public var schemaVersion: Int
    public var isEnabled: Bool
    public var shortcut: GlobalShortcut

    public init(schemaVersion: Int, isEnabled: Bool, shortcut: GlobalShortcut) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.shortcut = shortcut
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GlobalShortcutSettingsError.unsupportedSchemaVersion(schemaVersion)
        }
        if isEnabled {
            try shortcut.validate()
        }
    }
}

public enum GlobalShortcutSettingsError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}
