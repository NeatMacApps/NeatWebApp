import Foundation

final class RuntimeCommandBus {
    private enum NotificationTopic {
        static let command = Notification.Name("com.geraltgraham.NeatWebApp.runtime.command")
        static let event = Notification.Name("com.geraltgraham.NeatWebApp.runtime.event")
        static let payloadKey = "payload"
    }

    private let center: DistributedNotificationCenter
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    func send(_ command: RuntimeCommand) {
        post(command, name: NotificationTopic.command, object: command.instanceID.uuidString)
    }

    func send(_ event: RuntimeEvent) {
        post(event, name: NotificationTopic.event, object: event.instanceID.uuidString)
    }

    func observeCommands(
        for instanceID: UUID,
        using handler: @escaping @MainActor (RuntimeCommand) -> Void
    ) -> NSObjectProtocol {
        observe(name: NotificationTopic.command, object: instanceID.uuidString, using: handler)
    }

    func observeEvents(
        using handler: @escaping @MainActor (RuntimeEvent) -> Void
    ) -> NSObjectProtocol {
        observe(name: NotificationTopic.event, object: nil, using: handler)
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        center.removeObserver(observer)
    }

    private func observe<Message: Decodable & Sendable>(
        name: Notification.Name,
        object: String?,
        using handler: @escaping @MainActor (Message) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: object, queue: .main) { [decoder] notification in
            guard let payload = notification.userInfo?[NotificationTopic.payloadKey] as? String,
                  let data = payload.data(using: .utf8),
                  let message = try? decoder.decode(Message.self, from: data) else {
                return
            }

            Task { @MainActor [message] in
                handler(message)
            }
        }
    }

    private func post<Message: Encodable>(_ message: Message, name: Notification.Name, object: String) {
        guard let data = try? encoder.encode(message),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }

        center.postNotificationName(
            name,
            object: object,
            userInfo: [NotificationTopic.payloadKey: payload],
            deliverImmediately: true
        )
    }
}
