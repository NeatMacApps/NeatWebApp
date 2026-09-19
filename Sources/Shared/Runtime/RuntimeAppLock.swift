import Foundation

@MainActor
final class RuntimeAppLock {
    private let registryStore: RuntimeRegistryStore
    private let fileManager: FileManager
    private let rootDirectoryURL: URL?

    init(
        registryStore: RuntimeRegistryStore,
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.registryStore = registryStore
        self.rootDirectoryURL = rootDirectoryURL
        self.fileManager = fileManager
    }

    func acquire(appID: String, instanceID: UUID) throws -> Bool {
        let lockURL = try RuntimeSupportDirectory.lockDirectoryURL(
            for: appID,
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )

        // Always consult live registry state — not only when a lock directory exists.
        // A missing lock with a still-running instance used to let a second runtime start,
        // which then crashed the host on Dictionary(uniqueKeysWithValues:).
        registryStore.cleanupStaleStates()

        if let activeState = registryStore.state(forAppID: appID),
           activeState.instanceID != instanceID {
            return false
        }

        if fileManager.fileExists(atPath: lockURL.path) {
            try? fileManager.removeItem(at: lockURL)
        }

        do {
            try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
            return true
        } catch {
            // Lost the mkdir race to another launcher for the same appID.
            if fileManager.fileExists(atPath: lockURL.path) {
                return false
            }
            throw error
        }
    }

    func release(appID: String) {
        guard let lockURL = try? RuntimeSupportDirectory.lockDirectoryURL(
                for: appID,
                rootDirectoryURL: rootDirectoryURL,
                fileManager: fileManager
              ),
              fileManager.fileExists(atPath: lockURL.path) else {
            return
        }

        try? fileManager.removeItem(at: lockURL)
    }
}
