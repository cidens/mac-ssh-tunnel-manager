import Foundation
import Testing
@testable import SSHTunnelCore

@Test func exportDocumentContainsMetadataAndOnlyPersistentConfigurationFields() throws {
    var tunnel = sampleTunnel(id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!)
    tunnel.tags = ["数据库", "生产"]
    tunnel.isFavorite = true
    tunnel.manualOrder = 4
    tunnel.isAutoReconnectEnabled = true
    tunnel.isAutoStartEnabled = true
    tunnel.replaceRules(tunnel.effectiveRules.map { rule in
        var value = rule
        value.healthCheck = TunnelHealthCheckConfiguration(
            kind: .http,
            url: URL(string: "http://127.0.0.1:\(rule.localPort)/health")
        )
        return value
    })
    let exportedAt = Date(timeIntervalSince1970: 1_750_000_000)
    let transfer = TunnelConfigurationTransfer()

    let data = try transfer.exportData(configs: [tunnel], appVersion: "0.3.2", exportedAt: exportedAt)
    let document = try transfer.decode(data)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(document.schemaVersion == 3)
    #expect(document.exportedAt == exportedAt)
    #expect(document.appVersion == "0.3.2")
    #expect(document.configs == [tunnel])
    #expect(json.contains("\"isAutoReconnectEnabled\" : true"))
    #expect(json.contains("\"isAutoStartEnabled\" : true"))
    #expect(json.contains("\"rules\""))
    #expect(json.contains("\"healthCheck\""))
    #expect(!json.contains("process"))
    #expect(!json.contains("stderr"))
    #expect(!json.contains("errorHistory"))
    #expect(!json.contains("credential"))
    #expect(!json.contains("riskConfirmation"))
}

@Test func importReadsSchemaTwoRulesWithHealthChecksDisabled() throws {
    let data = Data(#"{"schemaVersion":2,"exportedAt":"2025-06-15T15:06:40Z","appVersion":"0.4.0","configs":[{"id":"00000000-0000-0000-0000-000000000072","mode":"localForward","name":"Version two","sshHost":"legacy-host","tags":[],"isFavorite":false,"isAutoReconnectEnabled":false,"isAutoStartEnabled":false,"rules":[{"id":"00000000-0000-0000-0000-000000000073","mode":"localForward","localHost":"127.0.0.1","localPort":15432,"remoteHost":"db","remotePort":5432,"isEnabled":true,"healthCheck":{"kind":"tcp","interval":30,"timeout":3}}]}]}"#.utf8)

    let document = try TunnelConfigurationTransfer().decode(data)
    let rule = try #require(document.configs.first?.effectiveRules.first)

    #expect(document.schemaVersion == 2)
    #expect(rule.healthCheck == nil)
}

@Test func importReadsSchemaOneAndMigratesSingleForwardToAGroup() throws {
    let data = Data(#"{"schemaVersion":1,"exportedAt":"2025-06-15T15:06:40Z","appVersion":"0.3.2","configs":[{"id":"00000000-0000-0000-0000-000000000071","mode":"localForward","name":"Legacy export","sshHost":"legacy-host","localHost":"127.0.0.1","localPort":15432,"remoteHost":"db","remotePort":5432,"openURL":"http://127.0.0.1:15432","tags":["db"],"isFavorite":true,"manualOrder":3,"isAutoReconnectEnabled":true,"isAutoStartEnabled":true}]}"#.utf8)

    let document = try TunnelConfigurationTransfer().decode(data)
    let config = try #require(document.configs.first)

    #expect(document.schemaVersion == 1)
    #expect(config.id == UUID(uuidString: "00000000-0000-0000-0000-000000000071"))
    #expect(config.name == "Legacy export")
    #expect(config.sshHost == "legacy-host")
    #expect(config.effectiveRules.count == 1)
    #expect(config.effectiveRules.first?.mode == .localForward)
    #expect(config.effectiveRules.first?.localPort == 15_432)
}

@Test func importClearsRuleRiskConfirmationAndAutomaticStart() throws {
    var tunnel = sampleTunnel(id: UUID())
    var rule = try #require(tunnel.rules.first)
    rule.localHost = "*"
    rule.riskConfirmationSignature = rule.currentRiskSignature
    tunnel.replaceRules([rule])
    tunnel.isAutoStartEnabled = true
    let document = TunnelConfigurationDocument(appVersion: "0.4.0", configs: [tunnel])

    let preview = TunnelConfigurationTransfer().preview(document: document, existing: [], strategy: .skip)
    let imported = try #require(preview.mergedConfigs.first)

    #expect(imported.isAutoStartEnabled == false)
    #expect(imported.effectiveRules.first?.riskConfirmationSignature == nil)
}

@Test func importRejectsNewerSchemaWithoutProducingPreview() throws {
    let data = Data(#"{"schemaVersion":99,"exportedAt":"2025-06-15T15:06:40Z","appVersion":"9.0","configs":[]}"#.utf8)

    #expect(throws: TunnelConfigurationTransferError.unsupportedSchemaVersion(99)) {
        try TunnelConfigurationTransfer().decode(data)
    }
}

@Test func importRejectsOversizedFilesAndTooManyConfigs() throws {
    let oversized = Data(repeating: 0, count: TunnelConfigurationTransfer.maximumFileSize + 1)
    #expect(throws: TunnelConfigurationTransferError.fileTooLarge(
        maximumBytes: TunnelConfigurationTransfer.maximumFileSize
    )) {
        try TunnelConfigurationTransfer().decode(oversized)
    }

    let configs = (0...TunnelConfigurationTransfer.maximumConfigCount).map { index in
        sampleTunnel(id: UUID(), localPort: 20_000 + index)
    }
    #expect(throws: TunnelConfigurationTransferError.tooManyConfigs(
        maximum: TunnelConfigurationTransfer.maximumConfigCount
    )) {
        try TunnelConfigurationTransfer().exportData(configs: configs, appVersion: "0.3.2")
    }

    let oversizedConfig = sampleTunnel(id: UUID(), name: String(
        repeating: "x",
        count: TunnelConfigurationTransfer.maximumFileSize
    ))
    #expect(throws: TunnelConfigurationTransferError.fileTooLarge(
        maximumBytes: TunnelConfigurationTransfer.maximumFileSize
    )) {
        try TunnelConfigurationTransfer().exportData(configs: [oversizedConfig], appVersion: "0.3.2")
    }
}

@Test func importRejectsDuplicateIdentifiersAndInvalidFields() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
    let transfer = TunnelConfigurationTransfer()
    let duplicateData = try transfer.exportData(
        configs: [sampleTunnel(id: id), sampleTunnel(id: id, localPort: 15_433)],
        appVersion: "0.3.2"
    )
    #expect(throws: TunnelConfigurationTransferError.duplicateIdentifier(id)) {
        try transfer.decode(duplicateData)
    }

    let invalidData = Data(#"{"schemaVersion":1,"exportedAt":"2025-06-15T15:06:40Z","appVersion":"0.3.2","configs":[{"id":"00000000-0000-0000-0000-000000000063","mode":"localForward","name":"Bad","sshHost":"host","localHost":"127.0.0.1","localPort":0,"remoteHost":"127.0.0.1","remotePort":80,"tags":[],"isFavorite":false,"isAutoReconnectEnabled":false,"isAutoStartEnabled":false}]}"#.utf8)
    #expect(throws: TunnelConfigurationTransferError.self) {
        try transfer.decode(invalidData)
    }
}

@Test func previewAppliesSameIdentifierStrategiesAndDisablesAutomaticStart() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000064")!
    var existing = sampleTunnel(id: id, name: "现有配置")
    existing.manualOrder = 0
    var incoming = sampleTunnel(id: id, name: "导入配置", localPort: 15_433)
    incoming.manualOrder = 8
    incoming.isAutoStartEnabled = true
    incoming.isAutoReconnectEnabled = true
    let document = TunnelConfigurationDocument(appVersion: "0.3.2", configs: [incoming])
    let transfer = TunnelConfigurationTransfer()

    let skipped = transfer.preview(document: document, existing: [existing], strategy: .skip)
    #expect(skipped.skippedCount == 1)
    #expect(skipped.mergedConfigs.map(\.name) == ["现有配置"])

    let replaced = transfer.preview(document: document, existing: [existing], strategy: .replace)
    #expect(replaced.replacedCount == 1)
    #expect(replaced.mergedConfigs.first?.name == "导入配置")
    #expect(replaced.mergedConfigs.first?.isAutoStartEnabled == false)
    #expect(replaced.mergedConfigs.first?.isAutoReconnectEnabled == true)
    #expect(replaced.mergedConfigs.first?.manualOrder == 0)

    let copied = transfer.preview(document: document, existing: [existing], strategy: .copy)
    #expect(copied.copiedCount == 1)
    #expect(copied.mergedConfigs.count == 2)
    #expect(copied.mergedConfigs[1].id != id)
    #expect(copied.mergedConfigs[1].effectiveRules.first?.id != incoming.effectiveRules.first?.id)
    #expect(copied.mergedConfigs[1].isAutoStartEnabled == false)
    #expect(copied.mergedConfigs[1].name == "导入配置 (2)")
}

@Test func previewBlocksDuplicateNamesIgnoringCaseAndWhitespace() {
    let existing = sampleTunnel(id: UUID(), name: "Database", localPort: 15_432)
    let incoming = sampleTunnel(id: UUID(), name: " database ", localPort: 15_433)
    let document = TunnelConfigurationDocument(appVersion: "0.4.0", configs: [incoming])

    let preview = TunnelConfigurationTransfer().preview(
        document: document,
        existing: [existing],
        strategy: .skip
    )

    #expect(!preview.canCommit)
    #expect(preview.issues.contains(.duplicateName("Database")))
}

@Test func importedAndCopiedConfigsAppendWithoutReorderingExistingConfigs() {
    var existingA = sampleTunnel(id: UUID(), name: "Existing A", localPort: 10_001)
    existingA.manualOrder = 0
    var existingB = sampleTunnel(id: UUID(), name: "Existing B", localPort: 10_002)
    existingB.manualOrder = 1
    var laterSource = sampleTunnel(id: UUID(), name: "Later Source", localPort: 10_004)
    laterSource.manualOrder = 8
    var earlierSource = sampleTunnel(id: UUID(), name: "Earlier Source", localPort: 10_003)
    earlierSource.manualOrder = 2
    let document = TunnelConfigurationDocument(
        appVersion: "0.3.2",
        configs: [laterSource, earlierSource]
    )

    let preview = TunnelConfigurationTransfer().preview(
        document: document,
        existing: [existingA, existingB],
        strategy: .skip
    )

    #expect(preview.mergedConfigs.map(\.name) == [
        "Existing A", "Existing B", "Earlier Source", "Later Source",
    ])
    #expect(preview.mergedConfigs.compactMap(\.manualOrder) == [0, 1, 2, 3])
}

@Test func previewReportsExposedRemoteForwardListener() {
    var remote = TunnelConfig(
        name: "Remote",
        sshHost: "example-host",
        remoteBindHost: "*",
        remotePort: 18_080,
        localTargetHost: "127.0.0.1",
        localPort: 3_000,
        openURL: nil
    )
    remote.manualOrder = 0
    let document = TunnelConfigurationDocument(appVersion: "0.3.2", configs: [remote])

    let preview = TunnelConfigurationTransfer().preview(
        document: document,
        existing: [],
        strategy: .skip
    )

    #expect(preview.issues.contains(.exposedListener(host: "*", port: 18_080)))
    #expect(preview.canCommit)
}

@Test func previewReportsLocalPortConflictsAndExposureWithoutRunningAnything() {
    let first = sampleTunnel(id: UUID(), localPort: 15_432)
    var second = sampleTunnel(id: UUID(), localPort: 15_432)
    second.localHost = "localhost"
    var exposed = sampleTunnel(id: UUID(), localPort: 10_080)
    exposed.localHost = "*"
    let document = TunnelConfigurationDocument(appVersion: "0.3.2", configs: [second, exposed])

    let preview = TunnelConfigurationTransfer().preview(
        document: document,
        existing: [first],
        strategy: .skip
    )

    #expect(preview.canCommit == false)
    #expect(preview.issues.contains(.localEndpointConflict(host: "127.0.0.1", port: 15_432)))
    #expect(preview.issues.contains(.exposedListener(host: "*", port: 10_080)))
}

@Test func previewDetectsWildcardOverlapButDoesNotBlockOnUnchangedExistingConflict() {
    let existingA = sampleTunnel(id: UUID(), localPort: 15_432)
    let existingB = sampleTunnel(id: UUID(), localPort: 15_432)
    var imported = sampleTunnel(id: UUID(), localPort: 10_080)
    imported.localHost = "*"
    let existingOnImportedPort = sampleTunnel(id: UUID(), localPort: 10_080)
    let document = TunnelConfigurationDocument(appVersion: "0.3.2", configs: [imported])

    let preview = TunnelConfigurationTransfer().preview(
        document: document,
        existing: [existingA, existingB, existingOnImportedPort],
        strategy: .skip
    )

    #expect(preview.issues.contains(.localEndpointConflict(host: "*", port: 10_080)))
    #expect(!preview.issues.contains(.localEndpointConflict(host: "127.0.0.1", port: 15_432)))
}

@Test func storeCreatesAndRestoresPreImportBackup() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ssh-tunnel-transfer-store-\(UUID().uuidString)")
    let store = TunnelConfigStore(configURL: directory.appending(path: "tunnels.json"))
    let original = sampleTunnel(id: UUID(), name: "原配置")
    let replacement = sampleTunnel(id: UUID(), name: "新配置", localPort: 15_433)
    try store.save([original])

    #expect(try store.createPreImportBackup() == store.preImportBackupURL)
    try store.save([replacement])
    try store.restorePreImportBackup()

    #expect(try store.load() == [original])
    let attributes = try FileManager.default.attributesOfItem(atPath: store.preImportBackupURL.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o600)
}

private func sampleTunnel(
    id: UUID,
    name: String = "Example",
    localPort: Int = 15_432
) -> TunnelConfig {
    TunnelConfig(
        id: id,
        name: name,
        sshHost: "example-host",
        localHost: "127.0.0.1",
        localPort: localPort,
        remoteHost: "127.0.0.1",
        remotePort: 5_432,
        openURL: URL(string: "http://127.0.0.1:\(localPort)")
    )
}
