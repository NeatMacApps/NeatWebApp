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
            diagnosticsMessage = "设置开机自启失败：\(error.localizedDescription)"
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
        guard sideDockEdge != edge else {
            return
        }

        sideDockEdge = edge
        saveAppPreferences()
        syncSideDockOverlay()
    }

    func updateSideDockPlacement(
        edge: SideDockEdge,
        verticalPosition: CGFloat,
        displayID: CGDirectDisplayID?
    ) {
        sideDockEdge = edge
        sideDockVerticalPosition = min(max(verticalPosition, 0), 1)
        sideDockDisplayID = displayID
        saveAppPreferences()
        syncSideDockOverlay()
    }

    func loadAppPreferences() {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let defaultEdge = fallbackScreen.map {
            SideDockPlacementResolver.recommendedDefaultEdge(
                screenFrame: $0.frame,
                visibleFrame: $0.visibleFrame
            )
        } ?? .right
        let preferences = appPreferencesStore.load(defaultEdge: defaultEdge)
        sideDockEdge = preferences.sideDockEdge
        sideDockVerticalPosition = preferences.sideDockVerticalPosition
        sideDockDisplayID = preferences.sideDockDisplayID
        isVirtualNotchEnabled = preferences.isVirtualNotchEnabled
    }

    func saveAppPreferences() {
        appPreferencesStore.save(
            AppPreferences(
                sideDockEdge: sideDockEdge,
                sideDockVerticalPosition: sideDockVerticalPosition,
                sideDockDisplayID: sideDockDisplayID,
                isVirtualNotchEnabled: isVirtualNotchEnabled
            )
        )
    }

    func syncSideDockOverlay() {
        sideDockOverlayController.update(
            apps: collapsedWebApps,
            edge: sideDockEdge,
            verticalPosition: sideDockVerticalPosition,
            preferredDisplayID: sideDockDisplayID,
            appModel: self
        )
        publishSideDockReserve()
    }

    func publishSideDockReserve() {
        let reserve: SideDockScreenReserve?
        if collapsedWebApps.isEmpty {
            reserve = nil
        } else {
            reserve = SideDockScreenReserve(
                edge: sideDockEdge.screenReserveEdge,
                displayID: sideDockOverlayController.currentDisplayID ?? sideDockDisplayID,
                thickness: SideDockPresentationContext.Layout.thickness
            )
        }

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
