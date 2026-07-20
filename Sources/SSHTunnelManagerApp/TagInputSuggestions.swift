import Foundation
import SSHTunnelCore

struct TagInputSuggestions {
    static let maximumVisibleCount = 8

    struct Option: Equatable, Sendable {
        let tag: String
        let key: String
    }

    static func prepare(availableTags: [String]) -> [Option] {
        availableTags
            .map { Option(tag: $0, key: comparisonKey($0)) }
            .filter { !$0.key.isEmpty }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    static func matching(
        availableTags: [String],
        input: String,
        limit: Int = maximumVisibleCount
    ) -> [String] {
        matching(options: prepare(availableTags: availableTags), input: input, limit: limit)
    }

    static func matching(
        options: [Option],
        input: String,
        limit: Int = maximumVisibleCount
    ) -> [String] {
        guard limit > 0 else { return [] }
        let fragments = input.components(separatedBy: ",")
        let query = comparisonKey(fragments.last ?? "")
        let enteredCount = fragments.count { !comparisonKey($0).isEmpty }
        guard enteredCount < TunnelConfig.maximumTagCount || !query.isEmpty else { return [] }
        let selected = Set(fragments.compactMap { fragment -> String? in
            let key = comparisonKey(fragment)
            return key.isEmpty ? nil : key
        })

        var prefixMatches: [String] = []
        var otherMatches: [String] = []
        prefixMatches.reserveCapacity(limit)
        otherMatches.reserveCapacity(limit)

        for option in options {
            let key = option.key
            guard !key.isEmpty,
                  !selected.contains(key),
                  query.isEmpty || key.contains(query) else {
                continue
            }
            if query.isEmpty || key.hasPrefix(query) {
                if prefixMatches.count < limit {
                    prefixMatches.append(option.tag)
                }
                if prefixMatches.count == limit { break }
            } else if otherMatches.count < limit {
                otherMatches.append(option.tag)
            }
        }
        return Array((prefixMatches + otherMatches).prefix(limit))
    }

    static func selecting(_ tag: String, in input: String) -> String {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return input }

        let fragments = input.components(separatedBy: ",")
        let selectedBeforeCurrent = fragments.dropLast().contains { fragment in
            comparisonKey(fragment) == comparisonKey(tag)
        }
        guard !selectedBeforeCurrent else { return input }

        guard let lastComma = input.lastIndex(of: ",") else {
            return "\(tag), "
        }
        let prefix = input[...lastComma]
        return "\(prefix) \(tag), "
    }

    private static func comparisonKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

}
