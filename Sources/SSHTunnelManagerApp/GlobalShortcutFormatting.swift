import Carbon
import Foundation
import SSHTunnelCore

enum GlobalShortcutFormatter {
    static func displayText(for shortcut: GlobalShortcut) -> String {
        let modifiers = shortcut.modifiers
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(modifierSymbol)
            .joined()
        return modifiers + keyLabel(for: shortcut.keyCode)
    }

    static func accessibilityText(for shortcut: GlobalShortcut) -> String {
        let modifierNames = shortcut.modifiers
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(modifierAccessibilityName)
        return (modifierNames + [keyLabel(for: shortcut.keyCode)]).joined(separator: " ")
    }

    private static func modifierSymbol(_ modifier: GlobalShortcutModifier) -> String {
        switch modifier {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    private static func modifierAccessibilityName(_ modifier: GlobalShortcutModifier) -> String {
        switch modifier {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let translated = translatedKeyLabel(for: keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func translatedKeyLabel(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else {
            return nil
        }
        return String(utf16CodeUnits: characters, count: length)
    }

    private static let specialKeyLabels: [UInt32: String] = [
        0x24: "↩",
        0x30: "⇥",
        0x31: "Space",
        0x33: "⌫",
        0x35: "Esc",
        0x40: "F17",
        0x4F: "F18",
        0x50: "F19",
        0x5A: "F20",
        0x60: "F5",
        0x61: "F6",
        0x62: "F7",
        0x63: "F3",
        0x64: "F8",
        0x65: "F9",
        0x67: "F11",
        0x69: "F13",
        0x6A: "F16",
        0x6B: "F14",
        0x6D: "F10",
        0x6F: "F12",
        0x71: "F15",
        0x72: "Help",
        0x73: "Home",
        0x74: "Page Up",
        0x75: "⌦",
        0x76: "F4",
        0x77: "End",
        0x78: "F2",
        0x79: "Page Down",
        0x7A: "F1",
        0x7B: "←",
        0x7C: "→",
        0x7D: "↓",
        0x7E: "↑"
    ]
}
