import Testing
@testable import SSHTunnelManagerApp

@Test func appStringsLocalizeRepresentativeUIStringsToEnglishAndChinese() {
    #expect(AppStrings.addTunnel(language: "en") == "Add Tunnel")
    #expect(AppStrings.addTunnel(language: "zh-Hans") == "添加隧道")
    #expect(AppStrings.emptyStateTitle(language: "en") == "No tunnel configurations yet")
    #expect(AppStrings.emptyStateTitle(language: "zh-Hans") == "还没有隧道配置")
    #expect(AppStrings.modeDynamicForward(language: "en") == "Dynamic SOCKS")
    #expect(AppStrings.modeDynamicForward(language: "zh-Hans") == "动态 SOCKS")
    #expect(AppStrings.riskyLocalBindTitle(language: "en") == "Local listener may be exposed")
    #expect(AppStrings.riskyLocalBindTitle(language: "zh-Hans") == "本地监听可能暴露")
    #expect(AppStrings.shortcutSettingsTitle(language: "en") == "Global Shortcut")
    #expect(AppStrings.shortcutSettingsTitle(language: "zh-Hans") == "全局快捷键")
    #expect(AppStrings.deleteTunnelConfirmationTitle(language: "en") == "Delete tunnel configuration?")
    #expect(AppStrings.deleteTunnelConfirmationTitle(language: "zh-Hans") == "删除隧道配置？")
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
}
