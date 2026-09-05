import Dispatch
import Foundation

/// 订阅系统内存压力，只收缩可重建宿主资源，不碰网页内容与保活运行时。
///
/// 刻意不做 `@MainActor`：`DispatchSource` 的事件回调跑在专用后台队列上。
/// 若类或闭包继承主线程隔离，Swift 6 运行时会在入口做隔离断言，系统一报内存压力就整进程闪退。
final class HostMemoryPressureMonitor: @unchecked Sendable {
    private let source: DispatchSourceMemoryPressure

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.geraltgraham.NeatWebApp.memory-pressure", qos: .utility),
        onWarning: @escaping @MainActor @Sendable () -> Void,
        onCritical: @escaping @MainActor @Sendable () -> Void
    ) {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: queue
        )
        self.source = source

        // `@Sendable` 去掉从创建处继承的主线程隔离；真正改 UI / 缓存时再 hop 回主线程。
        source.setEventHandler { @Sendable in
            let event = source.data
            Task { @MainActor in
                if event.contains(.critical) {
                    onCritical()
                } else if event.contains(.warning) {
                    onWarning()
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
