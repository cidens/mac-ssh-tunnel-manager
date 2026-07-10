import Foundation

enum SSHConfigResolution: Equatable {
    case resolved(String)
    case failed
    case timedOut
}

protocol SSHConfigResolving {
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
            guard waitUntilExit(process, timeout: timeout) else {
                return .timedOut
            }
            guard process.terminationStatus == 0 else {
                return .failed
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return .resolved(String(data: data, encoding: .utf8) ?? "")
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
        _ = semaphore.wait(timeout: .now() + 1)
        return false
    }
}
