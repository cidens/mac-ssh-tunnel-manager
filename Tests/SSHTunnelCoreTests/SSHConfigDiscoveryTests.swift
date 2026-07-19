import CryptoKit
import Foundation
import Testing
@testable import SSHTunnelCore

@Test func discoversExplicitHostsAcrossIncludesWithoutModifyingSources() throws {
    let root = try temporarySSHDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    let included = root.appending(path: "config.d/services.conf")
    try FileManager.default.createDirectory(
        at: included.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try """
    Include config.d/*.conf
    Host direct wildcard-* !excluded
      HostName direct.example
    """.write(to: config, atomically: true, encoding: .utf8)
    try """
    Host included direct
      HostName included.example
    Match exec "test -f ~/.ssh/allow"
    """.write(to: included, atomically: true, encoding: .utf8)
    let hashesBefore = try [config, included].map(fileSHA256)

    let result = SSHConfigDiscovery(configURL: config, includeBaseURL: root).discover()

    #expect(result.hosts.map(\.alias) == ["included", "direct"])
    #expect(result.containsMatchExec)
    #expect(result.issues.isEmpty)
    #expect(try [config, included].map(fileSHA256) == hashesBefore)
}

@Test func includeCycleAndUnreadableIncludeDoNotRecurseOrCrash() throws {
    let root = try temporarySSHDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    let child = root.appending(path: "child.conf")
    let unreadableDirectory = root.appending(path: "not-a-file")
    try FileManager.default.createDirectory(at: unreadableDirectory, withIntermediateDirectories: true)
    try "Include child.conf not-a-file\nHost root\n".write(
        to: config,
        atomically: true,
        encoding: .utf8
    )
    try "Include config\nHost child\n".write(to: child, atomically: true, encoding: .utf8)

    let result = SSHConfigDiscovery(configURL: config, includeBaseURL: root).discover()

    #expect(result.hosts.map(\.alias) == ["child", "root"])
    #expect(result.issues.contains { $0.kind == .includeCycle })
    #expect(result.issues.contains { $0.kind == .unreadableFile })
}

@Test func invalidSyntaxIsReportedWhileOtherHostsRemainDiscoverable() throws {
    let root = try temporarySSHDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    try "Host \"unterminated\nHost usable\n".write(
        to: config,
        atomically: true,
        encoding: .utf8
    )

    let result = SSHConfigDiscovery(configURL: config, includeBaseURL: root).discover()

    #expect(result.hosts.map(\.alias) == ["usable"])
    #expect(result.issues == [SSHConfigDiscoveryIssue(
        kind: .invalidSyntax,
        sourcePath: config.path,
        line: 1
    )])
}

@Test func oversizedSSHConfigIsRejectedBeforeParsing() throws {
    let root = try temporarySSHDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    try Data(repeating: 0x20, count: 65).write(to: config)

    let result = SSHConfigDiscovery(
        configURL: config,
        includeBaseURL: root,
        maximumFileSize: 64
    ).discover()

    #expect(result.hosts.isEmpty)
    #expect(result.issues == [SSHConfigDiscoveryIssue(
        kind: .fileTooLarge,
        sourcePath: config.path
    )])
}

@Test func discoversEqualsSeparatedHostAndIncludeDirectives() throws {
    let root = try temporarySSHDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    let included = root.appending(path: "included.conf")
    try "Include=included.conf\nHost = root-host\n".write(
        to: config,
        atomically: true,
        encoding: .utf8
    )
    try "Host=included-host\nMatch exec=\"true\"\n".write(
        to: included,
        atomically: true,
        encoding: .utf8
    )

    let result = SSHConfigDiscovery(configURL: config, includeBaseURL: root).discover()

    #expect(result.hosts.map(\.alias) == ["included-host", "root-host"])
    #expect(result.containsMatchExec)
    #expect(result.issues.isEmpty)
}

private func temporarySSHDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-config-discovery-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func fileSHA256(_ url: URL) throws -> SHA256Digest {
    SHA256.hash(data: try Data(contentsOf: url))
}
