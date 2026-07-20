import Testing
@testable import SSHTunnelCore

@Test func detectsListeningPortFromLsofOutput() {
    let output = """
    COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "127.0.0.1", port: 8088))
}

@Test func doesNotMatchDifferentPort() {
    let output = """
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:8088 (LISTEN)
    """

    #expect(!PortStatusParser.isListening(lsofOutput: output, host: "127.0.0.1", port: 8089))
}

@Test func doesNotMatchPortPrefix() {
    let output = """
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:80880 (LISTEN)
    """

    #expect(!PortStatusParser.isListening(lsofOutput: output, host: "127.0.0.1", port: 8088))
}

@Test func treatsWildcardListenerAsMatchingSpecificHost() {
    let output = """
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP *:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "127.0.0.1", port: 8088))
}

@Test func treatsLocalhostAsLoopback() {
    let output = """
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "localhost", port: 8088))
}

@Test func detectsBracketedIPv6Listener() {
    let output = """
    ssh 1960 ad 4u IPv6 0x123 0t0 TCP [::1]:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "[::1]", port: 8088))
}

@Test func treatsRequestedWildcardHostAsMatchingAnyListenerOnPort() {
    let output = """
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "0.0.0.0", port: 8088))
    #expect(PortStatusParser.isListening(lsofOutput: output, host: "*", port: 8088))
}

@Test func treatsIPv6AnyListenerAsWildcard() {
    let output = """
    ssh 1960 ad 4u IPv6 0x123 0t0 TCP [::]:8088 (LISTEN)
    """

    #expect(PortStatusParser.isListening(lsofOutput: output, host: "[::1]", port: 8088))
}

@Test func extractsAllListeningEndpointsForReuseByRecommendation() {
    let output = """
    COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    ssh 1960 ad 4u IPv4 0x123 0t0 TCP 127.0.0.1:8088 (LISTEN)
    ssh 1960 ad 5u IPv6 0x124 0t0 TCP [::1]:8089 (LISTEN)
    ssh 1960 ad 6u IPv4 0x125 0t0 UDP 127.0.0.1:8090
    """

    #expect(PortStatusParser.listeningEndpoints(lsofOutput: output) == [
        LocalPortEndpoint(host: "127.0.0.1", port: 8088),
        LocalPortEndpoint(host: "[::1]", port: 8089),
    ])
}
