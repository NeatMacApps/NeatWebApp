import Foundation

@MainActor
final class RuntimeBookmarkClient {
    private let instanceID: UUID
    private let sourceAppID: String
    private let commandBus: RuntimeCommandBus
    private let timeout: Duration
    private var observer: NSObjectProtocol?
    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]

    init(instanceID: UUID, sourceAppID: String, commandBus: RuntimeCommandBus, timeout: Duration = .seconds(10)) {
        self.instanceID = instanceID
        self.sourceAppID = sourceAppID
        self.commandBus = commandBus
        self.timeout = timeout
        observer = commandBus.observeBookmarkResults(for: instanceID) { [weak self] result in
            guard result.instanceID == self?.instanceID else { return }
            self?.finish(appID: result.destinationAppID, succeeded: result.succeeded)
        }
    }

    func register(_ definition: WebAppDefinition) async -> Bool {
        guard pending[definition.id] == nil, observer != nil else { return false }
        return await withCheckedContinuation { continuation in
            pending[definition.id] = continuation
            deadlines[definition.id] = Task { [weak self, timeout] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                self?.finish(appID: definition.id, succeeded: false)
            }
            commandBus.send(RuntimeBookmarkRequest(
                instanceID: instanceID, sourceAppID: sourceAppID, definition: definition
            ))
        }
    }

    func stop() {
        if let observer {
            commandBus.removeObserver(observer)
            self.observer = nil
        }
        for appID in Array(pending.keys) {
            finish(appID: appID, succeeded: false)
        }
    }

    private func finish(appID: String, succeeded: Bool) {
        deadlines.removeValue(forKey: appID)?.cancel()
        pending.removeValue(forKey: appID)?.resume(returning: succeeded)
    }
}
