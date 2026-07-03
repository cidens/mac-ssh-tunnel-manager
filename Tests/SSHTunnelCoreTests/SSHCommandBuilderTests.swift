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
