import Foundation

extension AppModel {
    // MARK: - Web apps / Runtime

    func openWebApp(_ app: WebAppDefinition) {
        let preferredGeometry = launcherContext?.geometry ?? mainScreenPreferredGeometry
        hideLauncher(immediately: true)
        runtimeCoordinator.open(app, preferredGeometry: preferredGeometry)
    }

    func zoomInActiveWebApp() {
        guard let activeRuntimeAppID else {
            return
        }

        runtimeCoordinator.increaseZoom(appID: activeRuntimeAppID)
    }

    func zoomOutActiveWebApp() {
        guard let activeRuntimeAppID else {
            return
        }

        runtimeCoordinator.decreaseZoom(appID: activeRuntimeAppID)
    }

    func resetZoomForActiveWebApp() {
        guard let activeRuntimeAppID else {
            return
        }

        runtimeCoordinator.resetZoom(appID: activeRuntimeAppID)
    }

    func expandCollapsedWebApp(_ app: WebAppDefinition) {
        runtimeCoordinator.expand(appID: app.id)
    }

    func closeCollapsedWebApp(_ app: WebAppDefinition) {
        runtimeCoordinator.terminate(appID: app.id)
    }

    /// 应用即将被自动更新覆盖安装：先收掉所有 WebApp 运行时，
    /// 否则它们会继续跑在被替换掉的旧应用包上。
    func prepareForApplicationUpdate() {
        runtimeCoordinator.terminateAll()
    }

    func addCustomApp(_ app: WebAppDefinition) {
        apps.append(app)
        customAppStore.save(apps)
        ensureFaviconLoaded(for: app)
        runtimeCoordinator.refreshRegistry()
    }

    func updateWebApp(
        _ app: WebAppDefinition,
        name: String,
        homeURL: URL,
        accentColorName: String
    ) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else {
            return
        }

        let updatedApp = WebAppDefinition(
            id: app.id,
            name: name,
            homeURL: homeURL,
            accentColorName: accentColorName,
            shortDescription: app.shortDescription
        )

        apps[index] = updatedApp
        customAppStore.save(apps)

        // 只有网址变了才值得丢掉站点图标缓存重新抓，改名或换底色没必要。
        if app.homeURL != homeURL {
            faviconLoadTasks[app.id]?.cancel()
            faviconLoadTasks[app.id] = nil
            faviconMemoryCache.remove(for: app.id)
            failedFaviconAppIDs.remove(app.id)
            faviconStore.delete(for: app.id)
            faviconCacheGeneration &+= 1
            ensureFaviconLoaded(for: updatedApp, refreshCachedImage: true)
        }

        runtimeCoordinator.reloadDefinition(updatedApp)
        runtimeCoordinator.refreshRegistry()
    }

    func deleteCustomApp(_ app: WebAppDefinition) {
        apps.removeAll { $0.id == app.id }
        customAppStore.save(apps)
        faviconMemoryCache.remove(for: app.id)
        failedFaviconAppIDs.remove(app.id)
        faviconStore.delete(for: app.id)
        faviconCacheGeneration &+= 1
        runtimeCoordinator.refreshRegistry()
    }

    func moveCustomApps(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        customAppStore.save(apps)
        runtimeCoordinator.refreshRegistry()
    }

    /// 用启动器拖动排好的整份顺序覆盖应用顺序并持久化。
    /// 只接受与当前列表同源（同集合同数量）的顺序，避免把启动器
    /// 快照里已不存在的应用写回去，或覆盖掉并发的增删。
    func applyAppOrder(_ orderedApps: [WebAppDefinition]) {
        guard orderedApps.map(\.id) != apps.map(\.id),
              Set(orderedApps.map(\.id)) == Set(apps.map(\.id)) else {
            return
        }

        apps = orderedApps
        customAppStore.save(apps)
        runtimeCoordinator.refreshRegistry()
    }

    func loadApps() {
        if let storedApps = customAppStore.load() {
            apps = storedApps
        } else {
            let legacyApps = customAppStore.loadLegacyCustomApps()
            apps = WebAppDefinition.examples + legacyApps
            customAppStore.save(apps)
        }
    }

    func handleRuntimeStatesChange(_ states: [RuntimeState]) {
        let collapsedAppIDs = Set(
            states.lazy
                .filter { $0.phase == .collapsedToFloatingIcon }
                .map(\.appID)
        )
        collapsedWebApps = apps.filter { collapsedAppIDs.contains($0.id) }
        syncSideDockOverlay()
    }
}
