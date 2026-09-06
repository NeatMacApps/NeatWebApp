import AppKit

@MainActor
extension WebAppWindowController {
    // MARK: - 窗口框与启动锁定

    func applyInitialFrame(
        using preference: StoredWebAppPreference,
        restoredWindowFrame: CGRect?,
        to window: NSWindow,
        preferredGeometry: ScreenNotchGeometry?
    ) {
        if let restoredWindowFrame,
           !isFillFrame(restoredWindowFrame, among: placementScreens()) {
            lockLaunchFrame(restoredWindowFrame, on: window)
            return
        }

        let availableScreens = placementScreens()
        let fallbackDisplayID = NSScreen.main?.displayID

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        lockLaunchFrame(frame, on: window)
    }

    func ensureWindowFrameIsVisible(preferredGeometry: ScreenNotchGeometry?) {
        guard let window, !shouldHoldLaunchFrame else {
            return
        }

        let availableScreens = placementScreens()
        guard !WebAppWindowPlacementResolver.isFrameVisible(window.frame, across: availableScreens) else {
            clampWindowToDockReserveIfNeeded()
            return
        }

        let transientPreference = StoredWebAppPreference(
            pageZoom: session.pageZoom,
            isPinned: session.isPinned,
            windowFrame: window.frame,
            windowPlacement: StoredWindowPlacement(frame: window.frame, display: nil)
        )
        let nextFrame = WebAppWindowPlacementResolver.resolveFrame(
            preference: transientPreference,
            preferredGeometry: preferredGeometry ?? self.preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: NSScreen.main?.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        window.setFrame(nextFrame, display: false)
    }

    func lockLaunchFrame(_ frame: CGRect, on window: NSWindow) {
        lockedLaunchFrame = frame
        shouldHoldLaunchFrame = true
        browserWindow?.ignoresDockAvoidance = true
        window.setFrame(frame, display: false)
    }

    func restoreLockedFrameIfNeeded(on window: NSWindow?) {
        guard shouldHoldLaunchFrame, let window, let lockedLaunchFrame else {
            return
        }

        if abs(window.frame.width - lockedLaunchFrame.width) > 0.5 ||
            abs(window.frame.height - lockedLaunchFrame.height) > 0.5 ||
            abs(window.frame.minX - lockedLaunchFrame.minX) > 0.5 ||
            abs(window.frame.minY - lockedLaunchFrame.minY) > 0.5 {
            window.setFrame(lockedLaunchFrame, display: false)
        }
    }

    func releaseLaunchFrameHoldIfNeeded() {
        restoreLockedFrameIfNeeded(on: window)
        guard shouldHoldLaunchFrame else {
            return
        }

        shouldHoldLaunchFrame = false
        browserWindow?.ignoresDockAvoidance = false
        clampWindowToDockReserveIfNeeded()
        persistWindowFrame()
    }

    func isFillFrame(_ frame: CGRect, among screens: [WebAppWindowPlacementScreen]) -> Bool {
        screens.contains {
            WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: $0.visibleFrame)
                || WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: $0.usableFrame)
        }
    }

    func placementScreens() -> [WebAppWindowPlacementScreen] {
        NSScreen.screens.map { WebAppWindowPlacementScreen(screen: $0, dockReserve: dockReserve) }
    }

    func clampWindowToDockReserveIfNeeded() {
        guard let window, !shouldHoldLaunchFrame else {
            return
        }

        let clamped = WebAppWindowPlacementResolver.clamp(window.frame, into: placementScreens())
        guard abs(clamped.minX - window.frame.minX) > 0.5
            || abs(clamped.minY - window.frame.minY) > 0.5
            || abs(clamped.width - window.frame.width) > 0.5
            || abs(clamped.height - window.frame.height) > 0.5 else {
            return
        }

        window.setFrame(clamped, display: window.isVisible)
        persistWindowFrame()
    }

    func persistWindowFrame() {
        guard let window, !shouldHoldLaunchFrame, !window.isZoomed else {
            return
        }

        if let screen = window.screen {
            let usableFrame = SideDockWindowAvoidance.usableFrame(
                visibleFrame: screen.visibleFrame,
                reserve: dockReserve,
                screenDisplayID: screen.displayID
            )
            if WebAppWindowPlacementResolver.isFillVisibleFrame(window.frame, visibleFrame: screen.visibleFrame)
                || WebAppWindowPlacementResolver.isFillVisibleFrame(window.frame, visibleFrame: usableFrame) {
                return
            }
        }

        session.persistWindowFrame(window.frame, on: window.screen)
    }
}
