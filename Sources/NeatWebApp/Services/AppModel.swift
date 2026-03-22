import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class AppModel {
    private(set) var apps: [WebAppDefinition] = WebAppDefinition.examples
    private(set) var detectedNotchScreens: [ScreenNotchGeometry] = []
    private(set) var launcherContext: LauncherPresentationContext?
    private(set) var diagnosticsMessage = "Move the mouse into the notch zone to reveal the launcher."
    private(set) var isNotchDebugOverlayVisible = false
    private(set) var isLauncherVisible = false
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
    private lazy var windowCoordinator = WebAppWindowCoordinator(
        preferencesStore: preferencesStore
    ) { [weak self] session in
        self?.activeBrowserSession = session
    }

    @ObservationIgnored
    private var hideWorkItem: DispatchWorkItem?

    @ObservationIgnored
    private var screenObserver: NSObjectProtocol?

    @ObservationIgnored
    private var hasStarted = false

    @ObservationIgnored
    private var failedFaviconAppIDs: Set<String> = []

    @ObservationIgnored
    private var faviconLoadTasks: [String: Task<Void, Never>] = [:]

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        refreshScreenState()
        preloadFavicons()

        notchActivationMonitor.start { [weak self] mouseLocation in
            self?.handleMouseLocationChange(mouseLocation)
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
        windowCoordinator.open(app)
        hideLauncher()
    }

    func faviconImage(for app: WebAppDefinition) -> NSImage? {
        faviconImages[app.id]
    }

    func ensureFaviconLoaded(for app: WebAppDefinition) {
        guard faviconImages[app.id] == nil else {
            return
        }

        guard !failedFaviconAppIDs.contains(app.id) else {
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

    func hideLauncher() {
        hideWorkItem?.cancel()
        overlayController.hide()
        launcherContext = nil
        isLauncherVisible = false
    }

    private func handleMouseLocationChange(_ mouseLocation: CGPoint) {
        if let frame = overlayController.frame, frame.contains(mouseLocation) {
            hideWorkItem?.cancel()
            return
        }

        guard let geometry = ScreenNotchGeometry.screen(containing: mouseLocation, within: detectedNotchScreens) else {
            scheduleHide()
            return
        }

        if geometry.activationRect.contains(mouseLocation) {
            showLauncher(for: geometry)
        } else {
            scheduleHide()
        }
    }

    private func showLauncher(for geometry: ScreenNotchGeometry) {
        hideWorkItem?.cancel()

        let context = LauncherPresentationContext(geometry: geometry, apps: apps)
        launcherContext = context
        isLauncherVisible = true
        overlayController.present(context: context, appModel: self)
    }

    private func preloadFavicons() {
        for app in apps {
            ensureFaviconLoaded(for: app)
        }
    }

    private func storeFaviconResponse(_ data: Data?, for appID: String) {
        defer {
            faviconLoadTasks[appID] = nil
        }

        guard let data, let image = NSImage(data: data) else {
            failedFaviconAppIDs.insert(appID)
            return
        }

        faviconImages[appID] = image
        failedFaviconAppIDs.remove(appID)
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideLauncher()
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }
}
