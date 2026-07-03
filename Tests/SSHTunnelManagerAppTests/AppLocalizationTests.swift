import Testing
@testable import SSHTunnelManagerApp

@Test func appStringsLocalizeRepresentativeUIStringsToEnglishAndChinese() {
    #expect(AppStrings.addTunnel(language: "en") == "Add Tunnel")
    #expect(AppStrings.addTunnel(language: "zh-Hans") == "添加隧道")
    #expect(AppStrings.emptyStateTitle(language: "en") == "No tunnel configurations yet")
    #expect(AppStrings.emptyStateTitle(language: "zh-Hans") == "还没有隧道配置")
    #expect(AppStrings.modeDynamicForward(language: "en") == "Dynamic SOCKS")
    #expect(AppStrings.modeDynamicForward(language: "zh-Hans") == "动态 SOCKS")
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
}
