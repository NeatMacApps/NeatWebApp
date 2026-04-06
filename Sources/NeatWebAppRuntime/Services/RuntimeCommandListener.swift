import Foundation

@MainActor
final class RuntimeCommandListener {
    private let commandBus: RuntimeCommandBus
    private var observer: NSObjectProtocol?

    init(commandBus: RuntimeCommandBus) {
        self.commandBus = commandBus
    }

    func start(
        instanceID: UUID,
        onCommand: @escaping @MainActor (RuntimeCommand) -> Void
    ) {
        stop()
        observer = commandBus.observeCommands(for: instanceID, using: onCommand)
    }

    func stop() {
        if let observer {
            commandBus.removeObserver(observer)
            self.observer = nil
        }
    }
}
