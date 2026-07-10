import Testing
@testable import SSHTunnelCore

@Test func detectsLocalForwardInSSHConfigOutput() {
    let output = """
    user appuser
    hostname 203.0.113.10
    localforward 127.0.0.1:18080 127.0.0.1:8080
    """

    #expect(SSHConfigOutputParser.hasLocalForward(output))
}

@Test func ignoresNonLocalForwardSSHConfigOutput() {
    let output = """
    user appuser
    hostname 203.0.113.10
    remoteforward 127.0.0.1:18080 127.0.0.1:8080
    """

    #expect(!SSHConfigOutputParser.hasLocalForward(output))
}

@Test func extractsLocalForwardBindHosts() {
    let output = """
    localforward 127.0.0.1:18080 127.0.0.1:8080
    localforward *:18081 127.0.0.1:8081
    """

    #expect(SSHConfigOutputParser.localForwardBindHosts(output) == ["127.0.0.1", "*"])
}

@Test func detectsAnyForwardingDirectiveInSSHConfigOutput() {
    let output = """
    user appuser
    hostname 203.0.113.10
    remoteforward 127.0.0.1:18080 127.0.0.1:8080
    dynamicforward 127.0.0.1:1080
    """

    #expect(SSHConfigOutputParser.hasAnyForwardingDirective(output))
}

@Test func ignoresNonForwardingSSHConfigOutputWhenCheckingAnyForwardingDirective() {
    let output = """
    user appuser
    hostname 203.0.113.10
    serveraliveinterval 30
    """

    #expect(!SSHConfigOutputParser.hasAnyForwardingDirective(output))
}
