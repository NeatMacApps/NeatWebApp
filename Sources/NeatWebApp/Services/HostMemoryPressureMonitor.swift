import Dispatch
import Foundation

/// 订阅系统内存压力，只收缩可重建宿主资源，不碰网页内容与保活运行时。
@MainActor
final class HostMemoryPressureMonitor {
    private let source: DispatchSourceMemoryPressure
    private let onWarning: () -> Void
    private let onCritical: () -> Void

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.geraltgraham.NeatWebApp.memory-pressure", qos: .utility),
        onWarning: @escaping @MainActor () -> Void,
        onCritical: @escaping @MainActor () -> Void
    ) {
        self.onWarning = onWarning
        self.onCritical = onCritical
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            let event = self.source.data
            Task { @MainActor in
                if event.contains(.critical) {
                    self.onCritical()
                } else if event.contains(.warning) {
                    self.onWarning()
                }
            }
        }
    }

    func start() {
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
