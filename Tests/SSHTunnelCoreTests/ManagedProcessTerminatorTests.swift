import Foundation
import Testing
@testable import SSHTunnelCore

@Test func terminatesRunningProcessAndWaitsForExit() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["10"]
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let didExit = ManagedProcessTerminator.terminateAndWait(process, timeout: 2)

    #expect(didExit)
    #expect(process.isRunning == false)
}

@Test func treatsAlreadyExitedProcessAsTerminated() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()

    let didExit = ManagedProcessTerminator.terminateAndWait(process, timeout: 1)

    #expect(didExit)
    #expect(process.isRunning == false)
}
