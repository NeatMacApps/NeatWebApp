import Foundation

@MainActor
final class RuntimeEventPublisher {
    private let bootstrap: RuntimeBootstrap
    private let registryStore: RuntimeRegistryStore
    private let commandBus: RuntimeCommandBus
    private var nextSequence = 1

    init(
        bootstrap: RuntimeBootstrap,
        registryStore: RuntimeRegistryStore,
        commandBus: RuntimeCommandBus
    ) {
        self.bootstrap = bootstrap
        self.registryStore = registryStore
        self.commandBus = commandBus
    }

    func publish(
        eventName: RuntimeEventName,
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    ) {
        let now = Date()
        let state = RuntimeState(
            instanceID: bootstrap.instanceID,
            appID: bootstrap.appID,
            pid: ProcessInfo.processInfo.processIdentifier,
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame,
            lastUpdatedAt: now
        )

        try? registryStore.saveState(state)

        let event = RuntimeEvent(
            instanceID: bootstrap.instanceID,
            appID: bootstrap.appID,
            sequence: nextSequence,
            event: eventName,
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame,
            lastUpdatedAt: now
        )
        nextSequence += 1
        commandBus.send(event)
    }
}
