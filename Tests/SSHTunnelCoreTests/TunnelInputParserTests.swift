import Testing
@testable import SSHTunnelCore

@Test func parsesBlankURLAsNil() throws {
    #expect(try TunnelInputParser.optionalURL(from: "   ") == nil)
}

@Test func parsesValidURL() throws {
    #expect(try TunnelInputParser.optionalURL(from: "http://127.0.0.1:8088/pools")?.absoluteString == "http://127.0.0.1:8088/pools")
}

@Test func parsesHTTPSURL() throws {
    #expect(try TunnelInputParser.optionalURL(from: "https://example.com/pools")?.scheme == "https")
}

@Test func rejectsInvalidNonEmptyURL() {
    #expect(throws: TunnelValidationError.self) {
        _ = try TunnelInputParser.optionalURL(from: "not a url")
    }
}

@Test func rejectsURLWithoutHTTPHost() {
    #expect(throws: TunnelValidationError.self) {
        _ = try TunnelInputParser.optionalURL(from: "http:")
    }
}

@Test func rejectsNonHTTPURLSchemes() {
    #expect(throws: TunnelValidationError.self) {
        _ = try TunnelInputParser.optionalURL(from: "file:///etc/passwd")
    }
}
