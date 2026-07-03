import Testing
@testable import SSHTunnelCore

@Test func runtimeStatusReportsExternalListeningSeparatelyFromManagedProcess() {
    let status = TunnelRuntimeStatusResolver.status(
        isManagedProcessRunning: false,
        isPortListening: true,
        lastError: ""
    )

    #expect(status == .externalListening)
}

@Test func runtimeStatusReportsManagedProcessWithListeningPortAsListening() {
    let status = TunnelRuntimeStatusResolver.status(
        isManagedProcessRunning: true,
        isPortListening: true,
        lastError: ""
    )

    #expect(status == .portListening)
}

@Test func runtimeStatusReportsFailedOnlyAfterManagedProcessEndsWithError() {
    let status = TunnelRuntimeStatusResolver.status(
        isManagedProcessRunning: false,
        isPortListening: false,
        lastError: "bind: Address already in use"
    )

    #expect(status == .failed)
}
