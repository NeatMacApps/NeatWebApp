import Foundation

enum RuntimeSupportDirectory {
    private static let appDirectoryName = "NeatWebApp"

    static func bootstrapFileURL(
        for instanceID: UUID,
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try directoryURL(
            named: "RuntimeBootstrap",
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )
            .appending(path: "\(instanceID.uuidString).json")
    }

    static func stateFileURL(
        for instanceID: UUID,
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try directoryURL(
            named: "RuntimeState",
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )
            .appending(path: "\(instanceID.uuidString).json")
    }

    static func lockDirectoryURL(
        for appID: String,
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try directoryURL(
            named: "RuntimeLocks",
            rootDirectoryURL: rootDirectoryURL,
            fileManager: fileManager
        )
            .appending(path: "\(appID).lock", directoryHint: .isDirectory)
    }

    static func directoryURL(
        named name: String,
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let appURL: URL
        if let rootDirectoryURL {
            appURL = rootDirectoryURL.appending(path: appDirectoryName, directoryHint: .isDirectory)
        } else {
            let baseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            appURL = baseURL.appending(path: appDirectoryName, directoryHint: .isDirectory)
        }

        let directoryURL = appURL.appending(path: name, directoryHint: .isDirectory)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
