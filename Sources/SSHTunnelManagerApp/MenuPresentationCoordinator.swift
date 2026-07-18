import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuPresentationCoordinator: NSObject {
    private static let panelWidth: CGFloat = 460
    private static let preferredPanelHeight: CGFloat = 640
    private static let minimumPanelHeight: CGFloat = 420

    private enum PresentationSource {
        case statusItem
        case externalRequest
    }

    private let manager: TunnelManager
    private let shortcutController: GlobalShortcutController
    private let statusItem: NSStatusItem
    private let panel: MenuPanel
    private let hostingController: NSHostingController<MenuPanelRootView>
    private var managerCancellable: AnyCancellable?

    init(manager: TunnelManager, shortcutController: GlobalShortcutController) {
        self.manager = manager
        self.shortcutController = shortcutController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        hostingController = NSHostingController(
            rootView: MenuPanelRootView(
                manager: manager,
                shortcutController: shortcutController
            )
        )
        panel = MenuPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.panelWidth,
                height: Self.minimumPanelHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        configureStatusItem()
        configurePanel()
        observeManager()
        updateStatusItem()
    }

    func showAndFocus() {
        show(source: .externalRequest)
    }

    func toggleFromGlobalShortcut() {
        if panel.isVisible {
            close()
        } else {
            show(source: .externalRequest)
        }
    }

    func close() {
        panel.orderOut(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        statusItem.length = NSStatusBar.system.thickness
        button.target = self
        button.action = #selector(toggleFromStatusItem)
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePanel() {
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    private func observeManager() {
        managerCancellable = manager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateStatusItem()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        let image = NSImage(systemSymbolName: manager.menuSystemImage, accessibilityDescription: manager.menuTitle)
        image?.isTemplate = true
        statusItem.length = NSStatusBar.system.thickness
        button.image = image
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = manager.menuTitle
        button.setAccessibilityLabel(manager.menuTitle)
    }

    @objc private func toggleFromStatusItem() {
        if panel.isVisible {
            close()
        } else {
            show(source: .statusItem)
        }
    }

    private func show(source: PresentationSource) {
        let screen = targetScreen(for: source)
        resizePanel(toFit: screen)

        if !panel.isVisible || panel.screen != screen {
            positionPanel(on: screen, source: source)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func targetScreen(for source: PresentationSource) -> NSScreen {
        if source == .statusItem,
           let screen = statusItem.button?.window?.screen {
            return screen
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func resizePanel(toFit screen: NSScreen) {
        let maximumHeight = max(Self.minimumPanelHeight, screen.visibleFrame.height - 24)
        let height = min(Self.preferredPanelHeight, maximumHeight)
        panel.setContentSize(NSSize(width: Self.panelWidth, height: height))
    }

    private func positionPanel(on screen: NSScreen, source: PresentationSource) {
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let proposedOrigin: NSPoint

        if source == .statusItem,
           let button = statusItem.button,
           let window = button.window {
            let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            proposedOrigin = NSPoint(
                x: buttonRect.midX - panelSize.width / 2,
                y: buttonRect.minY - panelSize.height - 6
            )
        } else {
            proposedOrigin = NSPoint(
                x: visibleFrame.maxX - panelSize.width - 10,
                y: visibleFrame.maxY - panelSize.height - 10
            )
        }

        let x = min(max(proposedOrigin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = min(max(proposedOrigin.y, visibleFrame.minY + 8), visibleFrame.maxY - panelSize.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func orderOut(_ sender: Any?) {
        makeFirstResponder(nil)
        super.orderOut(sender)
    }
}

struct MenuPanelRootView: View {
    @ObservedObject var manager: TunnelManager
    @ObservedObject var shortcutController: GlobalShortcutController

    var body: some View {
        TunnelMenuView()
            .environmentObject(manager)
            .environmentObject(shortcutController)
            .frame(width: 460)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.quaternary)
            }
    }
}
