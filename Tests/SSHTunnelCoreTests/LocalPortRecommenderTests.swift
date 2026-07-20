import Foundation
import Testing
@testable import SSHTunnelCore

@Test func recommendsNextAvailableNonPrivilegedPort() {
    let index = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "127.0.0.1", port: 8_081),
        LocalPortEndpoint(host: "127.0.0.1", port: 8_082),
    ])

    #expect(index.firstAvailablePort(host: "127.0.0.1", startingAfter: 8_080) == 8_083)
}

@Test func recommendationWrapsAfterMaximumPort() {
    let index = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "127.0.0.1", port: 1_024),
    ])

    #expect(index.firstAvailablePort(host: "127.0.0.1", startingAfter: 65_535) == 1_025)
}

@Test func recommendationStartsAtMinimumPortWhenCurrentValueIsMissingOrInvalid() {
    let index = LocalPortOccupancyIndex(endpoints: [])

    #expect(index.firstAvailablePort(host: "127.0.0.1", startingAfter: nil) == 1_024)
    #expect(index.firstAvailablePort(host: "127.0.0.1", startingAfter: 80) == 1_024)
}

@Test func wildcardListenersConflictWithEveryAddressOnTheSamePort() {
    let wildcard = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "*", port: 8_080),
    ])
    let specific = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "127.0.0.1", port: 8_081),
    ])

    #expect(wildcard.isOccupied(host: "127.0.0.1", port: 8_080))
    #expect(specific.isOccupied(host: "0.0.0.0", port: 8_081))
}

@Test func localhostOverlapsBothLoopbackFamiliesWithoutMergingIPv4AndIPv6() {
    let localhost = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "localhost", port: 8_080),
    ])
    let ipv4 = LocalPortOccupancyIndex(endpoints: [
        LocalPortEndpoint(host: "127.0.0.1", port: 8_081),
    ])

    #expect(localhost.isOccupied(host: "127.0.0.1", port: 8_080))
    #expect(localhost.isOccupied(host: "[::1]", port: 8_080))
    #expect(!ipv4.isOccupied(host: "::1", port: 8_081))
}

@Test func recommendationDoesNotReturnTheCurrentPortAfterWrapping() {
    let currentPort = 8_080
    let endpoints: [LocalPortEndpoint] = (
        LocalPortOccupancyIndex.minimumPort...LocalPortOccupancyIndex.maximumPort
    ).compactMap {
        guard $0 != currentPort else { return nil }
        return LocalPortEndpoint(host: "*", port: $0)
    }
    let index = LocalPortOccupancyIndex(endpoints: endpoints)

    #expect(index.firstAvailablePort(host: "127.0.0.1", startingAfter: currentPort) == nil)
}

@Test func largeRecommendationIndexMeetsReleasePerformanceBudget() {
    let endpoints = (0..<20_000).map {
        LocalPortEndpoint(host: "127.0.0.1", port: LocalPortOccupancyIndex.minimumPort + $0)
    }
    var samples: [Double] = []

    for iteration in 0..<35 {
        let started = ContinuousClock.now
        let index = LocalPortOccupancyIndex(endpoints: endpoints)
        let recommendation = index.firstAvailablePort(host: "127.0.0.1", startingAfter: 65_535)
        let elapsed = started.duration(to: .now)
        #expect(recommendation == 21_024)
        if iteration >= 5 {
            samples.append(seconds(elapsed))
        }
    }

    samples.sort()
    let median = (samples[14] + samples[15]) / 2
    let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    let medianMilliseconds = String(format: "%.3f", median * 1_000)
    let p95Milliseconds = String(format: "%.3f", p95 * 1_000)
    print("local-port-index endpoints=20000 samples=30 median_ms=\(medianMilliseconds) p95_ms=\(p95Milliseconds)")
    #if !DEBUG
    #expect(p95 < 0.1, "Release P95 was \(p95) seconds")
    #endif
}

private func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
}
