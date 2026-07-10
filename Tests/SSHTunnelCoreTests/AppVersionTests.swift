import Testing
@testable import SSHTunnelCore

@Test func exposesCurrentAppVersion() {
    #expect(AppVersion.current == "0.2.1")
    #expect(AppVersion.displayText == "v0.2.1")
}
