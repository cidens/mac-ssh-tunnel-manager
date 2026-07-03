import SwiftUI
import SSHTunnelCore

@main
struct SSHTunnelManagerApp: App {
    @StateObject private var manager = TunnelManager()

    var body: some Scene {
        MenuBarExtra {
            TunnelMenuView()
                .environmentObject(manager)
                .frame(width: 460)
                .frame(minHeight: 420, alignment: .top)
        } label: {
            Label(manager.menuTitle, systemImage: manager.menuSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
