import Foundation
import AppKit
import XCTest
@testable import NeatWebApp

@MainActor
final class WebAppFaviconStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testLoadsPreviouslySavedFavicon() {
        let store = WebAppFaviconStore(directoryURL: temporaryDirectoryURL)
        let image = makeImage(color: .systemGreen)

        store.save(image, for: "chatgpt")

        let loadedImage = store.load(for: "chatgpt")

        XCTAssertNotNil(loadedImage)
        XCTAssertEqual(loadedImage?.size.width, image.size.width)
        XCTAssertEqual(loadedImage?.size.height, image.size.height)
    }

    func testDeleteRemovesCachedFavicon() {
        let store = WebAppFaviconStore(directoryURL: temporaryDirectoryURL)
        store.save(makeImage(color: .systemBlue), for: "figma")

        store.delete(for: "figma")

        XCTAssertNil(store.load(for: "figma"))
        XCTAssertFalse(store.contains(appID: "figma"))
    }

    func testContainsReportsSavedFavicon() {
        let store = WebAppFaviconStore(directoryURL: temporaryDirectoryURL)
        XCTAssertFalse(store.contains(appID: "notion"))

        store.save(makeImage(color: .systemPurple), for: "notion")

        XCTAssertTrue(store.contains(appID: "notion"))
    }

    private func makeImage(color: NSColor, size: NSSize = NSSize(width: 32, height: 32)) -> NSImage {
        let image = NSImage(size: size)

        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        return image
    }
}
