import Foundation
import Testing
@testable import SSHTunnelCore

@Test func healthCheckConfigurationValidatesSupportedRuleKinds() throws {
    let local = TunnelForwardRule(
        mode: .localForward,
        localHost: "127.0.0.1",
        localPort: 8_080,
        remoteHost: "service",
        remotePort: 80
    )
    let socks = TunnelForwardRule(
        mode: .dynamicForward,
        localHost: "[::1]",
        localPort: 1_080
    )

    try TunnelHealthCheckConfiguration(kind: .tcp).validate(for: local)
    try TunnelHealthCheckConfiguration(
        kind: .http,
        url: URL(string: "http://localhost:8080/health")
    ).validate(for: local)
    try TunnelHealthCheckConfiguration(kind: .socks5).validate(for: socks)

    #expect(throws: TunnelHealthCheckValidationError.unsupportedCheckKind) {
        try TunnelHealthCheckConfiguration(kind: .socks5).validate(for: local)
    }
    #expect(throws: TunnelHealthCheckValidationError.unsupportedCheckKind) {
        try TunnelHealthCheckConfiguration(kind: .tcp).validate(for: socks)
    }
}

@Test func httpHealthCheckMustTargetItsRuleListener() {
    let local = TunnelForwardRule(
        mode: .localForward,
        localHost: "0.0.0.0",
        localPort: 8_080,
        remoteHost: "service",
        remotePort: 80
    )

    #expect(throws: Never.self) {
        try TunnelHealthCheckConfiguration(
            kind: .http,
            url: URL(string: "http://127.0.0.1:8080/health")
        ).validate(for: local)
    }
    #expect(throws: TunnelHealthCheckValidationError.urlDoesNotMatchListener) {
        try TunnelHealthCheckConfiguration(
            kind: .http,
            url: URL(string: "http://example.com:8080/health")
        ).validate(for: local)
    }
    #expect(throws: TunnelHealthCheckValidationError.invalidURL) {
        try TunnelHealthCheckConfiguration(
            kind: .http,
            url: URL(string: "http://user:secret@127.0.0.1:8080/health")
        ).validate(for: local)
    }
}

@Test func healthCheckConfigurationRejectsInvalidTimingAndUnsupportedModes() {
    let remote = TunnelForwardRule(
        mode: .remoteForward,
        localHost: "127.0.0.1",
        localPort: 80,
        remoteHost: "localhost",
        remotePort: 8_080
    )
    let local = TunnelForwardRule(
        mode: .localForward,
        localHost: "127.0.0.1",
        localPort: 8_080,
        remoteHost: "service",
        remotePort: 80
    )

    #expect(throws: TunnelHealthCheckValidationError.unsupportedRuleMode) {
        try TunnelHealthCheckConfiguration(kind: .tcp).validate(for: remote)
    }
    #expect(throws: TunnelHealthCheckValidationError.invalidInterval) {
        try TunnelHealthCheckConfiguration(kind: .tcp, interval: 1).validate(for: local)
    }
    #expect(throws: TunnelHealthCheckValidationError.invalidTimeout) {
        try TunnelHealthCheckConfiguration(kind: .tcp, interval: 5, timeout: 6).validate(for: local)
    }
}

@Test func legacyRuleJSONDefaultsHealthCheckToDisabled() throws {
    let data = Data(#"{"id":"00000000-0000-0000-0000-000000000088","mode":"localForward","localHost":"127.0.0.1","localPort":8080,"remoteHost":"service","remotePort":80,"isEnabled":true}"#.utf8)

    let rule = try JSONDecoder().decode(TunnelForwardRule.self, from: data)

    #expect(rule.healthCheck == nil)
}

@Test func commandValidationRejectsInvalidHealthChecksBeforeStartingSSH() {
    var tunnel = TunnelConfig(
        name: "Invalid health",
        sshHost: "example",
        localHost: "127.0.0.1",
        localPort: 8_080,
        remoteHost: "service",
        remotePort: 80,
        openURL: nil
    )
    var rule = tunnel.rules[0]
    rule.healthCheck = TunnelHealthCheckConfiguration(
        kind: .http,
        url: URL(string: "http://127.0.0.1:8081/health")
    )
    tunnel.replaceRules([rule])

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validateForStart(tunnel)
    }
}
