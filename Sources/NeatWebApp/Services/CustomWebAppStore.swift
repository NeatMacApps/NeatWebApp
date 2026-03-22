import Foundation

@MainActor
final class CustomWebAppStore {
    private enum Key {
        static let customApps = "NeatWebApp.CustomApps"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [WebAppDefinition] {
        guard let data = userDefaults.data(forKey: Key.customApps) else {
            return []
        }

        return (try? JSONDecoder().decode([WebAppDefinition].self, from: data)) ?? []
    }

    func save(_ apps: [WebAppDefinition]) {
        guard let data = try? JSONEncoder().encode(apps) else {
            return
        }

        userDefaults.set(data, forKey: Key.customApps)
    }
}
