import AppKit
import Foundation

@MainActor
protocol RuntimeLaunching: AnyObject {
    func launch(
        _ bootstrap: RuntimeBootstrap,
        onError: @escaping @MainActor (String) -> Void
    ) throws

    func currentRuntimeBuildIdentifier() throws -> String
}

@MainActor
final class RuntimeLauncher: RuntimeLaunching {
    private let registryStore: RuntimeRegistryStore

    init(registryStore: RuntimeRegistryStore = RuntimeRegistryStore()) {
        self.registryStore = registryStore
    }

    func launch(
        _ bootstrap: RuntimeBootstrap,
        onError: @escaping @MainActor (String) -> Void
    ) throws {
        let bootstrapURL = try registryStore.saveBootstrap(bootstrap)
        let runtimeURL = try runtimeApplicationURL()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--instance-id", bootstrap.instanceID.uuidString,
            "--bootstrap-path", bootstrapURL.path,
            "--host-pid", String(ProcessInfo.processInfo.processIdentifier)
        ]

        NSWorkspace.shared.openApplication(at: runtimeURL, configuration: configuration) { _, error in
            guard let error else {
                return
            }

            Task { @MainActor in
                onError("Failed to launch \(bootstrap.definition.name): \(error.localizedDescription)")
            }
        }
    }

    func currentRuntimeBuildIdentifier() throws -> String {
        let runtimeURL = try runtimeApplicationURL()
        let executableURL = runtimeURL
            .appending(path: "Contents")
            .appending(path: "MacOS")
            .appending(path: "NeatWebAppRuntime")
        let values = try executableURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationStamp = values.contentModificationDate.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "unknown-date"
        let fileSize = values.fileSize.map(String.init) ?? "unknown-size"
        return "\(modificationStamp)-\(fileSize)"
    }

    private func runtimeApplicationURL() throws -> URL {
        let fileManager = FileManager.default
        let embeddedURL = Bundle.main.bundleURL
            .appending(path: "Contents")
            .appending(path: "Library")
            .appending(path: "LoginItems")
            .appending(path: "NeatWebAppRuntime.app")
        if fileManager.fileExists(atPath: embeddedURL.path) {
            return embeddedURL
        }

        let siblingURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appending(path: "NeatWebAppRuntime.app")
        if fileManager.fileExists(atPath: siblingURL.path) {
            return siblingURL
        }

        throw RuntimeLauncherError.runtimeBundleNotFound
    }
}

enum RuntimeLauncherError: LocalizedError {
    case runtimeBundleNotFound

    var errorDescription: String? {
        switch self {
        case .runtimeBundleNotFound:
            "NeatWebAppRuntime.app was not found inside the host app bundle."
        }
    }
}
