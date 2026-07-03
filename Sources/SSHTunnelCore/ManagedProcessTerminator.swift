import Darwin
import Foundation

public enum ManagedProcessTerminator {
    @discardableResult
    public static func terminateAndWait(
        _ process: Process,
        timeout: TimeInterval,
        forceKillAfterTimeout: Bool = false
    ) -> Bool {
        guard process.isRunning else {
            return true
        }

        process.terminate()
        if waitUntilExit(process, timeout: timeout) {
            return true
        }

        guard forceKillAfterTimeout,
              process.isRunning else {
            return false
        }

        kill(process.processIdentifier, SIGKILL)
        return waitUntilExit(process, timeout: 0.5)
    }

    private static func waitUntilExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}
