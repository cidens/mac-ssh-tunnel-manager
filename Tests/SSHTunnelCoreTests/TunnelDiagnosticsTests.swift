import Foundation
import Testing
@testable import SSHTunnelCore

@Test func notificationCycleEmitsOneFailureAndOneRecoveryPerCycle() {
    var cycle = TunnelNotificationCycle()

    let firstFailure = cycle.beginFailure()
    let duplicateFailure = cycle.beginFailure()
    let firstRecovery = cycle.recover()
    let duplicateRecovery = cycle.recover()
    let nextCycleFailure = cycle.beginFailure()

    #expect(firstFailure)
    #expect(!duplicateFailure)
    #expect(firstRecovery)
    #expect(!duplicateRecovery)
    #expect(nextCycleFailure)

    cycle.reset()
    let recoveryAfterReset = cycle.recover()
    #expect(!cycle.isFailureActive)
    #expect(!recoveryAfterReset)
}

@Test func failureCategoriesCoverKnownAndUnknownErrors() {
    #expect(TunnelFailureCategory.classify("Permission denied (publickey)") == .authentication)
    #expect(TunnelFailureCategory.classify("Host key verification failed") == .hostKey)
    #expect(TunnelFailureCategory.classify("bind: Address already in use") == .portConflict)
    #expect(TunnelFailureCategory.classify("Bad configuration option") == .configuration)
    #expect(TunnelFailureCategory.classify("Could not resolve hostname example") == .configuration)
    #expect(TunnelFailureCategory.classify("Network is unreachable") == .network)
    #expect(TunnelFailureCategory.classify("unexpected ssh exit") == .unknown)
}

@Test func diagnosticReportContainsOnlyShareableStructuredFields() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let report = TunnelDiagnosticReport(
        appVersion: "0.3.2",
        systemVersion: "macOS 14.0",
        architecture: "arm64",
        mode: .localForward,
        status: .failed,
        statusChangedAt: date,
        exitCode: 255,
        retryCount: 3,
        nextRetryAt: date.addingTimeInterval(30),
        errorCategory: .authentication
    ).text

    #expect(report == """
    appVersion=0.3.2
    systemVersion=macOS 14.0
    architecture=arm64
    mode=localForward
    status=Failed
    statusChangedAt=2023-11-14T22:13:20Z
    exitCode=255
    retryCount=3
    nextRetryAt=2023-11-14T22:13:50Z
    errorCategory=authentication
    """)
}

@Test func diagnosticReportUsesExplicitEmptyValues() {
    let report = TunnelDiagnosticReport(
        appVersion: "0.3.2",
        systemVersion: "macOS",
        architecture: "arm64",
        mode: .sshConfig,
        status: .stopped,
        statusChangedAt: Date(timeIntervalSince1970: 0),
        exitCode: nil,
        retryCount: 0,
        nextRetryAt: nil,
        errorCategory: nil
    ).text

    #expect(report.contains("exitCode=none"))
    #expect(report.contains("nextRetryAt=none"))
    #expect(report.contains("errorCategory=none"))
}
