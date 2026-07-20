import Testing
@testable import SSHTunnelCore

@Test func exposesCurrentAppVersion() {
    #expect(AppVersion.current == "0.5.0")
    #expect(AppVersion.displayText == "v0.5.0")
}
