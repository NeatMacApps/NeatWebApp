import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class AppModel {
    private static let launcherHideDelay: Duration = .milliseconds(800)
    private static let launcherTransitionDuration: Duration = .milliseconds(220)
    private static let virtualNotchHoverIntentDelay: Duration = .milliseconds(260)

    private(set) var apps: [WebAppDefinition] = []
    private(set) var detectedNotchScreens: [ScreenNotchGeometry] = []
    private(set) var launcherContext: LauncherPresentationContext?
    private(set) var diagnosticsMessage = "Move the mouse into the notch zone to reveal the launcher."
    private(set) var isNotchDebugOverlayVisible = false
    private(set) var isLauncherVisible = false
    private(set) var isTemporarilySuppressed = false
    private(set) var activeRuntimeAppID: String?
    private(set) var faviconImages: [String: NSImage] = [:]
    private(set) var isLaunchAtLoginEnabled = false
    /// 登录项被系统挂起的例外状态：正常开启不会出现，只有它曾被关掉过才会。
    /// 此时开关点了也不会生效，界面需要给出解释，否则表现为「怎么点都没反应」。
    private(set) var isLaunchAtLoginBlockedBySystem = false
    private(set) var sideDockEdge: SideDockEdge = .right
    private(set) var sideDockVerticalPosition = SideDockPlacementResolver.defaultVerticalPosition
    private(set) var sideDockDisplayID: CGDirectDisplayID?
    private(set) var isVirtualNotchEnabled = AppPreferencesStore.defaultVirtualNotchEnabled
    private(set) var collapsedWebApps: [WebAppDefinition] = []

    @ObservationIgnored
    private let overlayController = LauncherOverlayController()

    @ObservationIgnored
    private let notchActivationMonitor = NotchActivationMonitor()

    @ObservationIgnored
    private let notchDebugOverlayController = NotchDebugOverlayController()

    @ObservationIgnored
    private let customAppStore = CustomWebAppStore()

    @ObservationIgnored
    private let faviconStore = WebAppFaviconStore()

    @ObservationIgnored
    private let launchAtLoginService = LaunchAtLoginService()

    @ObservationIgnored
    private let appPreferencesStore = AppPreferencesStore()

    @ObservationIgnored
    private let sideDockOverlayController = SideDockOverlayController()

    @ObservationIgnored
    private lazy var runtimeCoordinator = WebAppRuntimeCoordinator(
        onActiveAppIDChange: { [weak self] appID in
            self?.activeRuntimeAppID = appID
        },
        onDiagnosticMessage: { [weak self] message in
            self?.diagnosticsMessage = message
        },
        onRuntimeStatesChange: { [weak self] states in
            self?.handleRuntimeStatesChange(states)
        }
    )

    @ObservationIgnored
    private var screenObserver: NSObjectProtocol?

    @ObservationIgnored
    private var activationObserver: NSObjectProtocol?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private var failedFaviconAppIDs: Set<String> = []

    @ObservationIgnored
    private var faviconLoadTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var hideLauncherTask: Task<Void, Never>?

    @ObservationIgnored
    private var pendingActivationTask: Task<Void, Never>?

    @ObservationIgnored
    private var pendingActivationGeometryID: String?

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        loadApps()
        restoreCachedFavicons()
        // 虚拟刘海开关会影响屏幕热区的识别结果，必须先恢复偏好再做首次识别。
        loadAppPreferences()
        refreshScreenState()
        refreshLaunchAtLoginState()
        runtimeCoordinator.refreshRegistry()
        preloadFavicons()

        notchActivationMonitor.start { [weak self] mouseLocation, eventType in
            self?.handleMouseEvent(mouseLocation, eventType)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenState()
            }
        }

        // 用户是在系统设置里放行登录项的，应用收不到任何回调；
        // 回到应用时重读一次，界面才不会一直停在「等待放行」。
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLaunchAtLoginState()
            }
        }
    }

    func refreshScreenState() {
        detectedNotchScreens = NSScreen.screens.compactMap { screen in
            if let hardwareGeometry = ScreenNotchGeometry(screen: screen) {
                return hardwareGeometry
            }

            guard isVirtualNotchEnabled else {
                return nil
            }

            return ScreenNotchGeometry.virtual(screen: screen)
        }

        // 屏幕参数变化在启动瞬间也会触发，这里只清理已经消失的热区，
        // 否则会顺手取消掉刚排上的悬停等待，指针停着不动就再也等不到展开。
        if let pendingActivationGeometryID,
           !detectedNotchScreens.contains(where: { $0.id == pendingActivationGeometryID }) {
            cancelPendingActivation()
        }

        if let launcherGeometry = launcherContext?.geometry,
           !detectedNotchScreens.contains(where: { $0.id == launcherGeometry.id }) {
            hideLauncher(immediately: true)
        }

        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)
        syncSideDockOverlay()
        diagnosticsMessage = screenDiagnosticsMessage
    }

    func toggleNotchDebugOverlay() {
        isNotchDebugOverlayVisible.toggle()
        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)
    }

    func revealLauncherManually() {
        refreshScreenState()

        guard let geometry = mainScreenPreferredGeometry else {
            diagnosticsMessage = "Manual reveal found no usable notch zone. Enable the virtual notch in Settings to use non-notched displays."
            return
        }

        showLauncher(for: geometry)
    }

    func setVirtualNotchEnabled(_ isEnabled: Bool) {
        guard isVirtualNotchEnabled != isEnabled else {
            return
        }

        isVirtualNotchEnabled = isEnabled
        saveAppPreferences()

        // 关掉虚拟刘海时，正挂在虚拟热区上的启动器必须立刻撤掉，否则会留在菜单栏上。
        if !isEnabled, launcherContext?.geometry.isVirtual == true {
            hideLauncher(immediately: true)
        }

        refreshScreenState()
    }

    func openWebApp(_ app: WebAppDefinition) {
        let preferredGeometry = launcherContext?.geometry ?? mainScreenPreferredGeometry
        hideLauncher(afterDelay: .zero)
        runtimeCoordinator.open(app, preferredGeometry: preferredGeometry)
    }

    func faviconImage(for app: WebAppDefinition) -> NSImage? {
        faviconImages[app.id]
    }

    func ensureFaviconLoaded(for app: WebAppDefinition, refreshCachedImage: Bool = false) {
        guard refreshCachedImage || faviconImages[app.id] == nil else {
            return
        }

        guard refreshCachedImage || !failedFaviconAppIDs.contains(app.id) else {
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

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(isEnabled)
        } catch {
            diagnosticsMessage = "设置开机自启失败：\(error.localizedDescription)"
        }

        refreshLaunchAtLoginState()
    }

    /// 打开系统设置的登录项页面。用户在那里放行后回到应用，状态会自动刷新。
    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    func setSideDockEdge(_ edge: SideDockEdge) {
        guard sideDockEdge != edge else {
            return
        }

        sideDockEdge = edge
        saveAppPreferences()
        syncSideDockOverlay()
    }

    func updateSideDockPlacement(
        verticalPosition: CGFloat,
        displayID: CGDirectDisplayID?
    ) {
        sideDockVerticalPosition = min(max(verticalPosition, 0), 1)
        sideDockDisplayID = displayID
        saveAppPreferences()
        syncSideDockOverlay()
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

    func dismissLauncherVoluntarily() {
        isTemporarilySuppressed = true
        cancelPendingActivation()
        hideLauncher(afterDelay: .zero)
    }

    /// 临时：事件日志，验证合成拖拽是否送达本应用。
    private func debugMouseLog(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/neatwebapp_mouse.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        try? handle.seekToEnd()
        if let data = "[\(Date().timeIntervalSince1970)] \(message)\n".data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        try? handle.close()
    }

    func hideLauncher(immediately: Bool = false) {
        if immediately {
            hideLauncherTask?.cancel()
            hideLauncherTask = nil

            guard isLauncherVisible || overlayController.frame != nil else {
                launcherContext = nil
                return
            }

            isLauncherVisible = false
            overlayController.hide()
            launcherContext = nil
            return
        }

        hideLauncher(afterDelay: Self.launcherHideDelay)
    }

    private func hideLauncher(afterDelay delay: Duration) {
        guard hideLauncherTask == nil else {
            return
        }

        guard isLauncherVisible || overlayController.frame != nil else {
            launcherContext = nil
            return
        }

        hideLauncherTask = Task {
            defer {
                hideLauncherTask = nil
            }

            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            isLauncherVisible = false

            do {
                try await Task.sleep(for: Self.launcherTransitionDuration)
            } catch {
                return
            }

            overlayController.hide()
            launcherContext = nil
        }
    }

    private func handleMouseEvent(_ mouseLocation: CGPoint, _ eventType: NSEvent.EventType) {
        let isClick = (eventType == .leftMouseDown || eventType == .rightMouseDown)
        debugMouseLog("\(eventType.rawValue) @ (\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))")
        
        let geometryForActivation = detectedNotchScreens.first(where: { $0.containsActivationPoint(mouseLocation) })
        let activationContains = geometryForActivation != nil

        if isTemporarilySuppressed {
            if !activationContains {
                isTemporarilySuppressed = false
            } else {
                return
            }
        }

        if let frame = overlayController.frame, frame.contains(mouseLocation) {
            return
        }

        if isClick,
           isLauncherVisible,
           let geometry = launcherContext?.geometry,
           geometry.containsLauncherRetentionPoint(mouseLocation) {
            dismissLauncherVoluntarily()
            return
        }

        if isLauncherVisible,
           let geometry = launcherContext?.geometry,
           geometry.containsLauncherRetentionPoint(mouseLocation) {
            showLauncher(for: geometry)
            return
        }

        if let geometry = geometryForActivation {
            requestLauncher(for: geometry, isClick: isClick)
            return
        }

        cancelPendingActivation()
        hideLauncher()
    }

    /// 硬件刘海背后没有任何系统控件，指针一进入就可以展开。
    /// 虚拟热区压在菜单栏上，必须先要求指针停留一小段时间，
    /// 否则用户只是路过去点菜单，也会被启动器抢走。
    private func requestLauncher(for geometry: ScreenNotchGeometry, isClick: Bool) {
        guard geometry.isVirtual, !isLauncherVisible else {
            cancelPendingActivation()
            showLauncher(for: geometry)
            return
        }

        // 虚拟热区上的点击一律让给菜单栏，不在这里抢焦点。
        guard !isClick else {
            cancelPendingActivation()
            return
        }

        guard pendingActivationGeometryID != geometry.id else {
            return
        }

        cancelPendingActivation()
        pendingActivationGeometryID = geometry.id
        pendingActivationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.virtualNotchHoverIntentDelay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.pendingActivationTask = nil
            self.pendingActivationGeometryID = nil

            guard geometry.containsActivationPoint(NSEvent.mouseLocation) else {
                return
            }

            self.showLauncher(for: geometry)
        }
    }

    private func cancelPendingActivation() {
        pendingActivationTask?.cancel()
        pendingActivationTask = nil
        pendingActivationGeometryID = nil
    }

    private func showLauncher(for geometry: ScreenNotchGeometry) {
        hideLauncherTask?.cancel()
        hideLauncherTask = nil
        cancelPendingActivation()

        if isLauncherVisible, launcherContext?.geometry == geometry {
            return
        }

        let context = LauncherPresentationContext(geometry: geometry, apps: apps)
        launcherContext = context
        isLauncherVisible = true
        overlayController.present(context: context, appModel: self)
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
            faviconImages.removeValue(forKey: app.id)
            failedFaviconAppIDs.remove(app.id)
            faviconStore.delete(for: app.id)
            ensureFaviconLoaded(for: updatedApp, refreshCachedImage: true)
        }

        runtimeCoordinator.refreshRegistry()
    }

    func deleteCustomApp(_ app: WebAppDefinition) {
        apps.removeAll { $0.id == app.id }
        customAppStore.save(apps)
        faviconImages.removeValue(forKey: app.id)
        failedFaviconAppIDs.remove(app.id)
        faviconStore.delete(for: app.id)
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

    private func loadApps() {
        if let storedApps = customAppStore.load() {
            apps = storedApps
        } else {
            let legacyApps = customAppStore.loadLegacyCustomApps()
            apps = WebAppDefinition.examples + legacyApps
            customAppStore.save(apps)
        }
    }

    private func loadAppPreferences() {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let defaultEdge = fallbackScreen.map {
            SideDockPlacementResolver.recommendedDefaultEdge(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        } ?? .right
        let preferences = appPreferencesStore.load(defaultEdge: defaultEdge)
        sideDockEdge = preferences.sideDockEdge
        sideDockVerticalPosition = preferences.sideDockVerticalPosition
        sideDockDisplayID = preferences.sideDockDisplayID
        isVirtualNotchEnabled = preferences.isVirtualNotchEnabled
    }

    private func saveAppPreferences() {
        appPreferencesStore.save(
            AppPreferences(
                sideDockEdge: sideDockEdge,
                sideDockVerticalPosition: sideDockVerticalPosition,
                sideDockDisplayID: sideDockDisplayID,
                isVirtualNotchEnabled: isVirtualNotchEnabled
            )
        )
    }

    private func handleRuntimeStatesChange(_ states: [RuntimeState]) {
        let collapsedAppIDs = Set(
            states.lazy
                .filter { $0.phase == .collapsedToFloatingIcon }
                .map(\.appID)
        )
        collapsedWebApps = apps.filter { collapsedAppIDs.contains($0.id) }
        syncSideDockOverlay()
    }

    private func syncSideDockOverlay() {
        sideDockOverlayController.update(
            apps: collapsedWebApps,
            edge: sideDockEdge,
            verticalPosition: sideDockVerticalPosition,
            preferredDisplayID: sideDockDisplayID,
            appModel: self
        )
    }

    private func preloadFavicons() {
        for app in apps {
            ensureFaviconLoaded(for: app, refreshCachedImage: true)
        }
    }

    private func restoreCachedFavicons() {
        for app in apps {
            guard let image = faviconStore.load(for: app.id) else {
                continue
            }

            faviconImages[app.id] = image
        }
    }

    private var screenDiagnosticsMessage: String {
        let hardwareCount = detectedNotchScreens.count(where: { !$0.isVirtual })
        let virtualCount = detectedNotchScreens.count(where: \.isVirtual)

        switch (hardwareCount, virtualCount) {
        case (0, 0):
            return isVirtualNotchEnabled
            ? "No usable notch zone was detected on any display."
            : "No notched display was detected. Enable the virtual notch in Settings to reveal the launcher on non-notched displays."
        case (let hardware, 0):
            return "Detected \(hardware) notched display(s). Hover the notch area to reveal the launcher."
        case (0, let virtual):
            return "No hardware notch was detected. \(virtual) display(s) use a virtual notch zone: rest the pointer on the top center of the screen to reveal the launcher."
        case (let hardware, let virtual):
            return "Detected \(hardware) notched display(s) and \(virtual) display(s) with a virtual notch zone at the top center."
        }
    }

    private var mainScreenPreferredGeometry: ScreenNotchGeometry? {
        guard let mainScreen = NSScreen.main else {
            return detectedNotchScreens.first
        }

        return detectedNotchScreens.first(where: { $0.screenFrame == mainScreen.frame })
        ?? detectedNotchScreens.first
    }

    private func storeFaviconResponse(_ data: Data?, for appID: String) {
        defer {
            faviconLoadTasks[appID] = nil
        }

        guard let data, let image = NSImage(data: data) else {
            failedFaviconAppIDs.insert(appID)
            return
        }

        let normalizedImage = WebAppIconNormalizer.normalizedLauncherIcon(from: image) ?? image
        faviconImages[appID] = normalizedImage
        faviconStore.save(normalizedImage, for: appID)
        failedFaviconAppIDs.remove(appID)
    }

    /// 重新读取系统侧的登录项状态。
    ///
    /// 用户是在系统设置里放行的，应用不会收到任何回调，所以每次应用重新变为活跃
    /// （打开设置窗口、点菜单栏图标）都要重读一次，否则界面会一直停在「等待放行」。
    func refreshLaunchAtLoginState() {
        isLaunchAtLoginEnabled = launchAtLoginService.isEnabled
        isLaunchAtLoginBlockedBySystem = launchAtLoginService.isBlockedBySystem
    }
}
