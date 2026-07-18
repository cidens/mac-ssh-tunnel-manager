import Foundation

public enum TunnelLifecyclePhase: Equatable, Sendable {
    case stopped
    case connecting
    case running
    case waitingForNetwork
    case waitingToReconnect(delay: TimeInterval)
    case failed
}

public enum TunnelStopReason: Equatable, Sendable {
    case userRequested
    case applicationTerminating
    case configurationChanged
    case processExited
    case nonRetryableFailure
}

public struct TunnelRecoveryPolicy: Equatable, Sendable {
    public static let retryDelays: [TimeInterval] = [2, 5, 10, 30, 60]
    public static let stableRunResetInterval: TimeInterval = 300
    public static let networkStabilityInterval: TimeInterval = 2

    public init() {}

    public func retryDelay(afterFailureCount failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return Self.retryDelays[0] }
        return Self.retryDelays[min(failureCount - 1, Self.retryDelays.count - 1)]
    }
}

public struct TunnelRecoveryState: Equatable, Sendable {
    public private(set) var phase: TunnelLifecyclePhase = .stopped
    public private(set) var generation: UInt64 = 0
    public private(set) var wantsToRun = false
    public private(set) var failureCount = 0
    public private(set) var isNetworkAvailable = true
    public private(set) var isSleeping = false
    public private(set) var lastStopReason: TunnelStopReason?

    public init() {}

    @discardableResult
    public mutating func requestStart() -> UInt64 {
        generation &+= 1
        wantsToRun = true
        failureCount = 0
        lastStopReason = nil
        phase = canAttemptConnection ? .connecting : .waitingForNetwork
        return generation
    }

    public mutating func markRunning(generation expectedGeneration: UInt64) -> Bool {
        guard acceptsCallback(generation: expectedGeneration) else { return false }
        phase = .running
        return true
    }

    public mutating func markStable(generation expectedGeneration: UInt64) -> Bool {
        guard acceptsCallback(generation: expectedGeneration), phase == .running else { return false }
        failureCount = 0
        return true
    }

    public mutating func processExited(
        generation expectedGeneration: UInt64,
        retryable: Bool,
        autoReconnectEnabled: Bool,
        policy: TunnelRecoveryPolicy = TunnelRecoveryPolicy()
    ) -> TimeInterval? {
        guard acceptsCallback(generation: expectedGeneration) else { return nil }
        guard retryable else {
            wantsToRun = false
            phase = .failed
            lastStopReason = .nonRetryableFailure
            return nil
        }
        guard autoReconnectEnabled else {
            wantsToRun = false
            phase = .failed
            lastStopReason = .processExited
            return nil
        }

        failureCount += 1
        lastStopReason = .processExited
        guard canAttemptConnection else {
            phase = .waitingForNetwork
            return nil
        }
        let delay = policy.retryDelay(afterFailureCount: failureCount)
        phase = .waitingToReconnect(delay: delay)
        return delay
    }

    @discardableResult
    public mutating func requestStop(reason: TunnelStopReason) -> UInt64 {
        generation &+= 1
        wantsToRun = false
        lastStopReason = reason
        phase = reason == .nonRetryableFailure ? .failed : .stopped
        return generation
    }

    public mutating func setNetworkAvailable(_ available: Bool) -> Bool {
        isNetworkAvailable = available
        guard wantsToRun else { return false }
        if !available {
            phase = .waitingForNetwork
            return false
        }
        return !isSleeping && phase == .waitingForNetwork
    }

    public mutating func setSleeping(_ sleeping: Bool) -> Bool {
        isSleeping = sleeping
        guard wantsToRun else { return false }
        if sleeping {
            phase = .waitingForNetwork
            return false
        }
        return isNetworkAvailable && phase == .waitingForNetwork
    }

    public mutating func beginRecoveryAfterNetworkStabilized() -> UInt64? {
        guard wantsToRun, canAttemptConnection, phase == .waitingForNetwork else { return nil }
        generation &+= 1
        phase = .connecting
        return generation
    }

    public mutating func resumeRunningProcessAfterRecovery() -> Bool {
        guard wantsToRun, canAttemptConnection, phase == .waitingForNetwork else { return false }
        phase = .running
        return true
    }

    public mutating func beginScheduledRetry(generation expectedGeneration: UInt64) -> Bool {
        guard acceptsCallback(generation: expectedGeneration), canAttemptConnection else { return false }
        guard case .waitingToReconnect = phase else { return false }
        phase = .connecting
        return true
    }

    private var canAttemptConnection: Bool {
        isNetworkAvailable && !isSleeping
    }

    private func acceptsCallback(generation expectedGeneration: UInt64) -> Bool {
        wantsToRun && generation == expectedGeneration
    }
}

public enum TunnelFailureClassifier {
    public static func isRetryable(stderr: String) -> Bool {
        let text = stderr.lowercased()
        let nonRetryableFragments = [
            "permission denied",
            "authentication failed",
            "host key verification failed",
            "remote host identification has changed",
            "address already in use",
            "cannot listen to port",
            "could not request local forwarding",
            "could not request remote forwarding",
            "remote port forwarding failed",
            "could not resolve hostname",
            "bad configuration option",
            "illegal option",
            "unknown option"
        ]
        return !nonRetryableFragments.contains(where: text.contains)
    }

    public static func isRetryable(validationError: TunnelValidationError) -> Bool {
        if case .sshConfigValidationTimedOut = validationError {
            return true
        }
        return false
    }
}
