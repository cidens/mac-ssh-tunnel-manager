import CoreGraphics
import SSHTunnelCore
import Testing
@testable import SSHTunnelManagerApp

@MainActor
@Test func shortcutRecorderFindsPrimaryKeyAddedAfterModifiers() {
    let previous: Set<UInt32> = [0x37]
    let current: Set<UInt32> = [0x37, 0x31]

    #expect(
        ShortcutRecorderNSView.newlyPressedPrimaryKey(
            current: current,
            previous: previous
        ) == 0x31
    )
}

@MainActor
@Test func shortcutRecorderMapsCombinedSessionModifierFlags() {
    let modifiers = ShortcutRecorderNSView.modifiers(
        from: [.maskControl, .maskAlternate, .maskCommand]
    )

    #expect(modifiers == [.control, .option, .command])
}
