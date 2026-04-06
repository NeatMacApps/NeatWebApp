import Foundation
import XCTest
@testable import NeatWebApp

final class RuntimeRegistryStoreTests: XCTestCase {
    @MainActor
    func testBootstrapRoundTripsThroughRegistryStore() throws {
        let temporaryRootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: temporaryRootURL) }

        let store = RuntimeRegistryStore(rootDirectoryURL: temporaryRootURL)
        let bootstrap = RuntimeBootstrap(
            instanceID: UUID(),
            appID: "chatgpt",
            definition: WebAppDefinition(
                id: "chatgpt",
                name: "ChatGPT",
                homeURL: URL(string: "https://chatgpt.com")!,
                accentColorName: "WebAppAccentGreen",
                shortDescription: "OpenAI chat"
            ),
            launchReason: .openFromLauncher,
            preferredDisplayID: 7,
            runtimeBuildIdentifier: "2026-04-06T08:00:00Z-123456",
            restoredPhase: .collapsedToFloatingIcon,
            restoredWindowFrame: CGRect(x: 10, y: 20, width: 460, height: 900),
            restoredFloatingIconFrame: CGRect(x: 10, y: 700, width: 64, height: 64),
            createdAt: Date(timeIntervalSince1970: 1_712_345_678),
            hostVersion: "0.1.0"
        )

        let url = try store.saveBootstrap(bootstrap)
        let loaded = try store.loadBootstrap(at: url)

        XCTAssertEqual(loaded.instanceID, bootstrap.instanceID)
        XCTAssertEqual(loaded.appID, bootstrap.appID)
        XCTAssertEqual(loaded.definition, bootstrap.definition)
        XCTAssertEqual(loaded.preferredDisplayID, bootstrap.preferredDisplayID)
        XCTAssertEqual(loaded.launchReason, bootstrap.launchReason)
        XCTAssertEqual(loaded.runtimeBuildIdentifier, bootstrap.runtimeBuildIdentifier)
        XCTAssertEqual(loaded.restoredPhase, bootstrap.restoredPhase)
        XCTAssertEqual(loaded.restoredWindowFrame, bootstrap.restoredWindowFrame)
        XCTAssertEqual(loaded.restoredFloatingIconFrame, bootstrap.restoredFloatingIconFrame)
    }

    @MainActor
    func testCleanupStaleStatesRemovesStateAndLockArtifacts() throws {
        let temporaryRootURL = try makeTemporaryRootURL()
        defer { try? FileManager.default.removeItem(at: temporaryRootURL) }

        let store = RuntimeRegistryStore(rootDirectoryURL: temporaryRootURL)
        let lock = RuntimeAppLock(
            registryStore: store,
            rootDirectoryURL: temporaryRootURL
        )
        let instanceID = UUID()
        let state = RuntimeState(
            instanceID: instanceID,
            appID: "notion",
            pid: -1,
            phase: .windowVisible,
            windowFrame: CGRect(x: 0, y: 0, width: 400, height: 700),
            floatingIconFrame: nil,
            lastUpdatedAt: .now
        )

        _ = try lock.acquire(appID: state.appID, instanceID: state.instanceID)
        try store.saveState(state)
        store.cleanupStaleStates()

        XCTAssertNil(store.loadState(instanceID: instanceID))
        let lockURL = try RuntimeSupportDirectory.lockDirectoryURL(
            for: state.appID,
            rootDirectoryURL: temporaryRootURL
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))
    }

    private func makeTemporaryRootURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
