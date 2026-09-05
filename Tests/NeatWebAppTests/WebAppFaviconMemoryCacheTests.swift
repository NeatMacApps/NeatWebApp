import AppKit
import Foundation
import XCTest
@testable import NeatWebApp

@MainActor
final class WebAppFaviconMemoryCacheTests: XCTestCase {
    func testStoreAndLoadRoundTrips() {
        let cache = WebAppFaviconMemoryCache()
        let image = makeImage(color: .systemOrange, size: NSSize(width: 64, height: 64))

        cache.store(image, for: "claude")

        XCTAssertNotNil(cache.image(for: "claude"))
    }

    func testRemoveAllClearsEntries() {
        let cache = WebAppFaviconMemoryCache()
        cache.store(makeImage(color: .systemBlue), for: "a")
        cache.store(makeImage(color: .systemRed), for: "b")

        cache.removeAll()

        XCTAssertNil(cache.image(for: "a"))
        XCTAssertNil(cache.image(for: "b"))
    }

    func testDownsampleCapsPixelDimension() throws {
        let large = makeImage(color: .systemTeal, size: NSSize(width: 1024, height: 1024))
        let tiff = try XCTUnwrap(large.tiffRepresentation)
        let data = try XCTUnwrap(
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        )

        let cgImage = try XCTUnwrap(
            WebAppFaviconImagePreparing.downsampleCGImage(data: data, maxPixelDimension: 128)
        )

        XCTAssertLessThanOrEqual(max(cgImage.width, cgImage.height), 128)
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
