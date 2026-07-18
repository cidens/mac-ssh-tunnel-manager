import Foundation
import SSHTunnelCore
import Testing
@testable import SSHTunnelManagerApp

@MainActor
@Test func importControllerRequiresMatchExecApprovalBeforeResolving() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    try """
    Host local-service duplicate-service
    Match exec "test -f ~/.ssh/allow"
    """.write(to: config, atomically: true, encoding: .utf8)
    let resolver = RecordingImportResolver(results: [
        "local-service": .resolved("localforward 127.0.0.1:18080 127.0.0.1:8080\n")
    ])
    let controller = SSHConfigImportController(
        discovery: SSHConfigDiscovery(configURL: config, includeBaseURL: root),
        resolver: resolver
    )

    let loadTask = controller.load(existingAliases: ["DUPLICATE-SERVICE"])
    await loadTask?.value
    controller.selectAll()

    #expect(controller.containsMatchExec)
    #expect(controller.selectedCount == 1)
    #expect(controller.candidates.first { $0.alias == "duplicate-service" }?.isDuplicate == true)
    #expect(controller.requiresMatchExecConfirmation)

    await controller.previewSelected()
    #expect(resolver.requestedNames.isEmpty)

    controller.approveMatchExec()
    await controller.previewSelected()

    #expect(resolver.requestedNames == ["local-service"])
    #expect(controller.importableAliases == ["local-service"])
}

@MainActor
@Test func importControllerClassifiesPreviewResultsAndManualAliases() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = root.appending(path: "config")
    try "Host remote-service socks-service empty-service\n".write(
        to: config,
        atomically: true,
        encoding: .utf8
    )
    let resolver = RecordingImportResolver(results: [
        "remote-service": .resolved("remoteforward *:18080 127.0.0.1:8080\n"),
        "socks-service": .resolved("dynamicforward 127.0.0.1:1080\n"),
        "empty-service": .resolved("hostname example.invalid\n"),
        "manual-service": .timedOut,
    ])
    let controller = SSHConfigImportController(
        discovery: SSHConfigDiscovery(configURL: config, includeBaseURL: root),
        resolver: resolver
    )

    await controller.load(existingAliases: [])?.value
    #expect(!controller.addManualAlias("bad alias"))
    #expect(controller.addManualAlias("manual-service"))
    controller.selectAll()
    await controller.previewSelected()

    #expect(controller.hasRiskyImport)
    #expect(Set(controller.importableAliases) == Set(["remote-service", "socks-service"]))
    #expect(controller.candidates.first { $0.alias == "empty-service" }?.preview == .noForwarding)
    #expect(controller.candidates.first { $0.alias == "manual-service" }?.preview == .timedOut)
}

private final class RecordingImportResolver: SSHConfigResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [String: SSHConfigResolution]
    private var requests: [String] = []

    init(results: [String: SSHConfigResolution]) {
        self.results = results
    }

    var requestedNames: [String] {
        lock.withLock { requests.sorted() }
    }

    func resolveConfig(named name: String, timeout: TimeInterval) -> SSHConfigResolution {
        lock.withLock { requests.append(name) }
        return results[name] ?? .failed
    }
}

private func importTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ssh-config-import-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
