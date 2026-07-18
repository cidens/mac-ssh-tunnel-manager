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
