import AppKit

@MainActor
final class NotchActivationMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(onMouseEvent: @escaping @MainActor (CGPoint, NSEvent.EventType) -> Void) {
        stop()

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            Task { @MainActor in
                onMouseEvent(NSEvent.mouseLocation, event.type)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            onMouseEvent(NSEvent.mouseLocation, event.type)
            return event
        }

        onMouseEvent(NSEvent.mouseLocation, .mouseMoved)
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
