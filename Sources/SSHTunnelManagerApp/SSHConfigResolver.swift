import Darwin
import Foundation

enum SSHConfigResolution: Equatable, Sendable {
    case resolved(String)
    case failed
    case timedOut
}

protocol SSHConfigResolving: Sendable {
    func resolveConfig(named name: String, timeout: TimeInterval) -> SSHConfigResolution
}

struct SystemSSHConfigResolver: SSHConfigResolving {
    func resolveConfig(named name: String, timeout: TimeInterval) -> SSHConfigResolution {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-G", name]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let outputBuffer = SSHConfigOutputBuffer()
            let readCompleted = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                outputBuffer.replace(with: output.fileHandleForReading.readDataToEndOfFile())
                readCompleted.signal()
            }
            guard waitUntilExit(process, timeout: timeout) else {
                try? output.fileHandleForReading.close()
                _ = readCompleted.wait(timeout: .now() + 0.5)
                return .timedOut
            }
            readCompleted.wait()
            guard process.terminationStatus == 0 else {
                return .failed
            }
            return .resolved(String(data: outputBuffer.data, encoding: .utf8) ?? "")
        } catch {
            return .failed
        }
    }

    private func waitUntilExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .success {
            return true
        }

        process.terminate()
        if semaphore.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = semaphore.wait(timeout: .now() + 0.5)
        }
        return false
    }
}

private final class SSHConfigOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.withLock { storage }
    }

    func replace(with data: Data) {
        lock.withLock { storage = data }
    }
}
