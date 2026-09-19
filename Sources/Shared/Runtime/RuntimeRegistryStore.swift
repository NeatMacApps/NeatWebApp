import AppKit
import Foundation

@MainActor
final class RuntimeRegistryStore {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func saveBootstrap(_ bootstrap: RuntimeBootstrap) throws -> URL {
        let url = try RuntimeSupportDirectory.bootstrapFileURL(
            for: bootstrap.instanceID,
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )
        let data = try encoder.encode(bootstrap)
        try data.write(to: url, options: .atomic)
        return url
    }

    func loadBootstrap(at url: URL) throws -> RuntimeBootstrap {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RuntimeBootstrap.self, from: data)
    }

    func loadBootstrap(instanceID: UUID) -> RuntimeBootstrap? {
        guard let url = try? RuntimeSupportDirectory.bootstrapFileURL(
                for: instanceID,
                rootDirectoryURL: rootDirectoryURL,
                fileManager: fileManager
              ) else {
            return nil
        }

        return try? loadBootstrap(at: url)
    }

    func removeBootstrap(instanceID: UUID) {
        guard let url = try? RuntimeSupportDirectory.bootstrapFileURL(
            for: instanceID,
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    func saveState(_ state: RuntimeState) throws {
        let url = try RuntimeSupportDirectory.stateFileURL(
            for: state.instanceID,
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func loadState(instanceID: UUID) -> RuntimeState? {
        guard let url = try? RuntimeSupportDirectory.stateFileURL(
                for: instanceID,
                rootDirectoryURL: rootDirectoryURL,
                fileManager: fileManager
              ),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode(RuntimeState.self, from: data)
    }

    func loadAllStates() -> [RuntimeState] {
        guard let directoryURL = try? RuntimeSupportDirectory.directoryURL(
                named: "RuntimeState",
                rootDirectoryURL: rootDirectoryURL,
                fileManager: fileManager
              ),
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return fileURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }

            return try? decoder.decode(RuntimeState.self, from: data)
        }
        .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    func state(forAppID appID: String) -> RuntimeState? {
        cleanupStaleStates()
        return loadAllStates().first(where: { $0.appID == appID })
    }

    func removeState(instanceID: UUID) {
        guard let url = try? RuntimeSupportDirectory.stateFileURL(
            for: instanceID,
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        ) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    func cleanupStaleStates() {
        for state in loadAllStates() where !isProcessRunning(state.pid) {
            removeState(instanceID: state.instanceID)
            releaseLockIfPresent(for: state.appID)
            removeBootstrap(instanceID: state.instanceID)
        }

        // One appID may still have multiple live instance files after a restart race.
        // Keep the newest (loadAllStates is newest-first) and drop the rest.
        var claimedAppIDs = Set<String>()
        for state in loadAllStates() {
            if claimedAppIDs.contains(state.appID) {
                if let application = NSRunningApplication(processIdentifier: state.pid),
                   application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    application.terminate()
                }
                removeState(instanceID: state.instanceID)
                removeBootstrap(instanceID: state.instanceID)
                continue
            }

            claimedAppIDs.insert(state.appID)
        }
    }

    private func isProcessRunning(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid) != nil
    }

    private func releaseLockIfPresent(for appID: String) {
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
