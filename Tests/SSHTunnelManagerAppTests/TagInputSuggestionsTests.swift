import Foundation
import SSHTunnelCore
import Testing
@testable import SSHTunnelManagerApp

@Suite(.serialized)
struct TagInputSuggestionsTests {
    @Test func filtersCurrentFragmentAndExcludesSelectedTags() {
        let suggestions = TagInputSuggestions.matching(
            availableTags: ["Database", "Production", "Product", "Web"],
            input: "Database, prod"
        )

        #expect(suggestions == ["Product", "Production"])
    }

    @Test func matchingIsNormalizedAndBounded() {
        let suggestions = TagInputSuggestions.matching(
            availableTags: ["Développement", "DevOps", "Device", "Other"],
            input: "DEV",
            limit: 2
        )

        #expect(suggestions == ["Développement", "Device"])
    }

    @Test func selectingReplacesOnlyTheCurrentFragment() {
        #expect(
            TagInputSuggestions.selecting("Production", in: "Database, prod")
                == "Database, Production, "
        )
        #expect(TagInputSuggestions.selecting("Web", in: "") == "Web, ")
        #expect(
            TagInputSuggestions.selecting("Production", in: "production, next")
                == "production, next"
        )
    }

    @Test func stopsAfterTheMaximumCompletedTagCount() {
        let input = (0..<10).map { "selected-\($0)" }.joined(separator: ", ") + ", "

        #expect(
            TagInputSuggestions.matching(availableTags: ["Another"], input: input).isEmpty
        )
    }

    @Test func filterIndexCountsConfigurationsAndChoosesPopularDefaults() {
        var first = TunnelConfig(name: "First", sshConfigName: "first", openURL: nil)
        first.tags = ["Production", "Database"]
        var second = TunnelConfig(name: "Second", sshConfigName: "second", openURL: nil)
        second.tags = ["production", "Web"]
        var third = TunnelConfig(name: "Third", sshConfigName: "third", openURL: nil)
        third.tags = ["Production", "Database"]

        let index = TagFilterIndex(tunnels: [first, second, third])

        #expect(index.option(matching: "PRODUCTION")?.configurationCount == 3)
        #expect(index.option(matching: "database")?.configurationCount == 2)
        #expect(index.filtering(query: "WEB").map(\.tag) == ["Web"])
        #expect(index.defaultPinnedTags == ["Production", "Database", "Web"])
    }

    @Test func filterPreferencesRoundTripWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ssh-tunnel-tag-filter-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TagFilterPreferencesStore(
            settingsURL: directory.appending(path: "tag-filters.json")
        )
        let preferences = TagFilterPreferences(
            pinnedTags: ["Production", "Database", "Web"]
        )

        try store.save(preferences)

        #expect(try store.load() == preferences)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.settingsURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func maximumTagFeaturesMeetReleasePerformanceBudgets() {
        let tags = (0..<10_000).map { String(format: "tag-%05d", $0) }
        let options = TagInputSuggestions.prepare(availableTags: tags)
        let tunnels = (0..<1_000).map { tunnelIndex -> TunnelConfig in
            var tunnel = TunnelConfig(
                name: "Tunnel \(tunnelIndex)",
                sshConfigName: "alias-\(tunnelIndex)",
                openURL: nil
            )
            tunnel.tags = (0..<10).map { "tag-\(tunnelIndex)-\($0)" }
            return tunnel
        }

        let matchingP95 = releaseP95Milliseconds {
            #expect(
                TagInputSuggestions.matching(options: options, input: "999").count
                    == TagInputSuggestions.maximumVisibleCount
            )
        }
        let preparationP95 = releaseP95Milliseconds {
            #expect(TagInputSuggestions.prepare(availableTags: tags).count == tags.count)
        }
        let indexP95 = releaseP95Milliseconds {
            #expect(TagFilterIndex(tunnels: tunnels).options.count == 10_000)
        }

        print(
            "tag-features tags=10000 samples=30"
                + " matching_p95_ms=\(matchingP95)"
                + " preparation_p95_ms=\(preparationP95)"
                + " index_p95_ms=\(indexP95)"
        )
        #if !DEBUG
        #expect(matchingP95 < 50, "Release tag matching P95 was \(matchingP95) ms")
        #expect(preparationP95 < 100, "Release tag preparation P95 was \(preparationP95) ms")
        #expect(indexP95 < 100, "Release tag filter index P95 was \(indexP95) ms")
        #endif
    }

    private func releaseP95Milliseconds(operation: () -> Void) -> Double {
        let clock = ContinuousClock()
        var samples: [Double] = []

        for iteration in 0..<35 {
            let started = clock.now
            operation()
            if iteration >= 5 {
                samples.append(milliseconds(started.duration(to: .now)))
            }
        }

        samples.sort()
        return samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
