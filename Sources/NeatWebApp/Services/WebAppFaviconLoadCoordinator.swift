import AppKit
import Foundation

/// Schedules recoverable icon loads independently of cache and view lifetimes.
@MainActor
final class WebAppFaviconLoadCoordinator {
    enum Priority: Int {
        case prefetch
        case demand
    }

    private struct Request {
        let websiteURL: URL
        let generation = UUID()
        var priority: Priority
        var failureCount = 0
        var readyAt: ContinuousClock.Instant
    }

    private struct ActiveLoad {
        let generation: UUID
        let task: Task<Void, Never>
    }

    private static let retryDelays: [Duration] = [.seconds(2), .seconds(10), .seconds(60), .seconds(300)]
    private let maximumConcurrentLoads = 2
    private let now: () -> ContinuousClock.Instant
    private let loadImage: (URL) async -> NSImage?
    private let onImageLoaded: (String, NSImage) -> Void
    private var requests: [String: Request] = [:]
    private var activeLoads: [String: ActiveLoad] = [:]
    private var wakeTask: Task<Void, Never>?
    private var isPrefetchSuspended = false

    init(
        now: @escaping () -> ContinuousClock.Instant = { .now },
        loadImage: @escaping (URL) async -> NSImage? = { url in
            guard let data = await WebAppFaviconLoader.loadFaviconData(for: url) else { return nil }
            return WebAppFaviconImagePreparing.image(from: data)
        },
        onImageLoaded: @escaping (String, NSImage) -> Void
    ) {
        self.now = now
        self.loadImage = loadImage
        self.onImageLoaded = onImageLoaded
    }

    func request(appID: String, websiteURL: URL, priority: Priority = .demand) {
        guard priority == .demand || !isPrefetchSuspended else { return }

        if var existing = requests[appID], existing.websiteURL == websiteURL {
            // Showing an icon promotes prefetch, but never defeats an existing backoff.
            if priority.rawValue > existing.priority.rawValue {
                existing.priority = priority
                requests[appID] = existing
            }
        } else {
            requests.removeValue(forKey: appID)
            activeLoads.removeValue(forKey: appID)?.task.cancel()
            requests[appID] = Request(websiteURL: websiteURL, priority: priority, readyAt: now())
        }
        retryDueLoads()
    }

    func invalidate(appID: String) {
        requests.removeValue(forKey: appID)
        activeLoads.removeValue(forKey: appID)?.task.cancel()
        retryDueLoads()
    }

    func suspendPrefetch() {
        isPrefetchSuspended = true
        let prefetchIDs = requests.compactMap { $0.value.priority == .prefetch ? $0.key : nil }
        for appID in prefetchIDs {
            requests.removeValue(forKey: appID)
            activeLoads.removeValue(forKey: appID)?.task.cancel()
        }
        retryDueLoads()
    }

    func cancelAll() {
        wakeTask?.cancel()
        wakeTask = nil
        requests.removeAll()
        let loads = activeLoads.values
        activeLoads.removeAll()
        for load in loads {
            load.task.cancel()
        }
    }

    /// Also called on activation; elapsed backoff is honored rather than reset.
    func retryDueLoads() {
        wakeTask?.cancel()
        wakeTask = nil
        let pending = requests.filter { activeLoads[$0.key] == nil }.sorted {
            if $0.value.priority != $1.value.priority {
                return $0.value.priority.rawValue > $1.value.priority.rawValue
            }
            if $0.value.readyAt != $1.value.readyAt {
                return $0.value.readyAt < $1.value.readyAt
            }
            return $0.key < $1.key
        }
        let instant = now()
        for (appID, request) in pending where request.readyAt <= instant {
            guard activeLoads.count < maximumConcurrentLoads else { break }
            start(appID: appID, request: request)
        }

        guard activeLoads.count < maximumConcurrentLoads,
              let next = requests.filter({ activeLoads[$0.key] == nil }).values.map(\.readyAt).min()
        else { return }

        let delay = instant.duration(to: next)
        wakeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.retryDueLoads()
        }
    }

    private func start(appID: String, request: Request) {
        let task = Task { [weak self, loadImage] in
            let image = await loadImage(request.websiteURL)
            guard !Task.isCancelled else { return }
            self?.finish(appID: appID, generation: request.generation, image: image)
        }
        activeLoads[appID] = ActiveLoad(generation: request.generation, task: task)
    }

    private func finish(appID: String, generation: UUID, image: NSImage?) {
        guard var request = requests[appID], request.generation == generation,
              activeLoads[appID]?.generation == generation else { return }
        activeLoads.removeValue(forKey: appID)

        if let image {
            requests.removeValue(forKey: appID)
            onImageLoaded(appID, image)
        } else if request.priority == .demand {
            let delay = Self.retryDelays[min(request.failureCount, Self.retryDelays.count - 1)]
            request.failureCount += 1
            request.readyAt = now().advanced(by: delay)
            requests[appID] = request
            if request.failureCount == 1 {
                NSLog("Website icon unavailable for app %@; scheduled recovery", appID)
            }
        } else {
            requests.removeValue(forKey: appID)
        }
        retryDueLoads()
    }
}
