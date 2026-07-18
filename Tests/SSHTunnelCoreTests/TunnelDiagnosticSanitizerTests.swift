import Testing
@testable import SSHTunnelCore

@Test func diagnosticSanitizerRedactsConfiguredHostsAndHomeDirectory() {
    let message = "ssh: connect to host internal.example.test; config /Users/example/.ssh/config"

    let sanitized = TunnelDiagnosticSanitizer.sanitize(
        message,
        sensitiveValues: ["internal.example.test"],
        homeDirectory: "/Users/example"
    )

    #expect(sanitized == "ssh: connect to host <redacted>; config ~/.ssh/config")
}

@Test func diagnosticSanitizerKeepsLoopbackEndpointsUseful() {
    let message = "bind 127.0.0.1:18080: Address already in use"

    let sanitized = TunnelDiagnosticSanitizer.sanitize(
        message,
        sensitiveValues: ["127.0.0.1"],
        homeDirectory: "/Users/example"
    )

    #expect(sanitized == message)
}

@Test func diagnosticSanitizerDoesNotReplaceShortValuesInsideNormalWords() {
    let message = "debug connection state"

    let sanitized = TunnelDiagnosticSanitizer.sanitize(
        message,
        sensitiveValues: ["db"],
        homeDirectory: "/Users/example"
    )

    #expect(sanitized == message)
}
