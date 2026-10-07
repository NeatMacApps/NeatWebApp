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

    func ensureFaviconLoaded(for app: WebAppDefinition, refreshCachedImage: Bool = false) {
        if !refreshCachedImage {
            if faviconMemoryCache.image(for: app.id) != nil || faviconStore.contains(appID: app.id) {
                return
            }
        }

        guard refreshCachedImage || !failedFaviconAppIDs.contains(app.id) else {
            return
        }

        guard !isFaviconPrefetchSuspended || refreshCachedImage else {
            return
        }

        guard faviconLoadTasks[app.id] == nil else {
            return
        }

        faviconLoadTasks[app.id] = Task { [appID = app.id, websiteURL = app.homeURL] in
            let data = await WebAppFaviconLoader.loadFaviconData(for: websiteURL)
            guard !Task.isCancelled else {
                return
            }

            storeFaviconResponse(data, for: appID)
        }
    }

    /// 系统内存压力：丢掉可从磁盘重建的图标内存缓存；不卸网页、不杀保活运行时。
    func handleHostMemoryPressure(isCritical: Bool) {
        isFaviconPrefetchSuspended = true
        for task in faviconLoadTasks.values {
            task.cancel()
        }
        faviconLoadTasks.removeAll()
        purgeFaviconMemoryCache()
        // 仍刻意不杀任何网页应用的运行时；严重压力时只丢掉不属于任何网页应用、可重建的预热运行时。
        if isCritical {
            runtimeCoordinator.releaseStandbyRuntimeForMemoryPressure()
        }
    }

    func preloadFavicons() {
        guard !isFaviconPrefetchSuspended else {
            return
        }

        for app in apps {
            ensureFaviconLoaded(for: app, refreshCachedImage: true)
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

    func storeFaviconResponse(_ data: Data?, for appID: String) {
        defer {
            faviconLoadTasks[appID] = nil
        }

        guard let data, let image = WebAppFaviconImagePreparing.image(from: data) else {
            failedFaviconAppIDs.insert(appID)
            return
        }

        let normalizedImage = WebAppIconNormalizer.normalizedLauncherIcon(from: image) ?? image
        faviconMemoryCache.store(normalizedImage, for: appID)
        faviconStore.save(normalizedImage, for: appID)
        faviconCacheGeneration &+= 1
        failedFaviconAppIDs.remove(appID)
    }
}
