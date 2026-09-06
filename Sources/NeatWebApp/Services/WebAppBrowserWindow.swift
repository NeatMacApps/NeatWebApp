import AppKit

/// 拖动和系统放大都走 `constrainFrameRect`，在系统可用桌面之上再避开侧边 Dock。
final class WebAppBrowserWindow: NSWindow {
    var dockReserve: SideDockScreenReserve?
    var ignoresDockAvoidance = false

    override func constrainFrameRect(_ frameRect: CGRect, to screen: NSScreen?) -> CGRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard !ignoresDockAvoidance else {
            return constrained
        }

        let targetScreen = screen ?? self.screen
        let usableFrame = SideDockWindowAvoidance.usableFrame(
            visibleFrame: targetScreen?.visibleFrame ?? constrained,
            reserve: dockReserve,
            screenDisplayID: targetScreen?.displayID
        )
        return SideDockWindowAvoidance.clamp(constrained, into: usableFrame)
    }
}
