import Foundation

struct TagFilterPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumPinnedCount = 3

    var schemaVersion: Int
    var pinnedTags: [String?]

    init(
        schemaVersion: Int = currentSchemaVersion,
        pinnedTags: [String?] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pinnedTags = Self.normalizedSlots(pinnedTags)
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TagFilterPreferencesError.unsupportedSchemaVersion(schemaVersion)
        }
        guard pinnedTags.count == Self.maximumPinnedCount else {
            throw TagFilterPreferencesError.invalidPinnedTags
        }
        let keys = pinnedTags.compactMap { tag -> String? in
            guard let tag else { return nil }
            let key = TagGroupSnapshot.comparisonKey(tag)
            return key.isEmpty ? nil : key
        }
        guard keys.count == Set(keys).count else {
            throw TagFilterPreferencesError.invalidPinnedTags
        }
    }

    private static func normalizedSlots(_ values: [String?]) -> [String?] {
        var slots = Array(values.prefix(maximumPinnedCount))
        slots.append(contentsOf: repeatElement(nil, count: maximumPinnedCount - slots.count))
        return slots.map { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }
}

enum TagFilterPreferencesError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidPinnedTags
}

struct TagFilterPreferencesStore {
    let settingsURL: URL

    static func defaultStore() -> Self {
        Self(
            settingsURL: AppSupportPaths.directory()
                .appending(path: "tag-filters.json")
        )
    }

    func load() throws -> TagFilterPreferences? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        let preferences = try JSONDecoder().decode(TagFilterPreferences.self, from: data)
        try preferences.validate()
        return preferences
    }

    func save(_ preferences: TagFilterPreferences) throws {
        try preferences.validate()
        let directory = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preferences).write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: settingsURL.path
        )
    }
}
