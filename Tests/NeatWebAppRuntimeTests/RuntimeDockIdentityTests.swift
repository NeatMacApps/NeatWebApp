import AppKit
import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class RuntimeDockIdentityTests: XCTestCase {
    func testStandbyDoesNotInstallAnIconOrPromoteItself() {
        var changed = false
        _ = RuntimeDockIdentity(setIcon: { _ in changed = true }, promoteApplication: { changed = true; return true })
        XCTAssertFalse(changed)
    }

    func testWebsiteIconIsInstalledBeforeNativePromotion() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.saveDockSource(try source(color: .red), for: "website")
        var events: [String] = []
        var icon: NSImage?
        let identity = RuntimeDockIdentity(faviconStore: fixture.store, setIcon: {
            icon = $0
            events.append("icon")
        }, promoteApplication: { events.append("regular"); return true })
        defer { identity.stop() }
        identity.update(for: definition())
        XCTAssertEqual(events, ["icon", "regular"])
        let bitmap = try bitmap(of: XCTUnwrap(icon))
        XCTAssertGreaterThan(bitmap.colorAt(x: 256, y: 256)?.redComponent ?? 0, 0.9)
    }

    func testDockSilhouetteIsRoundedRectangleNotCircleOrSquare() throws {
        let image = try XCTUnwrap(WebAppIconNormalizer.normalizedDockIcon(from: source(color: .red)))
        let pixels = try bitmap(of: image)
        XCTAssertEqual(pixels.pixelsWide, 512)
        XCTAssertEqual(pixels.pixelsHigh, 512)
        XCTAssertEqual(pixels.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(pixels.colorAt(x: 51, y: 51)?.alphaComponent, 0)
        XCTAssertGreaterThan(pixels.colorAt(x: 95, y: 95)?.alphaComponent ?? 0, 0.95)
        XCTAssertGreaterThan(pixels.colorAt(x: 256, y: 64)?.alphaComponent ?? 0, 0.95)
        XCTAssertEqual(pixels.colorAt(x: 256, y: 30)?.alphaComponent, 0)
    }

    func testTransparentSiteMarkReceivesTheSameOpaqueRoundedBacking() throws {
        let image = try source(color: .blue, transparent: true)
        let rendered = try XCTUnwrap(WebAppIconNormalizer.normalizedDockIcon(from: image))
        let pixels = try bitmap(of: rendered)
        XCTAssertGreaterThan(pixels.colorAt(x: 256, y: 64)?.alphaComponent ?? 0, 0.95)
        XCTAssertGreaterThan(pixels.colorAt(x: 256, y: 256)?.blueComponent ?? 0, 0.9)
        XCTAssertEqual(pixels.colorAt(x: 20, y: 20)?.alphaComponent, 0)
    }

    func testMissingFaviconStillUsesRoundedWebsitePlaceholderNotHostIcon() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var icon: NSImage?
        let identity = RuntimeDockIdentity(faviconStore: fixture.store, setIcon: { icon = $0 }, promoteApplication: { true })
        defer { identity.stop() }
        identity.update(for: definition())
        let pixels = try bitmap(of: XCTUnwrap(icon))
        XCTAssertEqual(pixels.pixelsWide, 512)
        XCTAssertGreaterThan(pixels.colorAt(x: 256, y: 64)?.alphaComponent ?? 0, 0.95)
        XCTAssertEqual(pixels.colorAt(x: 20, y: 20)?.alphaComponent, 0)
    }

    func testCacheRefreshChangesOnlyTheAssignedWebsiteIcon() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.saveDockSource(try source(color: .red), for: "website")
        let refreshed = expectation(description: "Assigned site icon refresh")
        var current: NSImage?
        let identity = RuntimeDockIdentity(faviconStore: fixture.store, setIcon: { image in
            current = image
            if let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let color = NSBitmapImageRep(cgImage: pixels).colorAt(x: 256, y: 256), color.blueComponent > 0.9 {
                refreshed.fulfill()
            }
        }, promoteApplication: { true })
        defer { identity.stop() }
        identity.update(for: definition())
        fixture.store.saveDockSource(try source(color: .green), for: "other")
        XCTAssertGreaterThan(try bitmap(of: XCTUnwrap(current)).colorAt(x: 256, y: 256)?.redComponent ?? 0, 0.9)
        fixture.store.saveDockSource(try source(color: .blue), for: "website")
        await fulfillment(of: [refreshed], timeout: 2)
    }

    func testSourceCachePreservesUncroppedImageAndDeleteRemovesBothVariants() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let raw = try source(color: .red)
        fixture.store.saveDockSource(raw, for: "website")
        fixture.store.save(try XCTUnwrap(WebAppIconNormalizer.normalizedLauncherIcon(from: raw)), for: "website")
        let rawPixels = try bitmap(of: XCTUnwrap(fixture.store.loadDockSource(for: "website")))
        XCTAssertGreaterThan(rawPixels.colorAt(x: 0, y: 0)?.alphaComponent ?? 0, 0.9)
        fixture.store.delete(for: "website")
        XCTAssertNil(fixture.store.loadDockSource(for: "website"))
        XCTAssertNil(fixture.store.load(for: "website"))
    }

    func testLegacyCacheIsAnOfflineFallback() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.save(try source(color: .red), for: "website")
        XCTAssertNotNil(fixture.store.loadDockSource(for: "website"))
    }

    private func definition() -> WebAppDefinition {
        WebAppDefinition(id: "website", name: "Website", homeURL: URL(fileURLWithPath: "/tmp/website"), accentColorName: "blue", shortDescription: "")
    }

    private func fixture() throws -> (store: WebAppFaviconStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DockIconTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (WebAppFaviconStore(directoryURL: directory), directory)
    }

    private func source(color: NSColor, transparent: Bool = false) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(transparent ? CGRect(x: 16, y: 16, width: 32, height: 32) : CGRect(x: 0, y: 0, width: 64, height: 64))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 64, height: 64))
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    }
}
