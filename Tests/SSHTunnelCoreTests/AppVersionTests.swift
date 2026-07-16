import Testing
@testable import SSHTunnelCore

@Test func exposesCurrentAppVersion() {
    #expect(AppVersion.current == "0.3.0")
    #expect(AppVersion.displayText == "v0.3.0")
}
