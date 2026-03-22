import CoreGraphics
import Foundation

struct StoredWebAppPreference: Codable, Equatable, Sendable {
    var pageZoom: Double = 0.8
    var isPinned: Bool = false
    var windowFrame: CGRect?
}

@MainActor
final class WebAppPreferencesStore {
    private enum Key {
        static let preferences = "NeatWebApp.Preferences"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(for appID: String) -> StoredWebAppPreference {
        storage[appID] ?? StoredWebAppPreference()
    }

    func save(_ preference: StoredWebAppPreference, for appID: String) {
        var nextStorage = storage
        nextStorage[appID] = preference
        persist(nextStorage)
    }

    private var storage: [String: StoredWebAppPreference] {
        guard let data = userDefaults.data(forKey: Key.preferences) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: StoredWebAppPreference].self, from: data)) ?? [:]
    }

    private func persist(_ value: [String: StoredWebAppPreference]) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        userDefaults.set(data, forKey: Key.preferences)
    }
}
