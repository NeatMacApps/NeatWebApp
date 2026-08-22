import AppKit
import Foundation

@MainActor
final class RuntimeWindowCoordinator: RuntimeWindowEventSink {
    private let bootstrap: RuntimeBootstrap
    private let appModel: RuntimeAppModel
    private let registryStore: RuntimeRegistryStore
    private let appLock: RuntimeAppLock
    private let eventPublisher: RuntimeEventPublisher
    private let commandListener: RuntimeCommandListener
    private let preferencesStore = WebAppPreferencesStore()
    private var windowController: WebAppWindowController?
    private var hasPreparedTermination = false

    init(
        bootstrap: RuntimeBootstrap,
        registryStore: RuntimeRegistryStore = RuntimeRegistryStore(),
        commandBus: RuntimeCommandBus = RuntimeCommandBus()
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
    }

    func start() throws {
        registryStore.cleanupStaleStates()

        guard try appLock.acquire(appID: bootstrap.appID, instanceID: bootstrap.instanceID) else {
            throw RuntimeWindowCoordinatorError.duplicateRuntime(bootstrap.definition.name)
        }

        commandListener.start(instanceID: bootstrap.instanceID) { [weak self] command in
            self?.handle(command)
        }

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
            restoredWindowFrame: bootstrap.restoredWindowFrame,
            lockRestoredFrame: bootstrap.restoredPhase == nil && bootstrap.restoredWindowFrame != nil
        )
        windowController = controller
        restoreInitialPresentation(with: controller)
    }

    func prepareForTermination() {
        guard !hasPreparedTermination else {
            return
        }

        hasPreparedTermination = true
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
            windowController?.showAndFocus(preferredGeometry: resolvePreferredGeometry())
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

    private func resolvePreferredGeometry() -> ScreenNotchGeometry? {
        if let preferredDisplayID = bootstrap.preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return ScreenNotchGeometry(screen: screen)
        }

        return NSScreen.main.flatMap(ScreenNotchGeometry.init(screen:))
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
