import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class BrowserDownloadStatusTests: XCTestCase {
    func testClearingCompletedDownloadRemovesOnlyStatus() {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppDownloadStatus-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppDownloadStatus-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: temporaryRoot
        )
        let definition = WebAppDefinition.examples.first { $0.id == "claude" }!
        let session = BrowserSession(
            definition: definition,
            preference: StoredWebAppPreference(),
            preferencesStore: store
        )

        let downloadID = session.startDownload(filename: "report.pdf")
        let destination = temporaryRoot.appendingPathComponent("report.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: destination.path, contents: Data("keep".utf8)))
        session.finishDownload(id: downloadID, destinationURL: destination)

        session.clearDownload(id: downloadID)

        XCTAssertTrue(session.downloadItems.isEmpty)
        XCTAssertEqual(try? Data(contentsOf: destination), Data("keep".utf8))
    }

    func testClearingRunningDownloadDoesNothing() {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppRunningDownload-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppRunningDownload-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: temporaryRoot
        )
        let definition = WebAppDefinition.examples.first { $0.id == "claude" }!
        let session = BrowserSession(
            definition: definition,
            preference: StoredWebAppPreference(),
            preferencesStore: store
        )

        let downloadID = session.startDownload(filename: "report.pdf")
        session.clearDownload(id: downloadID)

        XCTAssertEqual(session.downloadItems.map(\.id), [downloadID])
        XCTAssertEqual(session.downloadItems.first?.phase, .running)
    }
}
