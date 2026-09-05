import AppKit
import Foundation

@MainActor
protocol WebAppRuntimeCoordinating {
    func open(_ definition: WebAppDefinition, preferredGeometry: ScreenNotchGeometry?)
    func focus(appID: String)
    func collapse(appID: String)
    func expand(appID: String)
    func terminate(appID: String)
    func terminateAll()
    func increaseZoom(appID: String)
    func decreaseZoom(appID: String)
    func resetZoom(appID: String)
    func reloadDefinition(_ definition: WebAppDefinition)
    func refreshRegistry()
}

@MainActor
final class WebAppRuntimeCoordinator: WebAppRuntimeCoordinating {
    private let registryStore: RuntimeRegistryStore
    private let launcher: any RuntimeLaunching
    private let commandBus: RuntimeCommandBus
    private let placeholderPresenter: any LaunchPlaceholderPresenting
    private let preferencesStore: WebAppPreferencesStore
    private let dockReserveStore: SideDockReserveStore
    private let onActiveAppIDChange: (String?) -> Void
    private let onDiagnosticMessage: (String) -> Void
    private let onRuntimeStatesChange: ([RuntimeState]) -> Void
    private let hostVersion: String
    private let runtimeBuildIdentifier: String
    private let runtimeHealthPolicy: RuntimeHealthPolicy
    private let runtimeMetricsProvider: RuntimeProcessMetricsProviding
    private let runtimeHealthMonitor: RuntimeHealthMonitor
    private var registry: [String: RuntimeState] = [:]
    private var nextSequence = 1
    private var eventObserver: NSObjectProtocol?
    private var runtimeHealthCheckTask: Task<Void, Never>?
    private var migratingAppIDs: Set<String> = []
    private var recoveringAppIDs: Set<String> = []
    private var placeholderAppIDs: Set<String> = []
    private var activeAppID: String? {
        didSet {
            guard oldValue != activeAppID else {
                return
            }

            onActiveAppIDChange(activeAppID)
        }
    }

    init(
        registryStore: RuntimeRegistryStore = RuntimeRegistryStore(),
        launcher: (any RuntimeLaunching)? = nil,
        commandBus: RuntimeCommandBus = RuntimeCommandBus(),
        placeholderPresenter: any LaunchPlaceholderPresenting = LaunchPlaceholderController(),
        preferencesStore: WebAppPreferencesStore = WebAppPreferencesStore(),
        dockReserveStore: SideDockReserveStore = SideDockReserveStore(),
        runtimeHealthPolicy: RuntimeHealthPolicy = .standard,
        runtimeMetricsProvider: RuntimeProcessMetricsProviding = DarwinRuntimeProcessMetricsProvider(),
        onActiveAppIDChange: @escaping (String?) -> Void,
        onDiagnosticMessage: @escaping (String) -> Void,
        onRuntimeStatesChange: @escaping ([RuntimeState]) -> Void = { _ in }
    ) {
        self.registryStore = registryStore
        self.launcher = launcher ?? RuntimeLauncher(registryStore: registryStore)
        self.commandBus = commandBus
        self.placeholderPresenter = placeholderPresenter
        self.preferencesStore = preferencesStore
        self.dockReserveStore = dockReserveStore
        self.runtimeHealthPolicy = runtimeHealthPolicy
        self.runtimeMetricsProvider = runtimeMetricsProvider
        self.runtimeHealthMonitor = RuntimeHealthMonitor(policy: runtimeHealthPolicy)
        self.onActiveAppIDChange = onActiveAppIDChange
        self.onDiagnosticMessage = onDiagnosticMessage
        self.onRuntimeStatesChange = onRuntimeStatesChange
        self.hostVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        self.runtimeBuildIdentifier = (try? self.launcher.currentRuntimeBuildIdentifier()) ?? hostVersion
        self.eventObserver = commandBus.observeEvents { [weak self] event in
            self?.handle(event)
        }
        refreshRegistry()
        startRuntimeHealthChecks()
    }

    func open(_ definition: WebAppDefinition, preferredGeometry: ScreenNotchGeometry?) {
        refreshRegistry()

        if placeholderAppIDs.contains(definition.id),
           registry[definition.id] == nil || registry[definition.id]?.phase == .launching {
            placeholderPresenter.orderPlaceholderFront(appID: definition.id)
            if let state = registry[definition.id] {
                focus(appID: definition.id)
            }
            return
        }

        if let state = registry[definition.id] {
            switch state.phase {
            case .collapsedToFloatingIcon:
                expand(appID: definition.id)
            case .hidden:
                sendCommand(.showWindow, state: state)
            case .launching, .windowVisible:
                placeholderPresenter.orderPlaceholderFront(appID: definition.id)
                focus(appID: definition.id)
            case .terminating:
                launchNewRuntime(
                    for: definition,
                    preferredGeometry: preferredGeometry,
                    reason: .reopenExisting,
                    showsPlaceholder: true
                )
            }
            return
        }

        launchNewRuntime(
            for: definition,
            preferredGeometry: preferredGeometry,
            reason: .openFromLauncher,
            showsPlaceholder: true
        )
    }

    func focus(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.focusWindow, state: state)
    }

    func collapse(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.collapseWindow, state: state)
    }

    func expand(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.expandWindow, state: state)
    }

    func terminate(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.terminateRuntime, state: state)
    }

    /// 收掉全部运行时。用在应用即将被更新覆盖之前：运行时是从应用包里启动的独立进程，
    /// 应用包被整体替换后它们仍会跑在旧代码上，且注册表里的状态会失效。
    /// 这里不等它们退干净——宿主马上就要退出，等不了；漏网的会在下次启动时
    /// 由 refreshRegistry 的版本迁移逻辑重启到新版本。
    func terminateAll() {
        refreshRegistry()

        for state in registry.values {
            terminateProcessIfNeeded(for: state)
        }
        placeholderPresenter.dismissAllPlaceholders()
        placeholderAppIDs.removeAll()
    }

    func increaseZoom(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.increaseZoom, state: state)
    }

    func decreaseZoom(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.decreaseZoom, state: state)
    }

    func resetZoom(appID: String) {
        guard let state = registry[appID] else {
            return
        }

        sendCommand(.resetZoom, state: state)
    }

    /// 目录里改了还在跑的网页应用时，把新定义推给对应运行时，并改掉磁盘上的 bootstrap，
    /// 避免健康重启后又回到旧首页 / 旧名字。
    func reloadDefinition(_ definition: WebAppDefinition) {
        refreshRegistry()
        guard let state = registry[definition.id] else {
            return
        }

        if let bootstrap = registryStore.loadBootstrap(instanceID: state.instanceID) {
            let updatedBootstrap = RuntimeBootstrap(
                instanceID: bootstrap.instanceID,
                appID: bootstrap.appID,
                definition: definition,
                launchReason: bootstrap.launchReason,
                preferredDisplayID: bootstrap.preferredDisplayID,
                runtimeBuildIdentifier: bootstrap.runtimeBuildIdentifier,
                restoredPhase: bootstrap.restoredPhase,
                restoredWindowFrame: bootstrap.restoredWindowFrame,
                restoredFloatingIconFrame: bootstrap.restoredFloatingIconFrame,
                createdAt: bootstrap.createdAt,
                hostVersion: bootstrap.hostVersion
            )
            try? registryStore.saveBootstrap(updatedBootstrap)
        }

        sendCommand(.reloadDefinition, state: state, definition: definition)
    }

    func refreshRegistry() {
        registryStore.cleanupStaleStates()
        registry = Dictionary(
            uniqueKeysWithValues: registryStore.loadAllStates().map { ($0.appID, $0) }
        )
        migrateOutdatedRuntimesIfNeeded()

        if let activeAppID, registry[activeAppID] == nil {
            self.activeAppID = nil
        }

        publishRuntimeStates()
    }

    private func launchNewRuntime(
        for definition: WebAppDefinition,
        preferredGeometry: ScreenNotchGeometry?,
        reason: RuntimeLaunchReason,
        showsPlaceholder: Bool
    ) {
        // 只算一次框：占位窗和运行时真窗必须套同一份，禁止两边各自再算。
        let launchFrame = resolveLaunchFrame(for: definition, preferredGeometry: preferredGeometry)

        if showsPlaceholder {
            placeholderPresenter.showPlaceholder(
                for: definition,
                frame: launchFrame
            )
            placeholderAppIDs.insert(definition.id)
        }

        let bootstrap = RuntimeBootstrap(
            instanceID: UUID(),
            appID: definition.id,
            definition: definition,
            launchReason: reason,
            preferredDisplayID: preferredGeometry?.displayID,
            runtimeBuildIdentifier: runtimeBuildIdentifier,
            restoredPhase: nil,
            restoredWindowFrame: launchFrame,
            restoredFloatingIconFrame: nil,
            createdAt: .now,
            hostVersion: hostVersion
        )

        do {
            try launcher.launch(bootstrap) { [weak self] message in
                self?.dismissLaunchPlaceholder(appID: definition.id)
                if self?.activeAppID == definition.id {
                    self?.activeAppID = nil
                }
                self?.onDiagnosticMessage(message)
            }
            activeAppID = definition.id
        } catch {
            dismissLaunchPlaceholder(appID: definition.id)
            onDiagnosticMessage(error.localizedDescription)
        }
    }

    private func migrateOutdatedRuntimesIfNeeded() {
        let outdatedRuntimes = registry.values.compactMap { state -> (RuntimeState, RuntimeBootstrap)? in
            guard let bootstrap = registryStore.loadBootstrap(instanceID: state.instanceID),
                  bootstrap.runtimeBuildIdentifier != runtimeBuildIdentifier else {
                return nil
            }

            return (state, bootstrap)
        }

        for (state, bootstrap) in outdatedRuntimes {
            guard !migratingAppIDs.contains(state.appID) else {
                continue
            }

            migratingAppIDs.insert(state.appID)
            Task { @MainActor [weak self] in
                await self?.migrateOutdatedRuntime(state: state, bootstrap: bootstrap)
            }
        }
    }

    private func migrateOutdatedRuntime(state: RuntimeState, bootstrap: RuntimeBootstrap) async {
        defer {
            migratingAppIDs.remove(state.appID)
            refreshRegistry()
        }

        await restartRuntime(state: state, bootstrap: bootstrap, diagnosticMessage: nil)
    }

    private func startRuntimeHealthChecks() {
        guard runtimeHealthPolicy.isEnabled else {
            return
        }

        runtimeHealthCheckTask?.cancel()
        let checkInterval = runtimeHealthPolicy.checkInterval
        runtimeHealthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: checkInterval)
                } catch {
                    return
                }

                self?.checkRuntimeHealth()
            }
        }
    }

    private func checkRuntimeHealth(now: Date = .now) {
        refreshRegistry()

        for state in registry.values {
            guard !migratingAppIDs.contains(state.appID),
                  !recoveringAppIDs.contains(state.appID),
                  let bootstrap = registryStore.loadBootstrap(instanceID: state.instanceID) else {
                continue
            }

            guard let metrics = runtimeMetricsProvider.metrics(for: state.pid, at: now) else {
                runtimeHealthMonitor.reset(instanceID: state.instanceID)
                continue
            }

            guard let decision = runtimeHealthMonitor.evaluate(
                state: state,
                bootstrap: bootstrap,
                metrics: metrics,
                now: now
            ) else {
                continue
            }

            recoveringAppIDs.insert(state.appID)
            Task { @MainActor [weak self] in
                await self?.recoverUnhealthyRuntime(
                    state: state,
                    bootstrap: bootstrap,
                    decision: decision
                )
            }
        }
    }

    private func recoverUnhealthyRuntime(
        state: RuntimeState,
        bootstrap: RuntimeBootstrap,
        decision: RuntimeHealthDecision
    ) async {
        defer {
            recoveringAppIDs.remove(state.appID)
            runtimeHealthMonitor.reset(instanceID: state.instanceID)
            refreshRegistry()
        }

        let message = "Restarting \(bootstrap.definition.name) runtime after sustained resource pressure: \(decision.diagnosticDescription)."
        await restartRuntime(state: state, bootstrap: bootstrap, diagnosticMessage: message)
    }

    private func restartRuntime(
        state: RuntimeState,
        bootstrap: RuntimeBootstrap,
        diagnosticMessage: String?
    ) async {
        if let diagnosticMessage {
            onDiagnosticMessage(diagnosticMessage)
        }

        terminateProcessIfNeeded(for: state)
        await waitForRuntimeShutdown(state)

        guard let restoredPhase = relaunchPhase(for: state.phase) else {
            return
        }

        let replacementBootstrap = RuntimeBootstrap(
            instanceID: UUID(),
            appID: bootstrap.appID,
            definition: bootstrap.definition,
            launchReason: .reopenExisting,
            preferredDisplayID: bootstrap.preferredDisplayID,
            runtimeBuildIdentifier: runtimeBuildIdentifier,
            restoredPhase: restoredPhase,
            restoredWindowFrame: state.windowFrame,
            restoredFloatingIconFrame: state.floatingIconFrame,
            createdAt: .now,
            hostVersion: hostVersion
        )

        do {
            try launcher.launch(replacementBootstrap) { [weak self] message in
                self?.onDiagnosticMessage(message)
            }
        } catch {
            onDiagnosticMessage(error.localizedDescription)
        }
    }

    private func terminateProcessIfNeeded(for state: RuntimeState) {
        sendCommand(.terminateRuntime, state: state)

        guard let application = NSRunningApplication(processIdentifier: state.pid) else {
            return
        }

        application.terminate()
    }

    private func waitForRuntimeShutdown(_ state: RuntimeState) async {
        for _ in 0..<20 {
            registryStore.cleanupStaleStates()

            if NSRunningApplication(processIdentifier: state.pid) == nil,
               registryStore.loadState(instanceID: state.instanceID) == nil {
                return
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        if let application = NSRunningApplication(processIdentifier: state.pid) {
            application.forceTerminate()
        }

        for _ in 0..<10 {
            registryStore.cleanupStaleStates()

            if NSRunningApplication(processIdentifier: state.pid) == nil,
               registryStore.loadState(instanceID: state.instanceID) == nil {
                return
            }

            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func relaunchPhase(for phase: RuntimePhase) -> RuntimePhase? {
        switch phase {
        case .launching, .windowVisible:
            .windowVisible
        case .collapsedToFloatingIcon:
            .collapsedToFloatingIcon
        case .hidden, .terminating:
            nil
        }
    }

    private func sendCommand(
        _ commandName: RuntimeCommandName,
        state: RuntimeState,
        definition: WebAppDefinition? = nil
    ) {
        let command = RuntimeCommand(
            instanceID: state.instanceID,
            appID: state.appID,
            sequence: nextSequence,
            command: commandName,
            definition: definition
        )
        nextSequence += 1
        commandBus.send(command)
    }

    private func handle(_ event: RuntimeEvent) {
        let state = registryStore.state(forAppID: event.appID) ?? RuntimeState(
            instanceID: event.instanceID,
            appID: event.appID,
            pid: 0,
            phase: event.phase,
            windowFrame: event.windowFrame,
            floatingIconFrame: event.floatingIconFrame,
            lastUpdatedAt: event.lastUpdatedAt
        )

        switch event.event {
        case .windowShown, .windowFocused, .windowExpanded:
            registry[event.appID] = state
            activeAppID = event.appID
            dismissLaunchPlaceholder(appID: event.appID)
        case .runtimeStarted:
            registry[event.appID] = state
            activeAppID = event.appID
        case .windowCollapsed:
            registry[event.appID] = state
            dismissLaunchPlaceholder(appID: event.appID)
            if activeAppID == event.appID {
                activeAppID = nil
            }
        case .windowHidden:
            registry[event.appID] = state
            dismissLaunchPlaceholder(appID: event.appID)
            if activeAppID == event.appID {
                activeAppID = nil
            }
        case .runtimeTerminating, .runtimeCrashed:
            registry.removeValue(forKey: event.appID)
            dismissLaunchPlaceholder(appID: event.appID)
            if activeAppID == event.appID {
                activeAppID = nil
            }
        }

        publishRuntimeStates()
    }

    private func publishRuntimeStates() {
        onRuntimeStatesChange(
            registry.values.sorted {
                if $0.lastUpdatedAt == $1.lastUpdatedAt {
                    return $0.appID < $1.appID
                }

                return $0.lastUpdatedAt < $1.lastUpdatedAt
            }
        )
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

    private func dismissLaunchPlaceholder(appID: String) {
        placeholderAppIDs.remove(appID)
        placeholderPresenter.dismissPlaceholder(appID: appID)
    }
}
