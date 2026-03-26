import Foundation

@MainActor
final class CustomWebAppStore {
    private enum Key {
        static let allApps = "NeatWebApp.AllApps"
        static let legacyCustomApps = "NeatWebApp.CustomApps"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [WebAppDefinition]? {
        if let data = userDefaults.data(forKey: Key.allApps),
           let apps = try? JSONDecoder().decode([WebAppDefinition].self, from: data) {
            return apps
        }
        return nil
    }
    
    func loadLegacyCustomApps() -> [WebAppDefinition] {
        guard let data = userDefaults.data(forKey: Key.legacyCustomApps) else {
            return []
        }
        return (try? JSONDecoder().decode([WebAppDefinition].self, from: data)) ?? []
    }

    func save(_ apps: [WebAppDefinition]) {
        guard let data = try? JSONEncoder().encode(apps) else {
            return
        }
        userDefaults.set(data, forKey: Key.allApps)
    }
}
