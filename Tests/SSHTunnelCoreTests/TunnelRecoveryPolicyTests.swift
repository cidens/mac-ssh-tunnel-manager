import Foundation
import Testing
@testable import SSHTunnelCore

@Test func recoveryPolicyUsesBoundedBackoffSequence() {
    let policy = TunnelRecoveryPolicy()
    let delays = (1...7).map { policy.retryDelay(afterFailureCount: $0) }

    #expect(delays == [2, 5, 10, 30, 60, 60, 60])
}

@Test func retryableFailuresAdvanceBackoffWithoutFastLooping() throws {
    var state = TunnelRecoveryState()
    let firstGeneration = state.requestStart()
    let firstRunStarted = state.markRunning(generation: firstGeneration)
    #expect(firstRunStarted)

    let firstDelay = state.processExited(
        generation: firstGeneration,
        retryable: true,
        autoReconnectEnabled: true
    )
    #expect(firstDelay == 2)
    #expect(state.phase == .waitingToReconnect(delay: 2))
    let firstRetryStarted = state.beginScheduledRetry(generation: firstGeneration)
    let secondRunStarted = state.markRunning(generation: firstGeneration)
    #expect(firstRetryStarted)
    #expect(secondRunStarted)

    let secondDelay = state.processExited(
        generation: firstGeneration,
        retryable: true,
        autoReconnectEnabled: true
    )
    #expect(secondDelay == 5)
    #expect(state.failureCount == 2)
}

@Test func stableRunClearsFailureCount() {
    var state = TunnelRecoveryState()
    let generation = state.requestStart()
    let firstRunStarted = state.markRunning(generation: generation)
    #expect(firstRunStarted)
    _ = state.processExited(generation: generation, retryable: true, autoReconnectEnabled: true)
    let retryStarted = state.beginScheduledRetry(generation: generation)
    let secondRunStarted = state.markRunning(generation: generation)
    #expect(retryStarted)
    #expect(secondRunStarted)

    let markedStable = state.markStable(generation: generation)
    #expect(markedStable)
    #expect(state.failureCount == 0)
}

@Test func userStopInvalidatesRetryAndOldProcessCallbacks() {
    var state = TunnelRecoveryState()
    let oldGeneration = state.requestStart()
    let runStarted = state.markRunning(generation: oldGeneration)
    #expect(runStarted)
    _ = state.processExited(generation: oldGeneration, retryable: true, autoReconnectEnabled: true)

    let stoppedGeneration = state.requestStop(reason: .userRequested)

    #expect(stoppedGeneration != oldGeneration)
    #expect(state.phase == .stopped)
    #expect(!state.wantsToRun)
    #expect(state.lastStopReason == .userRequested)
    let staleRetryStarted = state.beginScheduledRetry(generation: oldGeneration)
    let staleRunMarked = state.markRunning(generation: oldGeneration)
    #expect(!staleRetryStarted)
    #expect(!staleRunMarked)
}

@Test func staleCallbackCannotChangeANewerRunGeneration() {
    var state = TunnelRecoveryState()
    let oldGeneration = state.requestStart()
    _ = state.requestStop(reason: .configurationChanged)
    let newGeneration = state.requestStart()
    let staleExitDelay = state.processExited(
        generation: oldGeneration,
        retryable: true,
        autoReconnectEnabled: true
    )

    #expect(newGeneration != oldGeneration)
    #expect(staleExitDelay == nil)
    #expect(state.phase == .connecting)
    #expect(state.wantsToRun)
}

@Test func networkAndSleepPauseRecoveryUntilStableResume() throws {
    var state = TunnelRecoveryState()
    let generation = state.requestStart()
    let runStarted = state.markRunning(generation: generation)
    #expect(runStarted)

    let recoverWhileOffline = state.setNetworkAvailable(false)
    let offlineExitDelay = state.processExited(
        generation: generation,
        retryable: true,
        autoReconnectEnabled: true
    )
    #expect(!recoverWhileOffline)
    #expect(state.phase == .waitingForNetwork)
    #expect(offlineExitDelay == nil)
    let networkRecoveryRequested = state.setNetworkAvailable(true)
    #expect(networkRecoveryRequested)

    _ = state.setSleeping(true)
    let recoveryWhileSleeping = state.beginRecoveryAfterNetworkStabilized()
    #expect(recoveryWhileSleeping == nil)
    let wakeRecoveryRequested = state.setSleeping(false)
    #expect(wakeRecoveryRequested)
    let recoveredGenerationValue = state.beginRecoveryAfterNetworkStabilized()
    let recoveredGeneration = try #require(recoveredGenerationValue)
    #expect(recoveredGeneration != generation)
    #expect(state.phase == .connecting)
}

@Test func nonRetryableFailuresStopAutomaticRecovery() {
    var state = TunnelRecoveryState()
    let generation = state.requestStart()
    let retryDelay = state.processExited(
        generation: generation,
        retryable: false,
        autoReconnectEnabled: true
    )

    #expect(retryDelay == nil)
    #expect(state.phase == .failed)
    #expect(!state.wantsToRun)
    #expect(state.lastStopReason == .nonRetryableFailure)
}

@Test func failureClassifierSeparatesPermanentAndTransientSSHFailures() {
    #expect(!TunnelFailureClassifier.isRetryable(stderr: "Permission denied (publickey)."))
    #expect(!TunnelFailureClassifier.isRetryable(stderr: "bind: Address already in use"))
    #expect(!TunnelFailureClassifier.isRetryable(stderr: "Host key verification failed."))
    #expect(!TunnelFailureClassifier.isRetryable(stderr: "Could not resolve hostname typo.example"))
    #expect(TunnelFailureClassifier.isRetryable(stderr: "Connection reset by peer"))
    #expect(TunnelFailureClassifier.isRetryable(stderr: "Connection timed out"))
}

@Test func automaticRecoveryTreatsValidationTimeoutAsRetryableButOtherValidationErrorsAsPermanent() {
    #expect(TunnelFailureClassifier.isRetryable(
        validationError: .sshConfigValidationTimedOut("example", 10)
    ))
    #expect(!TunnelFailureClassifier.isRetryable(
        validationError: .sshConfigMissingForwardingDirective("example")
    ))
    #expect(!TunnelFailureClassifier.isRetryable(
        validationError: .invalidPort("localPort")
    ))
}
