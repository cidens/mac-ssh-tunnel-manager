public struct TunnelSummary: Equatable, Sendable {
    public let runningCount: Int
    public let failedCount: Int
    public let totalCount: Int

    public init(statuses: [TunnelRuntimeStatus]) {
        runningCount = statuses.filter { $0 == .running || $0 == .portListening }.count
        failedCount = statuses.filter { $0 == .failed || $0 == .externalListening }.count
        totalCount = statuses.count
    }

    public var displayText: String {
        displayText()
    }

    public func displayText(language: String? = nil) -> String {
        CoreStrings.format(
            "summary.display",
            language: language,
            runningCount,
            failedCount,
            totalCount
        )
    }
}
