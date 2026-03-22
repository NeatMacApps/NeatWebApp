import AppKit

@MainActor
final class NotchActivationMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(onMouseLocationChanged: @escaping (CGPoint) -> Void) {
        stop()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            Task { @MainActor in
                onMouseLocationChanged(NSEvent.mouseLocation)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            onMouseLocationChanged(NSEvent.mouseLocation)
            return event
        }

        onMouseLocationChanged(NSEvent.mouseLocation)
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
    }
}
