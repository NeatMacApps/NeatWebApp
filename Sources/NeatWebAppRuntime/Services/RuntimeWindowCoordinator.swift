import AppKit
import Foundation

@MainActor
final class RuntimeWindowCoordinator: RuntimeWindowEventSink {
    private var bootstrap: RuntimeBootstrap
    private let appModel: RuntimeAppModel
    private let registryStore: RuntimeRegistryStore
    private let appLock: RuntimeAppLock
    private let eventPublisher: RuntimeEventPublisher
    private let commandListener: RuntimeCommandListener
    private let hostProcessID: Int32?
    private let preferencesStore = WebAppPreferencesStore()
    private let dockReserveStore = SideDockReserveStore()
    private var windowController: WebAppWindowController?
    private var hasPreparedTermination = false
    private var dockReserveObserver: NSObjectProtocol?
    private var hostLifecycleTask: Task<Void, Never>?

    init(
        bootstrap: RuntimeBootstrap,
        registryStore: RuntimeRegistryStore = RuntimeRegistryStore(),
        commandBus: RuntimeCommandBus = RuntimeCommandBus(),
        hostProcessID: Int32? = nil
    ) {
        self.bootstrap = bootstrap
        self.appModel = RuntimeAppModel(definition: bootstrap.definition)
        self.registryStore = registryStore
        self.appLock = RuntimeAppLock(registryStore: registryStore)
        self.eventPublisher = RuntimeEventPublisher(
            bootstrap: bootstrap,
            registryStore: registryStore,
            commandBus: commandBus
        )
        self.commandListener = RuntimeCommandListener(commandBus: commandBus)
        self.hostProcessID = hostProcessID
    }

    func start() throws {
        registryStore.cleanupStaleStates()

        guard try appLock.acquire(appID: bootstrap.appID, instanceID: bootstrap.instanceID) else {
            throw RuntimeWindowCoordinatorError.duplicateRuntime(bootstrap.definition.name)
        }

        commandListener.start(instanceID: bootstrap.instanceID) { [weak self] command in
            self?.handle(command)
        }
        startHostLifecycleMonitor()

        eventPublisher.publish(
            eventName: .runtimeStarted,
            phase: .launching,
            windowFrame: nil,
            floatingIconFrame: nil
        )

        let controller = WebAppWindowController(
            definition: bootstrap.definition,
            preferencesStore: preferencesStore,
            preferredGeometry: resolvePreferredGeometry(),
            eventSink: self,
            dockReserveStore: dockReserveStore,
            restoredWindowFrame: bootstrap.restoredWindowFrame,
            lockRestoredFrame: bootstrap.restoredPhase == nil && bootstrap.restoredWindowFrame != nil
        )
        windowController = controller
        dockReserveObserver = dockReserveStore.observeChanges { [weak self] in
            guard let self else {
                return
            }

            self.windowController?.applyDockReserve(self.dockReserveStore.load())
        }
        restoreInitialPresentation(with: controller)
    }

    func prepareForTermination() {
        guard !hasPreparedTermination else {
            return
        }

        hasPreparedTermination = true
        if let dockReserveObserver {
            dockReserveStore.removeObserver(dockReserveObserver)
            self.dockReserveObserver = nil
        }
        hostLifecycleTask?.cancel()
        hostLifecycleTask = nil
        commandListener.stop()
        let windowFrame = windowController?.window?.frame ?? appModel.windowFrame
        let floatingIconFrame = appModel.floatingIconFrame

        eventPublisher.publish(
            eventName: .runtimeTerminating,
            phase: .terminating,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame
        )

        appLock.release(appID: bootstrap.appID)
        registryStore.removeState(instanceID: bootstrap.instanceID)
        registryStore.removeBootstrap(instanceID: bootstrap.instanceID)
    }

    func webAppWindowDidRequestClose(_ controller: WebAppWindowController) {
        prepareForTermination()
        NSApplication.shared.terminate(nil)
    }

    func webAppWindowDidUpdate(
        appID: String,
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    ) {
        let previousPhase = appModel.phase
        appModel.update(
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame
        )

        let eventName: RuntimeEventName
        switch phase {
        case .launching:
            eventName = .runtimeStarted
        case .windowVisible:
            eventName = previousPhase == .collapsedToFloatingIcon ? .windowExpanded : .windowShown
        case .collapsedToFloatingIcon:
            eventName = .windowCollapsed
        case .hidden:
            eventName = .windowHidden
        case .terminating:
            eventName = .runtimeTerminating
        }

        eventPublisher.publish(
            eventName: eventName,
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame
        )
    }

    func webAppWindowDidFocus(appID: String, windowFrame: CGRect?) {
        appModel.update(
            phase: .windowVisible,
            windowFrame: windowFrame,
            floatingIconFrame: nil
        )

        eventPublisher.publish(
            eventName: .windowFocused,
            phase: .windowVisible,
            windowFrame: windowFrame,
            floatingIconFrame: nil
        )
    }

    private func handle(_ command: RuntimeCommand) {
        guard command.instanceID == bootstrap.instanceID else {
            return
        }

        switch command.command {
        case .showWindow, .focusWindow, .expandWindow:
            windowController?.showAndFocus(preferredGeometry: resolvePreferredGeometry())
        case .collapseWindow:
            windowController?.collapseWindow()
        case .hideWindow:
            windowController?.hideWindow()
        case .reloadDefinition:
            applyReloadedDefinition(command.definition)
        case .terminateRuntime:
            prepareForTermination()
            NSApplication.shared.terminate(nil)
        case .increaseZoom:
            windowController?.session.increaseZoom()
        case .decreaseZoom:
            windowController?.session.decreaseZoom()
        case .resetZoom:
            windowController?.session.resetZoom()
        }
    }

    private func applyReloadedDefinition(_ definition: WebAppDefinition?) {
        guard let definition, definition.id == bootstrap.appID else {
            return
        }

        bootstrap = RuntimeBootstrap(
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
        try? registryStore.saveBootstrap(bootstrap)
        appModel.applyDefinition(definition)
        windowController?.applyDefinition(definition)
    }

    private func resolvePreferredGeometry() -> ScreenNotchGeometry? {
        if let preferredDisplayID = bootstrap.preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return ScreenNotchGeometry(screen: screen)
        }

        return NSScreen.main.flatMap(ScreenNotchGeometry.init(screen:))
    }

    /// 宿主异常退出时的兜底：正常退出走宿主发来的结束命令；宿主没机会发（崩溃、被杀），
    /// 就靠启动时记下的宿主身份发现「它已经不在」，再自己收掉注册状态并退出。
    /// 身份在启动瞬间解析成对象后不再按号码重查，所以号码被系统回收给新进程也不会误伤。
    private func startHostLifecycleMonitor() {
        guard let hostProcessID,
              hostProcessID != ProcessInfo.processInfo.processIdentifier,
              let hostApplication = NSRunningApplication(processIdentifier: hostProcessID) else {
            return
        }

        hostLifecycleTask?.cancel()
        hostLifecycleTask = Task { [weak self, hostApplication] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                guard hostApplication.isTerminated else { continue }

                self?.prepareForTermination()
                NSApplication.shared.terminate(nil)
                return
            }
        }
    }

    private func restoreInitialPresentation(with controller: WebAppWindowController) {
        switch bootstrap.restoredPhase {
        case .collapsedToFloatingIcon:
            controller.restoreCollapsedWindow(
                windowFrame: bootstrap.restoredWindowFrame,
                iconFrame: bootstrap.restoredFloatingIconFrame
            )
        case .none, .launching, .windowVisible, .hidden, .terminating:
            controller.showAndFocus(preferredGeometry: resolvePreferredGeometry())
        }
    }
}

enum RuntimeWindowCoordinatorError: LocalizedError {
    case duplicateRuntime(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateRuntime(appName):
            "A runtime for \(appName) is already active."
        }
    }
}
