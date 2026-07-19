import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

@Test func tunnelDraftRoundTripsAutomaticConnectionSettings() throws {
    var tunnel = TunnelConfig(
        name: "Example",
        sshConfigName: "example-service",
        openURL: nil
    )
    tunnel.isAutoReconnectEnabled = true
    tunnel.isAutoStartEnabled = true

    let rebuilt = try TunnelDraft(tunnel: tunnel).makeConfig(id: tunnel.id)

    #expect(rebuilt.isAutoReconnectEnabled)
    #expect(rebuilt.isAutoStartEnabled)
}

@Test func dynamicForwardFormShowsOnlySSHHostAndLocalFields() {
    #expect(TunnelMode.dynamicForward.showsSSHHostAndLocalFields)
    #expect(!TunnelMode.dynamicForward.showsRemoteFields)
    #expect(!TunnelMode.dynamicForward.showsSSHConfigFields)
}

@Test func localForwardFormShowsManualForwardFields() {
    #expect(TunnelMode.localForward.showsSSHHostAndLocalFields)
    #expect(TunnelMode.localForward.showsRemoteFields)
    #expect(!TunnelMode.localForward.showsSSHConfigFields)
}

@Test func remoteForwardFormShowsSSHRemoteListenerAndLocalTargetFields() {
    #expect(TunnelMode.remoteForward.showsSSHHostAndLocalFields)
    #expect(TunnelMode.remoteForward.showsRemoteFields)
    #expect(!TunnelMode.remoteForward.showsSSHConfigFields)
}

@Test func selectingRemoteForwardDefaultsRemoteListenerToLocalhost() {
    var draft = TunnelDraft()
    draft.remoteHost = "example-target"

    draft.mode = .remoteForward

    #expect(draft.remoteHost == "localhost")
}

@Test func sshConfigFormShowsOnlyConfigAliasField() {
    #expect(!TunnelMode.sshConfig.showsSSHHostAndLocalFields)
    #expect(!TunnelMode.sshConfig.showsRemoteFields)
    #expect(TunnelMode.sshConfig.showsSSHConfigFields)
}
