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

        if fileManager.fileExists(atPath: lockURL.path) {
            registryStore.cleanupStaleStates()

            if let activeState = registryStore.state(forAppID: appID),
               activeState.instanceID != instanceID {
                return false
            }

            try? fileManager.removeItem(at: lockURL)
        }

        try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
        return true
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
