import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class AppModel {
    private static let launcherHideDelay: Duration = .milliseconds(800)
    private static let launcherTransitionDuration: Duration = .milliseconds(220)

    private(set) var apps: [WebAppDefinition] = []
    private(set) var detectedNotchScreens: [ScreenNotchGeometry] = []
    private(set) var launcherContext: LauncherPresentationContext?
    private(set) var diagnosticsMessage = "Move the mouse into the notch zone to reveal the launcher."
    private(set) var isNotchDebugOverlayVisible = false
    private(set) var isLauncherVisible = false
    private(set) var isTemporarilySuppressed = false
    private(set) var activeBrowserSession: BrowserSession?
    private(set) var faviconImages: [String: NSImage] = [:]

    @ObservationIgnored
    private let overlayController = LauncherOverlayController()

    @ObservationIgnored
    private let notchActivationMonitor = NotchActivationMonitor()

    @ObservationIgnored
    private let notchDebugOverlayController = NotchDebugOverlayController()

    @ObservationIgnored
    private let preferencesStore = WebAppPreferencesStore()
    
    @ObservationIgnored
    private let customAppStore = CustomWebAppStore()

    @ObservationIgnored
    private let faviconStore = WebAppFaviconStore()

    @ObservationIgnored
    private lazy var windowCoordinator = WebAppWindowCoordinator(
        preferencesStore: preferencesStore
    ) { [weak self] session in
        self?.activeBrowserSession = session
    }

    @ObservationIgnored
    private var screenObserver: NSObjectProtocol?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private var failedFaviconAppIDs: Set<String> = []

    @ObservationIgnored
    private var faviconLoadTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var hideLauncherTask: Task<Void, Never>?

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        loadApps()
        restoreCachedFavicons()
        refreshScreenState()
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
    }

    func refreshScreenState() {
        detectedNotchScreens = NSScreen.screens.compactMap(ScreenNotchGeometry.init(screen:))
        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)

        diagnosticsMessage = detectedNotchScreens.isEmpty
        ? "No notched display was detected. The launcher scaffold still works, but notch-triggered reveal will stay inactive."
        : "Detected \(detectedNotchScreens.count) notched display(s). Hover the notch area to reveal the launcher."
    }

    func toggleNotchDebugOverlay() {
        isNotchDebugOverlayVisible.toggle()
        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)
    }

    func revealLauncherManually() {
        refreshScreenState()

        guard let geometry = detectedNotchScreens.first else {
            diagnosticsMessage = "Manual reveal needs a notched display, or a future fallback mode."
            return
        }

        showLauncher(for: geometry)
    }

    func openWebApp(_ app: WebAppDefinition) {
        let preferredGeometry = launcherContext?.geometry ?? defaultWebAppOpenGeometry
        hideLauncher(afterDelay: .zero)
        windowCoordinator.open(app, preferredGeometry: preferredGeometry)
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
        activeBrowserSession?.increaseZoom()
    }

    func zoomOutActiveWebApp() {
        activeBrowserSession?.decreaseZoom()
    }

    func resetZoomForActiveWebApp() {
        activeBrowserSession?.resetZoom()
    }

    func dismissLauncherVoluntarily() {
        isTemporarilySuppressed = true
        hideLauncher(afterDelay: .zero)
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
            showLauncher(for: geometry)
            return
        }

        hideLauncher()
    }

    private func showLauncher(for geometry: ScreenNotchGeometry) {
        hideLauncherTask?.cancel()
        hideLauncherTask = nil

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
    }

    func deleteCustomApp(_ app: WebAppDefinition) {
        apps.removeAll { $0.id == app.id }
        customAppStore.save(apps)
        faviconImages.removeValue(forKey: app.id)
        failedFaviconAppIDs.remove(app.id)
        faviconStore.delete(for: app.id)
    }

    func moveCustomApps(from source: IndexSet, to destination: Int) {
        apps.move(fromOffsets: source, toOffset: destination)
        customAppStore.save(apps)
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

    private var defaultWebAppOpenGeometry: ScreenNotchGeometry? {
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
}
