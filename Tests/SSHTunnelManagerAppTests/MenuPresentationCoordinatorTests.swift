import AppKit
import Testing
@testable import SSHTunnelManagerApp

@MainActor
@Test func panelOwnedWindowDetectionIncludesChildWindows() {
    let panel = NSPanel()
    let child = NSWindow()
    panel.addChildWindow(child, ordered: .above)

    #expect(MenuPresentationCoordinator.isWindow(panel, ownedBy: panel))
    #expect(MenuPresentationCoordinator.isWindow(child, ownedBy: panel))
    #expect(!MenuPresentationCoordinator.isWindow(NSWindow(), ownedBy: panel))
    #expect(!MenuPresentationCoordinator.isWindow(nil, ownedBy: panel))
}

@MainActor
@Test func filePanelsRemainPartOfTheMenuFlowAfterSheetParentIsCleared() {
    let panel = NSPanel()
    let savePanel = NSSavePanel()
    let openPanel = NSOpenPanel()

    #expect(MenuPresentationCoordinator.shouldKeepPanelOpen(for: savePanel, ownedBy: panel))
    #expect(MenuPresentationCoordinator.shouldKeepPanelOpen(for: openPanel, ownedBy: panel))
    #expect(!MenuPresentationCoordinator.shouldKeepPanelOpen(for: NSWindow(), ownedBy: panel))
}

@Test func modalInteractionNotificationsUseStableNames() {
    #expect(Notification.Name.menuPanelModalInteractionDidBegin.rawValue.contains("DidBegin"))
    #expect(Notification.Name.menuPanelModalInteractionDidEnd.rawValue.contains("DidEnd"))
    #expect(Notification.Name.menuPanelModalInteractionDidBegin != .menuPanelModalInteractionDidEnd)
}

@MainActor
@Test func modalInteractionAndTrailingGlobalClickCannotCloseMenuPanel() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    #expect(!MenuPresentationCoordinator.allowsOutsideClickClose(
        modalInteractionDepth: 1,
        suppressUntil: .distantPast,
        now: now
    ))
    #expect(!MenuPresentationCoordinator.allowsOutsideClickClose(
        modalInteractionDepth: 0,
        suppressUntil: now.addingTimeInterval(0.5),
        now: now
    ))
    #expect(MenuPresentationCoordinator.allowsOutsideClickClose(
        modalInteractionDepth: 0,
        suppressUntil: now.addingTimeInterval(-0.1),
        now: now
    ))
}
