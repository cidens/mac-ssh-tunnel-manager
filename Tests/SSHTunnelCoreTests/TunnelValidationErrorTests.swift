import Testing
@testable import SSHTunnelCore

@Test func describesSSHConfigValidationTimeout() {
    let error = TunnelValidationError.sshConfigValidationTimedOut("example-service", 10)

    #expect(error.description(language: "zh-Hans") == "检查 SSH Config Host example-service 超时（10 秒）。常见原因是 Match exec、ProxyJump 或网络探测较慢；请重试，或检查 SSH 配置。")
}
