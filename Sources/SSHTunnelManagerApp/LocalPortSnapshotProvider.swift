import Foundation
import SSHTunnelCore

protocol LocalPortSnapshotProviding: Sendable {
    func snapshot() throws -> String
}

struct SystemLocalPortSnapshotProvider: LocalPortSnapshotProviding {
    let timeout: TimeInterval

    init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    func snapshot() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LocalPortRecommendationError.snapshotFailed
        }

        let outputBuffer = LocalPortSnapshotOutputBuffer()
        let readCompleted = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            outputBuffer.replace(with: output.fileHandleForReading.readDataToEndOfFile())
            readCompleted.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            if Task.isCancelled {
                ManagedProcessTerminator.terminateAndWait(process, timeout: 0.2, forceKillAfterTimeout: true)
                _ = readCompleted.wait(timeout: .now() + 0.5)
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        guard !process.isRunning else {
            ManagedProcessTerminator.terminateAndWait(process, timeout: 0.2, forceKillAfterTimeout: true)
            _ = readCompleted.wait(timeout: .now() + 0.5)
            throw LocalPortRecommendationError.snapshotTimedOut
        }

        readCompleted.wait()
        let data = outputBuffer.data
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 || (process.terminationStatus == 1 && text.isEmpty) else {
            throw LocalPortRecommendationError.snapshotFailed
        }
        return text
    }
}

private final class LocalPortSnapshotOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.withLock { storage }
    }

    func replace(with data: Data) {
        lock.withLock { storage = data }
    }
}

enum LocalPortRecommendationError: Error, Equatable, LocalizedError {
    case unsupportedRule
    case invalidListenerHost
    case noAvailablePort
    case snapshotFailed
    case snapshotTimedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedRule:
            return AppStrings.string("portRecommendation.error.unsupported")
        case .invalidListenerHost:
            return AppStrings.string("portRecommendation.error.invalidHost")
        case .noAvailablePort:
            return AppStrings.string("portRecommendation.error.unavailable")
        case .snapshotFailed:
            return AppStrings.string("portRecommendation.error.snapshotFailed")
        case .snapshotTimedOut:
            return AppStrings.string("portRecommendation.error.snapshotTimedOut")
        }
    }
}
