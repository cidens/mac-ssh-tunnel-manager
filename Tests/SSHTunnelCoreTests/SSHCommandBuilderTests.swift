import Foundation
import Testing
@testable import SSHTunnelCore

@Test func buildsSSHLocalForwardArgumentsWithoutUsingShell() {
    let tunnel = TunnelConfig(
        name: "Example",
        sshHost: "example-prod",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )

    let command = SSHCommandBuilder().buildStartCommand(for: tunnel)

    #expect(command.executable == "/usr/bin/ssh")
    #expect(command.arguments == [
        "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-L", "127.0.0.1:8088:127.0.0.1:8089",
        "example-prod"
    ])
}

@Test func buildsOneSSHCommandForMixedEnabledForwardingRules() throws {
    var tunnel = TunnelConfig(
        name: "Mixed group",
        sshHost: "example-prod",
        localHost: "127.0.0.1",
        localPort: 8_088,
        remoteHost: "db",
        remotePort: 5_432,
        openURL: nil
    )
    tunnel.replaceRules([
        TunnelForwardRule(mode: .localForward, localHost: "127.0.0.1", localPort: 8_088, remoteHost: "db", remotePort: 5_432),
        TunnelForwardRule(mode: .remoteForward, localHost: "127.0.0.1", localPort: 3_000, remoteHost: "localhost", remotePort: 18_080),
        TunnelForwardRule(mode: .dynamicForward, localHost: "[::1]", localPort: 1_080),
        TunnelForwardRule(mode: .localForward, localHost: "127.0.0.1", localPort: 9_999, remoteHost: "disabled", remotePort: 9_999, isEnabled: false),
    ])

    let builder = SSHCommandBuilder()
    try builder.validate(tunnel)
    let command = builder.buildStartCommand(for: tunnel)

    #expect(command.arguments == [
        "-N", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
        "-L", "127.0.0.1:8088:db:5432",
        "-R", "localhost:18080:127.0.0.1:3000",
        "-D", "[::1]:1080",
        "example-prod",
    ])
    #expect(!command.arguments.contains(where: { $0.contains("disabled") }))
}

@Test func allowsSavingButRejectsStartingAGroupWithEveryRuleDisabled() throws {
    var tunnel = TunnelConfig(
        name: "Paused group",
        sshHost: "example-prod",
        localHost: "127.0.0.1",
        localPort: 8_088,
        remoteHost: "db",
        remotePort: 5_432,
        openURL: nil
    )
    tunnel.replaceRules(tunnel.effectiveRules.map { rule in
        var disabled = rule
        disabled.isEnabled = false
        return disabled
    })

    let builder = SSHCommandBuilder()
    try builder.validate(tunnel)
    #expect(throws: TunnelValidationError.noEnabledRules) {
        try builder.validateForStart(tunnel)
    }
}

@Test func rejectsAConnectionGroupWithoutForwardingRules() {
    var tunnel = TunnelConfig(
        name: "Empty group",
        sshHost: "example-prod",
        localHost: "127.0.0.1",
        localPort: 8_088,
        remoteHost: "db",
        remotePort: 5_432,
        openURL: nil
    )
    tunnel.replaceRules([])

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func rejectsInjectedHostInAnyConnectionGroupRule() {
    var tunnel = TunnelConfig(
        name: "Mixed group", sshHost: "example-prod", localHost: "127.0.0.1", localPort: 8_088,
        remoteHost: "db", remotePort: 5_432, openURL: nil
    )
    tunnel.replaceRules([
        tunnel.rules[0],
        TunnelForwardRule(mode: .localForward, localHost: "127.0.0.1", localPort: 9_000, remoteHost: "db;touch", remotePort: 9_001),
    ])

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func riskConfirmationIsBoundToRuleModeAddressAndPort() {
    var rule = TunnelForwardRule(
        mode: .localForward,
        localHost: "*",
        localPort: 8_088,
        remoteHost: "db",
        remotePort: 5_432
    )
    rule.riskConfirmationSignature = rule.currentRiskSignature
    #expect(rule.hasValidRiskConfirmation)

    rule.localPort = 8_089
    #expect(!rule.hasValidRiskConfirmation)
}

@Test func buildsSSHConfigArgumentsWithoutLocalForwardFlag() throws {
    let tunnel = TunnelConfig(
        name: "Example via config",
        sshConfigName: "example-service",
        openURL: nil
    )

    try SSHCommandBuilder().validate(tunnel)

    let command = SSHCommandBuilder().buildStartCommand(for: tunnel)
    #expect(command.executable == "/usr/bin/ssh")
    #expect(command.arguments == [
        "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "example-service"
    ])
    #expect(!command.arguments.contains("-L"))
}

@Test func buildsSSHDynamicForwardArgumentsWithoutRemoteTarget() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000108",
      "mode": "dynamicForward",
      "name": "Example SOCKS",
      "sshHost": "example-bastion",
      "localHost": "127.0.0.1",
      "localPort": 1080
    }
    """
    let data = try #require(json.data(using: .utf8))
    let tunnel = try JSONDecoder().decode(TunnelConfig.self, from: data)

    try SSHCommandBuilder().validate(tunnel)

    let command = SSHCommandBuilder().buildStartCommand(for: tunnel)
    #expect(command.executable == "/usr/bin/ssh")
    #expect(command.arguments == [
        "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-D", "127.0.0.1:1080",
        "example-bastion"
    ])
    #expect(!command.arguments.contains("-L"))
}

@Test func rejectsInvalidSSHConfigNameBeforeSpawningSSH() {
    let tunnel = TunnelConfig(
        name: "Bad config",
        sshConfigName: "bad host;rm",
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func rejectsSSHConfigNameStartingWithDashBeforeSpawningSSH() {
    let tunnel = TunnelConfig(
        name: "Bad config",
        sshConfigName: "-V",
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func rejectsSSHHostStartingWithDashBeforeSpawningSSH() {
    let tunnel = TunnelConfig(
        name: "Bad host",
        sshHost: "-Fmalicious",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func rejectsInvalidTunnelFieldsBeforeSpawningSSH() {
    let tunnel = TunnelConfig(
        name: "Bad",
        sshHost: "host; rm -rf /",
        localHost: "127.0.0.1",
        localPort: 70000,
        remoteHost: "127.0.0.1",
        remotePort: 22,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func acceptsOpenSSHStyleUserHostAndBracketedIPv6ForwardHost() throws {
    let tunnel = TunnelConfig(
        name: "IPv6",
        sshHost: "ops@example-host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "[::1]",
        remotePort: 8089,
        openURL: nil
    )

    try SSHCommandBuilder().validate(tunnel)

    let command = SSHCommandBuilder().buildStartCommand(for: tunnel)
    #expect(command.arguments.contains("127.0.0.1:8088:[::1]:8089"))
    #expect(command.arguments.last == "ops@example-host")
}

@Test func rejectsHostFieldsWithWhitespaceOrShellMetacharacters() {
    let shellMetacharacterTunnel = TunnelConfig(
        name: "Bad",
        sshHost: "example.com;rm",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )
    let whitespaceTunnel = TunnelConfig(
        name: "Bad",
        sshHost: "example host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(shellMetacharacterTunnel)
    }
    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(whitespaceTunnel)
    }
}

@Test func rejectsUnbracketedIPv6ForwardHosts() {
    let tunnel = TunnelConfig(
        name: "Bad IPv6",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "::1",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func allowsWildcardLocalBindHost() throws {
    let tunnel = TunnelConfig(
        name: "Wildcard local",
        sshHost: "example-host",
        localHost: "*",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )

    try SSHCommandBuilder().validate(tunnel)

    let command = SSHCommandBuilder().buildStartCommand(for: tunnel)
    #expect(command.arguments.contains("*:8088:127.0.0.1:8089"))
}

@Test func rejectsWildcardRemoteHost() {
    let tunnel = TunnelConfig(
        name: "Bad remote",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "*",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func rejectsWildcardCharactersOutsideLocalBindWildcard() {
    let sshHostTunnel = TunnelConfig(
        name: "Bad ssh host",
        sshHost: "prod*",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "127.0.0.1",
        remotePort: 8089,
        openURL: nil
    )
    let remoteHostTunnel = TunnelConfig(
        name: "Bad remote host",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "db*",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(sshHostTunnel)
    }
    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(remoteHostTunnel)
    }
}

@Test func rejectsBracketedNonIPv6ForwardHost() {
    let tunnel = TunnelConfig(
        name: "Bad bracket",
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: 8088,
        remoteHost: "[db]",
        remotePort: 8089,
        openURL: nil
    )

    #expect(throws: TunnelValidationError.self) {
        try SSHCommandBuilder().validate(tunnel)
    }
}

@Test func buildsSSHRemoteForwardArgumentsForLoopbackIPv4IPv6AndWildcardBinds() throws {
    let expectedBindings = [
        ("localhost", "localhost:18080:127.0.0.1:3000"),
        ("203.0.113.10", "203.0.113.10:18080:127.0.0.1:3000"),
        ("[::1]", "[::1]:18080:127.0.0.1:3000"),
        ("*", "*:18080:127.0.0.1:3000")
    ]

    for (bindHost, expectedArgument) in expectedBindings {
        let tunnel = remoteForwardTunnel(remoteBindHost: bindHost)
        try SSHCommandBuilder().validate(tunnel)
        let command = SSHCommandBuilder().buildStartCommand(for: tunnel)

        #expect(command.executable == "/usr/bin/ssh")
        #expect(command.arguments == [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-R", expectedArgument,
            "example-bastion"
        ])
    }
}

@Test func remoteForwardRejectsInjectedHostsAndInvalidPorts() {
    let invalidTunnels = [
        remoteForwardTunnel(remoteBindHost: "localhost;touch"),
        remoteForwardTunnel(localTargetHost: "127.0.0.1|cat"),
        remoteForwardTunnel(remotePort: 0),
        remoteForwardTunnel(remotePort: 65_536),
        remoteForwardTunnel(localPort: -1)
    ]

    for tunnel in invalidTunnels {
        #expect(throws: TunnelValidationError.self) {
            try SSHCommandBuilder().validate(tunnel)
        }
    }
}

private func remoteForwardTunnel(
    remoteBindHost: String = "localhost",
    remotePort: Int = 18_080,
    localTargetHost: String = "127.0.0.1",
    localPort: Int = 3_000
) -> TunnelConfig {
    TunnelConfig(
        name: "Example Reverse",
        sshHost: "example-bastion",
        remoteBindHost: remoteBindHost,
        remotePort: remotePort,
        localTargetHost: localTargetHost,
        localPort: localPort,
        openURL: nil
    )
}
