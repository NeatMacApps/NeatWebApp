import AppKit
import Foundation

extension AppModel {
    // MARK: - Preferences / Launch at login / Side dock

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        if isLaunchAtLoginBlockedBySystem, isEnabled {
            openLoginItemsSettings()
            refreshLaunchAtLoginState()
            return
        }
        switch launchAtLoginService.setEnabled(isEnabled) {
        case .success:
            break
        case .failure(let error):
            diagnosticsMessage = "Failed to set launch at login: \(error.localizedDescription)"
        }

        refreshLaunchAtLoginState()
    }

    /// 打开系统设置的登录项页面。用户在那里放行后回到应用，状态会自动刷新。
    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        isMenuBarIconVisible = visible
        UserDefaults.standard.set(visible, forKey: Self.menuBarIconVisibleKey)
    }

    func setSideDockEdge(_ edge: SideDockEdge) {
        sideDockEdge = edge
        sideDockFloatingPosition = nil
        saveAppPreferences()
        syncSideDockOverlay()
    }

    func updateSideDockPlacement(
        floatingPosition: CGPoint,
        displayID: CGDirectDisplayID?
    ) {
        sideDockFloatingPosition = floatingPosition
        sideDockDisplayID = displayID
        saveAppPreferences()
        syncSideDockOverlay()
    }

    /// Moves the Dock to the window that just collapsed and persists it like a drag result.
    func anchorSideDock(toCollapsedWindowFrame windowFrame: CGRect) {
        let screen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(windowFrame, lhs.frame) < intersectionArea(windowFrame, rhs.frame)
        } ?? NSScreen.screens.first
        guard let screen else {
            syncSideDockOverlay()
            return
        }
        let context = SideDockPresentationContext(
            apps: collapsedWebApps,
            edge: sideDockEdge,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            verticalPosition: sideDockVerticalPosition
        )
        updateSideDockPlacement(
            floatingPosition: SideDockPlacementResolver.anchoredPosition(
                windowFrame: windowFrame,
                visibleFrame: screen.visibleFrame,
                panelSize: context.layout.panelSize
            ),
            displayID: screen.displayID
        )
    }

    private func intersectionArea(_ frame: CGRect, _ screenFrame: CGRect) -> CGFloat {
        let intersection = frame.intersection(screenFrame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    func loadAppPreferences() {
        let fallbackScreen = NSScreen.screens.first
        let defaultEdge = fallbackScreen.map {
            SideDockPlacementResolver.recommendedDefaultEdge(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        } ?? .right
        let preferences = appPreferencesStore.load(defaultEdge: defaultEdge)
        sideDockEdge = preferences.sideDockEdge
        sideDockVerticalPosition = preferences.sideDockVerticalPosition
        sideDockFloatingPosition = preferences.sideDockFloatingPosition
        sideDockDisplayID = preferences.sideDockDisplayID
        isVirtualNotchEnabled = preferences.isVirtualNotchEnabled
    }

    func saveAppPreferences() {
        appPreferencesStore.save(
            AppPreferences(
                sideDockEdge: sideDockEdge,
                sideDockVerticalPosition: sideDockVerticalPosition,
                sideDockDisplayID: sideDockDisplayID,
                isVirtualNotchEnabled: isVirtualNotchEnabled,
                sideDockFloatingPosition: sideDockFloatingPosition
            )
        )
    }

    func syncSideDockOverlay() {
        sideDockOverlayController.update(
            apps: collapsedWebApps,
            edge: sideDockEdge,
            verticalPosition: sideDockVerticalPosition,
            floatingPosition: sideDockFloatingPosition,
            preferredDisplayID: sideDockDisplayID,
            appModel: self
        )
        publishSideDockReserve()
    }

    func publishSideDockReserve() {
        // Floating panels do not reserve a desktop edge. Clear older persisted reserves.
        let reserve: SideDockScreenReserve? = nil

        guard reserve != sideDockReserveStore.load() else {
            return
        }

        sideDockReserveStore.save(reserve)
    }

    /// 重新读取系统侧的登录项状态。
    ///
    /// 用户是在系统设置里放行的，应用不会收到任何回调，所以每次应用重新变为活跃
    /// （打开设置窗口、点菜单栏图标）都要重读一次，否则界面会一直停在「等待放行」。
    func refreshLaunchAtLoginState() {
        launchAtLoginService.refresh()
        isLaunchAtLoginEnabled = launchAtLoginService.isEffectivelyEnabled
        isLaunchAtLoginBlockedBySystem = launchAtLoginService.needsApproval
    }

    func restoreMenuBarIconVisibility() {
        if UserDefaults.standard.object(forKey: Self.menuBarIconVisibleKey) == nil {
            isMenuBarIconVisible = true
        } else {
            isMenuBarIconVisible = UserDefaults.standard.bool(forKey: Self.menuBarIconVisibleKey)
        }
    }
}
