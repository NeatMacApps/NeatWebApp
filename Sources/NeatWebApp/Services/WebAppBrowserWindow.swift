import AppKit

/// 拖动和系统放大都走 `constrainFrameRect`。AppKit 负责必要的尺寸约束，
/// 用户拖出一块就允许它留在那一块；只有整扇窗和所有显示器都没交集时，
/// 才把它收回到当前显示器的可用区域（含侧边 Dock 避让）。
final class WebAppBrowserWindow: NSWindow {
    var dockReserve: SideDockScreenReserve?
    var ignoresDockAvoidance = false

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
