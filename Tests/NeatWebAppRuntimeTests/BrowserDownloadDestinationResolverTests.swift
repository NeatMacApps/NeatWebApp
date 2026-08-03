import XCTest
@testable import NeatWebAppRuntime

final class BrowserDownloadDestinationResolverTests: XCTestCase {
    func testSanitizesDangerousSuggestedFilename() {
        XCTAssertEqual(
            BrowserDownloadDestinationResolver.sanitizedFilename(from: "../报告:最终版.pdf"),
            "报告-最终版.pdf"
        )
        XCTAssertEqual(BrowserDownloadDestinationResolver.sanitizedFilename(from: "   "), "下载文件")
        XCTAssertEqual(BrowserDownloadDestinationResolver.sanitizedFilename(from: "."), "下载文件")
    }

    func testUsesSuggestedFilenameWhenNoCollisionExists() throws {
        let directory = try makeTemporaryDirectory()
        var resolver = BrowserDownloadDestinationResolver(downloadsDirectoryURL: directory)

        let destination = resolver.reserveDestination(suggestedFilename: "report.pdf")

        XCTAssertEqual(destination.lastPathComponent, "report.pdf")
        XCTAssertEqual(destination.deletingLastPathComponent(), directory)
    }

    func testAddsNumericSuffixWhenFileAlreadyExists() throws {
        let directory = try makeTemporaryDirectory()
        _ = FileManager.default.createFile(
            atPath: directory.appendingPathComponent("report.pdf").path,
            contents: Data()
        )
        var resolver = BrowserDownloadDestinationResolver(downloadsDirectoryURL: directory)

        let destination = resolver.reserveDestination(suggestedFilename: "report.pdf")

        XCTAssertEqual(destination.lastPathComponent, "report (1).pdf")
    }

    func testReservationsPreventConcurrentDownloadsUsingSameDestination() throws {
        let directory = try makeTemporaryDirectory()
        var resolver = BrowserDownloadDestinationResolver(downloadsDirectoryURL: directory)

        let first = resolver.reserveDestination(suggestedFilename: "archive.zip")
        let second = resolver.reserveDestination(suggestedFilename: "archive.zip")

        XCTAssertEqual(first.lastPathComponent, "archive.zip")
        XCTAssertEqual(second.lastPathComponent, "archive (1).zip")
    }

    func testReleasedReservationCanBeReused() throws {
        let directory = try makeTemporaryDirectory()
        var resolver = BrowserDownloadDestinationResolver(downloadsDirectoryURL: directory)

        let first = resolver.reserveDestination(suggestedFilename: "archive.zip")
        resolver.releaseReservation(for: first)
        let second = resolver.reserveDestination(suggestedFilename: "archive.zip")

        XCTAssertEqual(first, second)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
