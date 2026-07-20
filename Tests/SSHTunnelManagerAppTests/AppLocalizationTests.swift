import Testing
@testable import SSHTunnelManagerApp

@Test func appStringsLocalizeRepresentativeUIStringsToEnglishAndChinese() {
    #expect(AppStrings.addTunnel(language: "en") == "Add Tunnel")
    #expect(AppStrings.addTunnel(language: "zh-Hans") == "添加隧道")
    #expect(AppStrings.emptyStateTitle(language: "en") == "No tunnel configurations yet")
    #expect(AppStrings.emptyStateTitle(language: "zh-Hans") == "还没有隧道配置")
    #expect(AppStrings.modeDynamicForward(language: "en") == "Dynamic SOCKS")
    #expect(AppStrings.modeDynamicForward(language: "zh-Hans") == "动态 SOCKS")
    #expect(AppStrings.modeRemoteForward(language: "en") == "Remote Forward")
    #expect(AppStrings.modeRemoteForward(language: "zh-Hans") == "远程转发")
    #expect(AppStrings.compactModeName(.localForward, language: "en") == "Local")
    #expect(AppStrings.compactModeName(.remoteForward, language: "en") == "Remote")
    #expect(AppStrings.compactModeName(.dynamicForward, language: "en") == "SOCKS")
    #expect(AppStrings.compactModeName(.sshConfig, language: "en") == "SSH Config")
    #expect(AppStrings.riskyLocalBindTitle(language: "en") == "Local listener may be exposed")
    #expect(AppStrings.riskyLocalBindTitle(language: "zh-Hans") == "本地监听可能暴露")
    #expect(AppStrings.riskyRemoteBindTitle(language: "en") == "Remote listener may be exposed")
    #expect(AppStrings.riskyRemoteBindTitle(language: "zh-Hans") == "远端监听可能暴露")
    #expect(AppStrings.shortcutSettingsTitle(language: "en") == "Global Shortcut")
    #expect(AppStrings.shortcutSettingsTitle(language: "zh-Hans") == "全局快捷键")
    #expect(AppStrings.deleteTunnelConfirmationTitle(language: "en") == "Delete tunnel configuration?")
    #expect(AppStrings.deleteTunnelConfirmationTitle(language: "zh-Hans") == "删除隧道配置？")
    #expect(AppStrings.searchTunnels(language: "en") == "Search tunnels")
    #expect(AppStrings.searchTunnels(language: "zh-Hans") == "搜索隧道")
    #expect(AppStrings.sortManual(language: "en") == "Manual")
    #expect(AppStrings.sortManual(language: "zh-Hans") == "手工排序")
    #expect(AppStrings.importSSHConfig(language: "en") == "Import SSH Config")
    #expect(AppStrings.importSSHConfig(language: "zh-Hans") == "导入 SSH Config")
    #expect(AppStrings.importSelectionCount(2, language: "en") == "2 selected")
    #expect(AppStrings.importSelectionCount(2, language: "zh-Hans") == "已选 2 项")
    #expect(AppStrings.importManualAlias(language: "zh-Hans") == "通配 Host 的具体别名（可选）")
    #expect(AppStrings.importManualAliasHelp(language: "en").contains("does not modify SSH Config"))
    #expect(AppStrings.formAutomation(language: "en") == "Automation")
    #expect(AppStrings.formAutomation(language: "zh-Hans") == "自动化")
    #expect(AppStrings.formAutoStart(language: "en") == "Connect when the app starts")
    #expect(AppStrings.formAutoStart(language: "zh-Hans") == "应用启动时连接")
    #expect(AppStrings.formAutoReconnect(language: "en") == "Reconnect after disconnecting")
    #expect(AppStrings.formAutoReconnect(language: "zh-Hans") == "断线后自动重连")
    #expect(AppStrings.string("configuration.type.connectionGroup", language: "en") == "Connection Group")
    #expect(AppStrings.string("configuration.type.connectionGroup", language: "zh-Hans") == "连接组")
    #expect(AppStrings.string("configuration.type.sshConfigReference", language: "en") == "SSH Config Reference")
    #expect(AppStrings.string("configuration.type.sshConfigReference", language: "zh-Hans") == "SSH Config 引用")
    #expect(AppStrings.string("form.rule.enabled", language: "en") == "Enable this rule")
    #expect(AppStrings.string("form.rule.enabled", language: "zh-Hans") == "启用此规则")
    #expect(AppStrings.string("error.noEnabledRules", language: "zh-Hans").contains("至少启用一条"))
    #expect(AppStrings.string("error.configurationTypeImmutable", language: "en").contains("cannot be changed"))
    #expect(AppStrings.string("error.configurationTypeImmutable", language: "zh-Hans").contains("不能改变类型"))
    #expect(AppStrings.string("portRecommendation.action", language: "en") == "Recommend Available Port")
    #expect(AppStrings.string("portRecommendation.action", language: "zh-Hans") == "推荐可用端口")
    #expect(AppStrings.format("portRecommendation.use", language: "en", 18_081) == "Use 18081")
    #expect(AppStrings.format("portRecommendation.use", language: "zh-Hans", 18_081) == "使用 18081")
    #expect(AppStrings.string("health.form.enabled", language: "en") == "Enable connection health check")
    #expect(AppStrings.string("health.form.enabled", language: "zh-Hans") == "启用连接健康检查")
    #expect(AppStrings.healthKind(.socks5, language: "en") == "SOCKS5")
    #expect(AppStrings.healthPhase(RuleHealthCheckPhase.unhealthy, language: "zh-Hans") == "异常")
    #expect(AppStrings.healthFailureCategory(.tls, language: "en") == "TLS validation failed")
    #expect(AppStrings.loginItemSettingsTitle(language: "en") == "Launch at Login")
    #expect(AppStrings.loginItemSettingsTitle(language: "zh-Hans") == "登录时启动")
    #expect(AppStrings.notificationUnavailableOutsideApp(language: "en").contains("swift run"))
    #expect(AppStrings.notificationUnavailableOutsideApp(language: "zh-Hans").contains("swift run"))
}

@Test func notificationAndDiagnosticCopyLocalizesToEnglishAndChinese() {
    #expect(AppStrings.settingsTitle(language: "en") == "Settings")
    #expect(AppStrings.close(language: "en") == "Close")
    #expect(AppStrings.close(language: "zh-Hans") == "关闭")
    #expect(AppStrings.configurationExportRequiresSelection(language: "zh-Hans").contains("至少选择一个"))
    #expect(AppStrings.configurationOpeningExportPanel(language: "en").contains("system save window"))
    #expect(AppStrings.settingsTitle(language: "zh-Hans") == "设置")
    #expect(AppStrings.notificationSettingsTitle(language: "en") == "Connection Notifications")
    #expect(AppStrings.notificationSettingsTitle(language: "zh-Hans") == "连接通知")
    #expect(AppStrings.notificationPermissionDenied(language: "en").contains("System Settings > Notifications"))
    #expect(AppStrings.notificationPermissionDenied(language: "zh-Hans").contains("系统设置 > 通知"))
    #expect(AppStrings.notificationFailureBody(
        category: .network,
        retryCount: 2,
        willRetry: true,
        language: "en"
    ) == "Network error. Automatic recovery remains active (failure 2).")
    #expect(AppStrings.notificationFailureBody(
        category: .network,
        retryCount: 2,
        willRetry: true,
        language: "zh-Hans"
    ) == "网络错误，自动恢复仍在进行（第 2 次失败）。")
    #expect(AppStrings.connectionDetails(language: "en") == "Connection Details")
    #expect(AppStrings.connectionDetails(language: "zh-Hans") == "连接详情")
    #expect(AppStrings.failureCategory(.authentication, language: "en") == "Authentication")
    #expect(AppStrings.failureCategory(.authentication, language: "zh-Hans") == "认证")
}

@Test func remoteBindWarningIncludesConfirmedEndpointAndGatewayPorts() {
    let english = AppStrings.riskyRemoteBindMessage(host: "*", port: 18_080, language: "en")
    let chinese = AppStrings.riskyRemoteBindMessage(host: "*", port: 18_080, language: "zh-Hans")

    #expect(english.contains("*:18080"))
    #expect(english.contains("GatewayPorts"))
    #expect(chinese.contains("*:18080"))
    #expect(chinese.contains("GatewayPorts"))
}

@Test func deleteTunnelConfirmationNamesTheTunnelAndExplainsTheConsequence() {
    let english = AppStrings.deleteTunnelConfirmationMessage(name: "Example Service", language: "en")
    let chinese = AppStrings.deleteTunnelConfirmationMessage(name: "示例服务", language: "zh-Hans")

    #expect(english.contains("Example Service"))
    #expect(english.contains("cannot be undone"))
    #expect(english.contains("stopped first"))
    #expect(chinese.contains("示例服务"))
    #expect(chinese.contains("无法撤销"))
    #expect(chinese.contains("先停止"))
}

@Test func globalShortcutFormatterDisplaysDefaultShortcut() {
    #expect(GlobalShortcutFormatter.displayText(for: .defaultShortcut) == "⌃⌥⌘T")
    #expect(GlobalShortcutFormatter.accessibilityText(for: .defaultShortcut) == "Control Option Command T")
}

@Test func shortcutConflictMessageExplainsRollbackInEnglishAndChinese() {
    #expect(
        AppStrings.string("shortcut.error.conflict", language: "en")
            .contains("previous shortcut remains active")
    )
    #expect(
        AppStrings.string("shortcut.error.conflict", language: "zh-Hans")
            .contains("原快捷键仍然有效")
    )
}

@Test func appStringsFormatRuntimeErrorsInEnglishAndChinese() {
    #expect(
        AppStrings.localPortAlreadyListeningOutsideApp(host: "127.0.0.1", port: 1080, language: "en")
            == "Local port 127.0.0.1:1080 is already listening outside this app."
    )
    #expect(
        AppStrings.localPortAlreadyListeningOutsideApp(host: "127.0.0.1", port: 1080, language: "zh-Hans")
            == "本地端口 127.0.0.1:1080 已被本应用之外的进程监听。"
    )
}

@Test func appLocalizationKeysMatchAcrossEnglishAndChinese() throws {
    let englishKeys = try AppStrings.localizationKeys(language: "en")
    let chineseKeys = try AppStrings.localizationKeys(language: "zh-Hans")

    #expect(englishKeys == chineseKeys)
    #expect(englishKeys.contains("button.addTunnel"))
    #expect(englishKeys.contains("shortcut.settings.title"))
    #expect(englishKeys.contains("delete.confirmation.message"))
    #expect(englishKeys.contains("filter.search"))
    #expect(englishKeys.contains("sort.manual"))
    #expect(englishKeys.contains("import.matchExec.message"))
}
