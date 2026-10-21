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

    func testActiveDownloadStaysVisibleAfterNewerDownloadCompletes() throws {
        let session = try makeSession()
        let activeID = session.startDownload(filename: "large.zip")
        let completedID = session.startDownload(filename: "small.pdf")
        session.finishDownload(id: completedID, destinationURL: URL(fileURLWithPath: "/tmp/small.pdf"))

        XCTAssertEqual(session.downloadIndicatorItem?.id, activeID)
        XCTAssertEqual(session.activeDownloadCount, 1)
    }

    func testUnknownTotalAndLateProgressPreserveTruthfulStatus() throws {
        let session = try makeSession()
        let id = session.startDownload(filename: "stream.bin")
        session.updateDownload(id: id, completedBytes: 512, totalBytes: -1)
        XCTAssertNil(session.downloadItems.first?.fractionCompleted)
        XCTAssertNil(session.downloadItems.first?.totalBytes)
        XCTAssertEqual(session.downloadItems.first?.completedBytes, 512)

        session.updateDownload(id: id, completedBytes: 512, totalBytes: 1024)
        XCTAssertEqual(session.downloadItems.first?.fractionCompleted, 0.5)
        session.finishDownload(id: id, destinationURL: URL(fileURLWithPath: "/tmp/stream.bin"))
        session.updateDownload(id: id, completedBytes: 256, totalBytes: 1024)
        XCTAssertEqual(session.downloadItems.first?.phase, .completed)
        XCTAssertEqual(session.downloadItems.first?.fractionCompleted, 1)
    }

    func testFailedDownloadIgnoresQueuedProgress() throws {
        let session = try makeSession()
        let id = session.startDownload(filename: "report.pdf")
        session.failDownload(id: id, message: "Connection lost")
        session.updateDownload(id: id, completedBytes: 100, totalBytes: 1000)
        XCTAssertEqual(session.downloadItems.first?.phase, .failed)
        XCTAssertNil(session.downloadItems.first?.fractionCompleted)
        XCTAssertEqual(session.downloadItems.first?.message, "Connection lost")
    }

    func testClearFinishedBatchPreservesActiveTransferAndSavedFile() throws {
        let session = try makeSession()
        let activeID = session.startDownload(filename: "large.zip")
        let completedID = session.startDownload(filename: "report.pdf")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        try Data("keep".utf8).write(to: destination)
        session.finishDownload(id: completedID, destinationURL: destination)
        let failedID = session.startDownload(filename: "failed.bin")
        session.failDownload(id: failedID, message: "Connection lost")

        XCTAssertTrue(session.hasFinishedDownloads)
        session.clearFinishedDownloads()

        XCTAssertEqual(session.downloadItems.map(\.id), [activeID])
        XCTAssertFalse(session.hasFinishedDownloads)
        XCTAssertEqual(try Data(contentsOf: destination), Data("keep".utf8))
    }

    func testMissingCompletedFileShowsFeedbackForThatRecord() throws {
        let session = try makeSession()
        let id = session.startDownload(filename: "missing.pdf")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        session.finishDownload(id: id, destinationURL: destination)
        session.revealDownload(id: id)

        XCTAssertEqual(session.downloadItems.first?.phase, .completed)
        XCTAssertEqual(session.downloadItems.first?.destinationURL, destination)
        XCTAssertNotNil(session.downloadItems.first?.message)
    }

    private func makeSession() throws -> BrowserSession {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppDownloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporaryRoot) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NeatWebAppDownloadTests-\(UUID().uuidString)"))
        return BrowserSession(
            definition: try XCTUnwrap(WebAppDefinition.examples.first),
            preference: StoredWebAppPreference(),
            preferencesStore: WebAppPreferencesStore(userDefaults: defaults, rootDirectoryURL: temporaryRoot)
        )
    }

}
