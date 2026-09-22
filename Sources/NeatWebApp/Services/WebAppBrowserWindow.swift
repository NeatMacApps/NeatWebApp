import AppKit

/// 拖动和系统放大都走 `constrainFrameRect`。AppKit 负责必要的尺寸约束，
/// 用户拖出一块就允许它留在那一块；只有整扇窗和所有显示器都没交集时，
/// 才把它收回到当前显示器的可用区域（含侧边 Dock 避让）。
final class WebAppBrowserWindow: NSWindow {
    var dockReserve: SideDockScreenReserve?
    var ignoresDockAvoidance = false

    override func constrainFrameRect(_ frameRect: CGRect, to screen: NSScreen?) -> CGRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)

        // A user may intentionally park part of the window beyond an edge. Keep
        // a recovery guard only for a frame that has no display intersection at
        // all; this also gives AppKit a reachable frame after a display vanishes.
        guard !NSScreen.screens.isEmpty,
              !NSScreen.screens.contains(where: { $0.frame.intersects(constrained) }) else {
            return constrained
        }

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
