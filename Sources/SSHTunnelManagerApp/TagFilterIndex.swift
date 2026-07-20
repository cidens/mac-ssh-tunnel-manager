import Foundation
import SSHTunnelCore

struct TagFilterIndex: Equatable, Sendable {
    struct Option: Equatable, Sendable, Identifiable {
        let tag: String
        let key: String
        let configurationCount: Int

        var id: String { key }
    }

    let options: [Option]

    init(tunnels: [TunnelConfig]) {
        var values: [String: (tag: String, count: Int)] = [:]
        values.reserveCapacity(
            min(tunnels.count * TunnelConfig.maximumTagCount, 10_000)
        )
        for tunnel in tunnels {
            var countedKeys = Set<String>()
            countedKeys.reserveCapacity(tunnel.tags.count)
            for tag in tunnel.tags {
                let key = TagGroupSnapshot.comparisonKey(tag)
                guard !key.isEmpty, countedKeys.insert(key).inserted else { continue }
                if let existing = values[key] {
                    values[key] = (existing.tag, existing.count + 1)
                } else {
                    values[key] = (tag, 1)
                }
            }
        }

        options = values.map { key, value in
            Option(tag: value.tag, key: key, configurationCount: value.count)
        }
        .sorted { $0.key < $1.key }
    }

    var defaultPinnedTags: [String] {
        options
            .sorted {
                if $0.configurationCount != $1.configurationCount {
                    return $0.configurationCount > $1.configurationCount
                }
                return $0.tag.localizedStandardCompare($1.tag) == .orderedAscending
            }
            .prefix(TagFilterPreferences.maximumPinnedCount)
            .map(\.tag)
    }

    func filtering(query: String) -> [Option] {
        let key = TagGroupSnapshot.comparisonKey(query)
        guard !key.isEmpty else { return options }
        return options.filter { $0.key.contains(key) }
    }

    func option(matching tag: String?) -> Option? {
        guard let tag else { return nil }
        let key = TagGroupSnapshot.comparisonKey(tag)
        return options.first { $0.key == key }
    }
}
