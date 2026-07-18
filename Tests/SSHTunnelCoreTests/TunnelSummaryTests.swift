import Testing
@testable import SSHTunnelCore

@Test func summarizesEmptyTunnelStatuses() {
    let summary = TunnelSummary(statuses: [])

    #expect(summary.runningCount == 0)
    #expect(summary.failedCount == 0)
    #expect(summary.totalCount == 0)
    #expect(summary.displayText(language: "zh-Hans") == "运行 0 · 异常 0 · 总数 0")
}

@Test func summarizesRunningFailedAndExternalListeningStatuses() {
    let summary = TunnelSummary(statuses: [
        .running,
        .portListening,
        .failed,
        .externalListening,
        .waitingForNetwork,
        .waitingToReconnect,
        .stopped
    ])

    #expect(summary.runningCount == 2)
    #expect(summary.failedCount == 4)
    #expect(summary.totalCount == 7)
    #expect(summary.displayText(language: "zh-Hans") == "运行 2 · 异常 4 · 总数 7")
}
