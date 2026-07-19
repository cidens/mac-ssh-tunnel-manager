import Testing
@testable import SSHTunnelCore

@Test func exposesCurrentAppVersion() {
    #expect(AppVersion.current == "0.4.0")
    #expect(AppVersion.displayText == "v0.4.0")
}
