import AppKit

/// 拖动和系统放大都走 `constrainFrameRect`。AppKit 负责必要的尺寸约束，
/// 用户拖出一块就允许它留在那一块；只有整扇窗和所有显示器都没交集时，
/// 才把它收回到当前显示器的可用区域（含侧边 Dock 避让）。
final class WebAppBrowserWindow: NSWindow {
    var dockReserve: SideDockScreenReserve?
    var ignoresDockAvoidance = false
    var isNativeDragging = false
    private var dragCompletionTask: Task<Void, Never>?

    override func performDrag(with event: NSEvent) {
        isNativeDragging = true
        dragCompletionTask?.cancel()
        super.performDrag(with: event)

        // Window Server may consume mouse-up, so the view cannot end this guard.
        dragCompletionTask = Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
            }
            self?.isNativeDragging = false
            self?.dragCompletionTask = nil
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // AppKit can restore a remembered display layout mid-drag. Replacing the
        // server-owned frame here breaks the pointer's original grab point.
        guard !isNativeDragging else { return }
        super.setFrame(frameRect, display: flag)
    }

    override func constrainFrameRect(_ frameRect: CGRect, to screen: NSScreen?) -> CGRect {
        // Check the proposed frame before AppKit can move its top edge or shrink
        // it to a shorter display, which changes the grab point during a drag.
        guard !NSScreen.screens.isEmpty,
              !NSScreen.screens.contains(where: { $0.frame.intersects(frameRect) }) else {
            return frameRect
        }

        // Recover a window stranded outside every display after a display change.
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard let targetScreen = screen ?? self.screen ?? NSScreen.screens.first else {
            return constrained
        }

        let usableFrame = SideDockWindowAvoidance.usableFrame(
            visibleFrame: targetScreen.visibleFrame,
            reserve: dockReserve,
            screenDisplayID: targetScreen.displayID
        )
        return SideDockWindowAvoidance.clamp(constrained, into: usableFrame)
    }
}
