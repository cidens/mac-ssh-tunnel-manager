import Testing
import SSHTunnelCore
@testable import SSHTunnelManagerApp

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

@Test func sshConfigFormShowsOnlyConfigAliasField() {
    #expect(!TunnelMode.sshConfig.showsSSHHostAndLocalFields)
    #expect(!TunnelMode.sshConfig.showsRemoteFields)
    #expect(TunnelMode.sshConfig.showsSSHConfigFields)
}
