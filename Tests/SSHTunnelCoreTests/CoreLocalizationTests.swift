import Testing
@testable import SSHTunnelCore

@Test func runtimeStatusDisplayTextLocalizesToEnglishAndChinese() {
    #expect(TunnelRuntimeStatus.running.displayText(language: "en") == "Running")
    #expect(TunnelRuntimeStatus.running.displayText(language: "zh-Hans") == "运行中")
    #expect(TunnelRuntimeStatus.connecting.displayText(language: "en") == "Connecting")
    #expect(TunnelRuntimeStatus.connecting.displayText(language: "zh-Hans") == "正在连接")
    #expect(TunnelRuntimeStatus.waitingForNetwork.displayText(language: "en") == "Waiting for network")
    #expect(TunnelRuntimeStatus.waitingForNetwork.displayText(language: "zh-Hans") == "等待网络")
    #expect(TunnelRuntimeStatus.waitingToReconnect.displayText(language: "en") == "Waiting to reconnect")
    #expect(TunnelRuntimeStatus.waitingToReconnect.displayText(language: "zh-Hans") == "等待重连")
    #expect(TunnelRuntimeStatus.externalListening.displayText(language: "en") == "Port occupied")
    #expect(TunnelRuntimeStatus.externalListening.displayText(language: "zh-Hans") == "端口占用")
}

@Test func summaryDisplayTextLocalizesToEnglishAndChinese() {
    let summary = TunnelSummary(statuses: [.running, .portListening, .failed])

    #expect(summary.displayText(language: "en") == "Running 2 · Issues 1 · Total 3")
    #expect(summary.displayText(language: "zh-Hans") == "运行 2 · 异常 1 · 总数 3")
}

@Test func validationErrorDescriptionsLocalizeToEnglishAndChinese() {
    #expect(
        TunnelValidationError.invalidPort("localPort").description(language: "en")
            == "Local port must be between 1 and 65535"
    )
    #expect(
        TunnelValidationError.invalidPort("localPort").description(language: "zh-Hans")
            == "本地端口必须在 1 到 65535 之间"
    )
    #expect(
        TunnelValidationError.sshConfigMissingForwardingDirective("example-service")
            .description(language: "en")
            == "example-service must be an SSH Config Host with at least one LocalForward, RemoteForward, or DynamicForward"
    )
    #expect(
        TunnelValidationError.sshConfigMissingForwardingDirective("example-service")
            .description(language: "zh-Hans")
            == "example-service 必须是至少包含一条 LocalForward、RemoteForward 或 DynamicForward 的 SSH Config Host"
    )
    #expect(
        TunnelValidationError.sshHostContainsForwardingDirectives("example-bastion").description(language: "en")
            == "SSH Host example-bastion already defines forwarding directives. Use SSH Config mode or choose a Host without LocalForward, RemoteForward, or DynamicForward."
    )
    #expect(
        TunnelValidationError.sshHostContainsForwardingDirectives("example-bastion").description(language: "zh-Hans")
            == "SSH Host example-bastion 已经定义转发指令。请改用 SSH Config 模式，或选择不包含 LocalForward、RemoteForward、DynamicForward 的 Host。"
    )
}

@Test func coreLocalizationKeysMatchAcrossEnglishAndChinese() throws {
    let englishKeys = try CoreStrings.localizationKeys(language: "en")
    let chineseKeys = try CoreStrings.localizationKeys(language: "zh-Hans")

    #expect(englishKeys == chineseKeys)
    #expect(englishKeys.contains("summary.display"))
}
