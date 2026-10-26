import AppKit
import Foundation

extension AppModel {
    // MARK: - Favicon / Memory pressure

    func faviconImage(for app: WebAppDefinition) -> NSImage? {
        // 读世代字段，让 Observation 在压力丢缓存后刷新视图。
        _ = faviconCacheGeneration

        if let cached = faviconMemoryCache.image(for: app.id) {
            return cached
        }

        guard let diskImage = faviconStore.load(for: app.id) else {
            return nil
        }

        faviconMemoryCache.store(diskImage, for: app.id)
        return diskImage
    }

    func ensureFaviconLoaded(
        for app: WebAppDefinition,
        refreshCachedImage: Bool = false,
        priority: WebAppFaviconLoadCoordinator.Priority = .demand
    ) {
        // An existing but undecodable cache file is a miss, not a permanent success.
        guard refreshCachedImage || faviconImage(for: app) == nil else { return }
        faviconLoadCoordinator.request(appID: app.id, websiteURL: app.homeURL, priority: priority)
    }

    /// 系统内存压力：丢掉可从磁盘重建的图标内存缓存；不卸网页、不杀保活运行时。
    func handleHostMemoryPressure(isCritical: Bool) {
        faviconLoadCoordinator.suspendPrefetch()
        purgeFaviconMemoryCache()
        // 仍刻意不杀任何网页应用的运行时；严重压力时只丢掉不属于任何网页应用、可重建的预热运行时。
        if isCritical {
            runtimeCoordinator.releaseStandbyRuntimeForMemoryPressure()
        }
    }

    func preloadFavicons() {
        for app in apps {
            ensureFaviconLoaded(for: app, refreshCachedImage: true, priority: .prefetch)
        }
    }

    func restoreCachedFavicons() {
        for app in apps {
            guard let image = faviconStore.load(for: app.id) else {
                continue
            }

            faviconMemoryCache.store(image, for: app.id)
        }
        faviconCacheGeneration &+= 1
    }

    func purgeFaviconMemoryCache() {
        faviconMemoryCache.removeAll()
        faviconCacheGeneration &+= 1
    }

    func startMemoryPressureMonitorIfNeeded() {
        guard memoryPressureMonitor == nil else {
            return
        }

        let monitor = HostMemoryPressureMonitor(
            onWarning: { [weak self] in
                self?.handleHostMemoryPressure(isCritical: false)
            },
            onCritical: { [weak self] in
                self?.handleHostMemoryPressure(isCritical: true)
            }
        )
        memoryPressureMonitor = monitor
        monitor.start()
    }

    func storeFaviconImage(_ image: NSImage, for appID: String) {
        faviconStore.saveDockSource(image, for: appID)
        let normalizedImage = WebAppIconNormalizer.normalizedLauncherIcon(from: image) ?? image
        faviconMemoryCache.store(normalizedImage, for: appID)
        faviconStore.save(normalizedImage, for: appID)
        faviconCacheGeneration &+= 1
    }
}
