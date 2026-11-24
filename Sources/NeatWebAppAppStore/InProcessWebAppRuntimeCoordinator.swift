import AppKit
import Foundation

/// Single-process runtime coordinator for the sandboxed Mac App Store edition.
///
/// Hosts each web app's `WebAppWindowController` directly in the main process
/// while preserving per-app `WKWebsiteDataStore(forIdentifier:)`, notch launcher,
/// and floating Activity Dock collapse/expand behavior.
@MainActor
final class InProcessWebAppRuntimeCoordinator: WebAppRuntimeCoordinating, RuntimeWindowEventSink {
    private let preferencesStore: WebAppPreferencesStore
    private let dockReserveStore: SideDockReserveStore
    private let onActiveAppIDChange: (String?) -> Void
    private let onDiagnosticMessage: (String) -> Void
    private let onRuntimeStatesChange: ([RuntimeState]) -> Void
    private let onBookmarkWebApp: (WebAppDefinition) -> Bool

    private var controllers: [String: WebAppWindowController] = [:]
    private var states: [String: RuntimeState] = [:]
    private var activeAppID: String? {
        didSet {
            guard oldValue != activeAppID else {
                return
            }

            onActiveAppIDChange(activeAppID)
        }
    }
    private var lastActiveAppID: String?

    init(
        preferencesStore: WebAppPreferencesStore = WebAppPreferencesStore(),
        dockReserveStore: SideDockReserveStore = SideDockReserveStore(),
        onActiveAppIDChange: @escaping (String?) -> Void,
        onDiagnosticMessage: @escaping (String) -> Void,
        onRuntimeStatesChange: @escaping ([RuntimeState]) -> Void = { _ in },
        onBookmarkWebApp: @escaping (WebAppDefinition) -> Bool = { _ in false }
    ) {
        self.preferencesStore = preferencesStore
        self.dockReserveStore = dockReserveStore
        self.onActiveAppIDChange = onActiveAppIDChange
        self.onDiagnosticMessage = onDiagnosticMessage
        self.onRuntimeStatesChange = onRuntimeStatesChange
        self.onBookmarkWebApp = onBookmarkWebApp
        _ = self.onDiagnosticMessage
    }

    var openAppIDs: Set<String> {
        Set(controllers.keys)
    }

    func phase(for appID: String) -> RuntimePhase? {
        states[appID]?.phase
    }

    func open(_ definition: WebAppDefinition, preferredGeometry: ScreenNotchGeometry?) {
        if let existing = controllers[definition.id] {
            if states[definition.id]?.phase == .collapsedToFloatingIcon {
                expand(appID: definition.id)
            } else {
                promoteActivationPolicyIfNeeded()
                existing.showAndFocus(preferredGeometry: preferredGeometry)
            }
            return
        }

        let launchFrame = resolveLaunchFrame(for: definition, preferredGeometry: preferredGeometry)
        let controller = WebAppWindowController(
            definition: definition,
            preferencesStore: preferencesStore,
            preferredGeometry: preferredGeometry,
            eventSink: self,
            dockReserveStore: dockReserveStore,
            restoredWindowFrame: launchFrame,
            lockRestoredFrame: false
        )
        controller.session.registerBookmarkWebApp = { [weak self] newDefinition in
            self?.onBookmarkWebApp(newDefinition) ?? false
        }

        controllers[definition.id] = controller
        states[definition.id] = RuntimeState(
            instanceID: UUID(),
            appID: definition.id,
            pid: ProcessInfo.processInfo.processIdentifier,
            phase: .launching,
            windowFrame: launchFrame,
            floatingIconFrame: nil,
            lastUpdatedAt: .now
        )

        promoteActivationPolicyIfNeeded()
        controller.showAndFocus(preferredGeometry: preferredGeometry)
    }

    func focus(appID: String) {
        guard let controller = controllers[appID] else {
            return
        }

        promoteActivationPolicyIfNeeded()
        controller.showAndFocus(preferredGeometry: nil)
    }

    func collapse(appID: String) {
        controllers[appID]?.collapseWindow()
    }

    func expand(appID: String) {
        guard let controller = controllers[appID] else {
            return
        }

        promoteActivationPolicyIfNeeded()
        controller.showAndFocus(preferredGeometry: nil)
    }

    func terminate(appID: String) {
        guard let controller = controllers.removeValue(forKey: appID) else {
            return
        }

        controller.stopCoverageWatch()
        controller.stopEnvironmentObservers()
        controller.stopHoverFocusMonitoring()
        controller.persistWindowFrame()
        controller.hideFloatingIcon()
        controller.window?.delegate = nil
        controller.window?.orderOut(nil)

        states.removeValue(forKey: appID)
        if activeAppID == appID {
            activeAppID = nil
        }
        if lastActiveAppID == appID {
            lastActiveAppID = nil
        }

        publishRuntimeStates()
        demoteActivationPolicyIfNeeded()
    }

    func terminateAll() {
        for appID in Array(controllers.keys) {
            terminate(appID: appID)
        }
    }

    func increaseZoom(appID: String) {
        controllers[appID]?.session.increaseZoom()
    }

    func decreaseZoom(appID: String) {
        controllers[appID]?.session.decreaseZoom()
    }

    func resetZoom(appID: String) {
        controllers[appID]?.session.resetZoom()
    }

    func reloadDefinition(_ definition: WebAppDefinition) {
        controllers[definition.id]?.applyDefinition(definition)
    }

    func refreshRegistry() {
        publishRuntimeStates()
    }

    func prepareStandbyRuntime() {}

    func releaseStandbyRuntimeForMemoryPressure() {}

    func restoreActiveWebAppOnReopen() -> Bool {
        guard !controllers.isEmpty else {
            return false
        }

        if let activeAppID, let controller = controllers[activeAppID] {
            promoteActivationPolicyIfNeeded()
            controller.showAndFocus(preferredGeometry: nil)
            return true
        }

        if let visibleEntry = controllers.first(where: {
            $0.value.window?.isVisible == true && $0.value.window?.isMiniaturized == false
        }) {
            promoteActivationPolicyIfNeeded()
            visibleEntry.value.showAndFocus(preferredGeometry: nil)
            return true
        }

        if let lastActiveAppID, let controller = controllers[lastActiveAppID] {
            promoteActivationPolicyIfNeeded()
            controller.showAndFocus(preferredGeometry: nil)
            return true
        }

        if let fallback = sortedStates().first, let controller = controllers[fallback.appID] {
            promoteActivationPolicyIfNeeded()
            controller.showAndFocus(preferredGeometry: nil)
            return true
        }

        return false
    }

    // MARK: - RuntimeWindowEventSink

    func webAppWindowDidRequestClose(_ controller: WebAppWindowController) {
        terminate(appID: controller.session.definition.id)
    }

    func webAppWindowDidUpdate(
        appID: String,
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    ) {
        guard controllers[appID] != nil else {
            return
        }

        let existingInstanceID = states[appID]?.instanceID ?? UUID()
        states[appID] = RuntimeState(
            instanceID: existingInstanceID,
            appID: appID,
            pid: ProcessInfo.processInfo.processIdentifier,
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame,
            lastUpdatedAt: .now
        )

        switch phase {
        case .launching, .windowVisible:
            activeAppID = appID
            lastActiveAppID = appID
        case .collapsedToFloatingIcon, .hidden, .terminating:
            if activeAppID == appID {
                activeAppID = nil
            }
        }

        publishRuntimeStates()
    }

    func webAppWindowDidFocus(appID: String, windowFrame: CGRect?) {
        guard controllers[appID] != nil else {
            return
        }

        let existingInstanceID = states[appID]?.instanceID ?? UUID()
        states[appID] = RuntimeState(
            instanceID: existingInstanceID,
            appID: appID,
            pid: ProcessInfo.processInfo.processIdentifier,
            phase: .windowVisible,
            windowFrame: windowFrame,
            floatingIconFrame: nil,
            lastUpdatedAt: .now
        )
        activeAppID = appID
        lastActiveAppID = appID
        publishRuntimeStates()
    }

    // MARK: - Helpers

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func promoteActivationPolicyIfNeeded() {
        guard !isRunningUnitTests, NSApp.activationPolicy() != .regular else {
            return
        }

        _ = NSApp.setActivationPolicy(.regular)
    }

    private func demoteActivationPolicyIfNeeded() {
        guard !isRunningUnitTests, controllers.isEmpty else {
            return
        }

        let hasOtherNormalWindow = NSApp.windows.contains {
            $0.isVisible && $0.level == .normal && !($0 is WebAppBrowserWindow)
        }
        guard !hasOtherNormalWindow, NSApp.activationPolicy() != .accessory else {
            return
        }

        _ = NSApp.setActivationPolicy(.accessory)
    }

    private func sortedStates() -> [RuntimeState] {
        states.values.sorted {
            if $0.lastUpdatedAt == $1.lastUpdatedAt {
                return $0.appID < $1.appID
            }

            return $0.lastUpdatedAt < $1.lastUpdatedAt
        }
    }

    private func publishRuntimeStates() {
        onRuntimeStatesChange(sortedStates())
    }

    private func resolveLaunchFrame(
        for definition: WebAppDefinition,
        preferredGeometry: ScreenNotchGeometry?
    ) -> CGRect {
        let preference = preferencesStore.load(for: definition.id)
        let dockReserve = dockReserveStore.load()
        let availableScreens = NSScreen.screens.map {
            WebAppWindowPlacementScreen(screen: $0, dockReserve: dockReserve)
        }
        return WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: NSScreen.main?.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )
    }
}
