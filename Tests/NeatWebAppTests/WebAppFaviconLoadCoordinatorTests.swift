import AppKit
import Foundation
import XCTest
@testable import NeatWebApp

@MainActor
final class WebAppFaviconLoadCoordinatorTests: XCTestCase {
    func testTransientFailureRecoversWithoutRestartAndRepeatedDemandHonorsBackoff() async throws {
        let url = try makeURL("studio")
        var instant = ContinuousClock.now
        var attempts = 0
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(now: { instant }, loadImage: { _ in
            attempts += 1
            return attempts == 1 ? nil : self.makeImage()
        }, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }

        coordinator.request(appID: "studio", websiteURL: url)
        await waitUntil { attempts == 1 }
        for _ in 0..<10 { coordinator.request(appID: "studio", websiteURL: url) }
        instant = instant.advanced(by: .seconds(1))
        coordinator.retryDueLoads()
        await flushTasks()
        XCTAssertEqual(attempts, 1)

        instant = instant.advanced(by: .seconds(1))
        coordinator.retryDueLoads()
        await waitUntil { delivered == 1 }
        XCTAssertEqual(attempts, 2)
    }

    func testBackoffIsCappedAndFailureNeverBecomesPermanent() async throws {
        let url = try makeURL("offline")
        var instant = ContinuousClock.now
        var attempts = 0
        let coordinator = WebAppFaviconLoadCoordinator(now: { instant }, loadImage: { _ in
            attempts += 1
            return nil
        }, onImageLoaded: { _, _ in XCTFail("An unavailable image must not be delivered") })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "offline", websiteURL: url)
        await waitUntil { attempts == 1 }

        for (index, delay) in [2, 10, 60, 300, 300].enumerated() {
            instant = instant.advanced(by: .seconds(delay - 1))
            coordinator.retryDueLoads()
            await flushTasks()
            XCTAssertEqual(attempts, index + 1)
            instant = instant.advanced(by: .seconds(1))
            coordinator.retryDueLoads()
            await waitUntil { attempts == index + 2 }
        }
    }

    func testScheduledRetryRunsWithoutAnotherRequest() async throws {
        let url = try makeURL("automatic")
        var attempts = 0
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: { _ in
            attempts += 1
            return attempts == 1 ? nil : self.makeImage()
        }, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "automatic", websiteURL: url)
        await waitUntil(timeout: .seconds(5)) { delivered == 1 }
        XCTAssertEqual(attempts, 2)
    }

    func testDuplicateRequestsShareOneInFlightLoad() async throws {
        let url = try makeURL("same")
        let probe = IconLoadProbe()
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: probe.load, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }
        for _ in 0..<20 { coordinator.request(appID: "same", websiteURL: url) }
        await waitUntil { probe.calls.count == 1 }
        probe.finish(url, image: makeImage())
        await waitUntil { delivered == 1 }
        XCTAssertEqual(probe.calls, [url])
    }

    func testConcurrencyIsLimitedAndQueuedDemandPrecedesPrefetch() async throws {
        let urls = try ["first", "second", "background", "visible"].map(makeURL)
        let probe = IconLoadProbe()
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: probe.load, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "first", websiteURL: urls[0], priority: .prefetch)
        coordinator.request(appID: "second", websiteURL: urls[1], priority: .prefetch)
        coordinator.request(appID: "background", websiteURL: urls[2], priority: .prefetch)
        coordinator.request(appID: "visible", websiteURL: urls[3])
        await waitUntil { probe.calls.count == 2 }
        XCTAssertEqual(Set(probe.calls), Set(urls.prefix(2)))
        probe.finish(urls[0], image: makeImage())
        await waitUntil { probe.calls.count == 3 }
        XCTAssertEqual(probe.calls[2], urls[3])
        probe.finish(urls[1], image: makeImage())
        await waitUntil { probe.calls.count == 4 }
        XCTAssertEqual(probe.calls[3], urls[2])
        probe.finish(urls[2], image: makeImage())
        probe.finish(urls[3], image: makeImage())
        await waitUntil { delivered == 4 }
    }

    func testPressureCancelsOnlyPrefetchAndAllowsNewDemand() async throws {
        let urls = try ["background-a", "background-b", "queued", "visible", "new"].map(makeURL)
        let probe = IconLoadProbe()
        var delivered: [String] = []
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: probe.load, onImageLoaded: { id, _ in delivered.append(id) })
        defer { coordinator.cancelAll() }
        for index in 0..<3 {
            coordinator.request(appID: "background-\(index)", websiteURL: urls[index], priority: .prefetch)
        }
        coordinator.request(appID: "visible", websiteURL: urls[3])
        await waitUntil { probe.calls.count == 2 }
        coordinator.suspendPrefetch()
        await waitUntil { probe.calls.count == 3 }
        probe.finish(urls[0], image: makeImage())
        probe.finish(urls[1], image: makeImage())
        probe.finish(urls[3], image: makeImage())
        await waitUntil { delivered == ["visible"] }

        coordinator.request(appID: "suppressed", websiteURL: urls[2], priority: .prefetch)
        coordinator.request(appID: "new", websiteURL: urls[4])
        await waitUntil { probe.calls.count == 4 }
        probe.finish(urls[4], image: makeImage())
        await waitUntil { delivered.count == 2 }
        XCTAssertEqual(delivered, ["visible", "new"])
        XCTAssertFalse(probe.calls.contains(urls[2]))
    }

    func testDemandPromotesPrefetchAndRetainsRecoveryDuringPressure() async throws {
        let url = try makeURL("promoted")
        var instant = ContinuousClock.now
        var attempts = 0
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(now: { instant }, loadImage: { _ in
            attempts += 1
            return attempts == 1 ? nil : self.makeImage()
        }, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "promoted", websiteURL: url, priority: .prefetch)
        coordinator.request(appID: "promoted", websiteURL: url)
        coordinator.suspendPrefetch()
        await waitUntil { attempts == 1 }
        instant = instant.advanced(by: .seconds(2))
        coordinator.retryDueLoads()
        await waitUntil { delivered == 1 }
        XCTAssertEqual(attempts, 2)
    }

    func testFailedPrefetchIsSingleAttemptButLaterDemandCanRecover() async throws {
        let url = try makeURL("prefetch")
        var instant = ContinuousClock.now
        var attempts = 0
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(now: { instant }, loadImage: { _ in
            attempts += 1
            return attempts == 1 ? nil : self.makeImage()
        }, onImageLoaded: { _, _ in delivered += 1 })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "prefetch", websiteURL: url, priority: .prefetch)
        await waitUntil { attempts == 1 }
        instant = instant.advanced(by: .seconds(600))
        coordinator.retryDueLoads()
        await flushTasks()
        XCTAssertEqual(attempts, 1)
        coordinator.request(appID: "prefetch", websiteURL: url)
        await waitUntil { delivered == 1 }
        XCTAssertEqual(attempts, 2)
    }

    func testChangedURLRejectsLateCompletionWithoutClearingNewRequest() async throws {
        let oldURL = try makeURL("old")
        let newURL = try makeURL("new")
        let probe = IconLoadProbe()
        let newImage = makeImage()
        var delivered: [NSImage] = []
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: probe.load, onImageLoaded: { _, image in delivered.append(image) })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "app", websiteURL: oldURL)
        await waitUntil { probe.calls.count == 1 }
        coordinator.request(appID: "app", websiteURL: newURL)
        await waitUntil { probe.calls.count == 2 }
        probe.finish(oldURL, image: makeImage())
        await flushTasks()
        XCTAssertTrue(delivered.isEmpty)
        coordinator.request(appID: "app", websiteURL: newURL)
        probe.finish(newURL, image: newImage)
        await waitUntil { delivered.count == 1 }
        XCTAssertTrue(delivered.first === newImage)
        XCTAssertEqual(probe.calls.count, 2)
    }

    func testDeletionAndShutdownRejectLateImagesAndCancelRecovery() async throws {
        let urls = try ["deleted", "shutdown"].map(makeURL)
        let probe = IconLoadProbe()
        var delivered = 0
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: probe.load, onImageLoaded: { _, _ in delivered += 1 })
        coordinator.request(appID: "deleted", websiteURL: urls[0])
        coordinator.request(appID: "shutdown", websiteURL: urls[1])
        await waitUntil { probe.calls.count == 2 }
        coordinator.invalidate(appID: "deleted")
        coordinator.cancelAll()
        for url in urls { probe.finish(url, image: makeImage()) }
        coordinator.retryDueLoads()
        await flushTasks()
        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(probe.calls.count, 2)
    }

    func testFailedRefreshDoesNotReplaceAnExistingImage() async throws {
        let url = try makeURL("cached")
        let original = makeImage()
        var displayed = original
        var attempts = 0
        let coordinator = WebAppFaviconLoadCoordinator(loadImage: { _ in
            attempts += 1
            return nil
        }, onImageLoaded: { _, image in displayed = image })
        defer { coordinator.cancelAll() }
        coordinator.request(appID: "cached", websiteURL: url, priority: .prefetch)
        await waitUntil { attempts == 1 }
        XCTAssertTrue(displayed === original)
    }

    private func makeURL(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://icons.example/\(path)"))
    }

    private func makeImage() -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func flushTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class IconLoadProbe {
    var calls: [URL] = []
    private var pending: [URL: CheckedContinuation<NSImage?, Never>] = [:]

    func load(_ url: URL) async -> NSImage? {
        calls.append(url)
        return await withCheckedContinuation { pending[url] = $0 }
    }

    func finish(_ url: URL, image: NSImage?) {
        pending.removeValue(forKey: url)?.resume(returning: image)
    }
}
