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
}

@Test func notificationAndDiagnosticCopyLocalizesToEnglishAndChinese() {
    #expect(AppStrings.settingsTitle(language: "en") == "Settings")
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
}
