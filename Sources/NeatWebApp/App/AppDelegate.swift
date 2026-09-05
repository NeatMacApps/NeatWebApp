import AppKit
import MacKitCore
import MacKitLifecycle

extension Notification.Name {
    /// 图标隐藏后或再次打开时，要求把主窗口带到前台。
    static let neatWebAppOpenMainWindow = Notification.Name("NeatWebApp.openMainWindow")
}

/// 菜单栏宿主的退出与再次打开：藏图标时系统可能顺手 terminate，必须拦住。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let terminationGuard = TerminationGuard()
    var isMenuBarIconVisible: () -> Bool = { true }
    var isUpdateSessionInProgress: () -> Bool = { false }
    private var presentMainWindow: (() -> Void)?
    private var pendingRecoveryPresentation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.isUpdateSessionInProgress() ?? false
        }
        let isLoginLaunch = LoginLaunchDetector.isLaunchedAsLoginItem
        if MenuBarReopenPolicy.shouldShowRecoveryWindow(
            iconVisible: menuBarIconVisibleFromDefaults(),
            isLoginLaunch: isLoginLaunch
        ) {
            pendingRecoveryPresentation = true
            flushPendingRecoveryIfPossible()
        }
    }

    /// 启动早期 Window 还未注入闭包，必须直接读偏好，不能等 onAppear。
    private func menuBarIconVisibleFromDefaults() -> Bool {
        let key = "menuBar.iconVisible"
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// 由界面注入 openWindow；suppressed 启动后若需恢复窗，等注入完成再出示。
    func installMainWindowPresenter(_ present: @escaping () -> Void) {
        presentMainWindow = present
        flushPendingRecoveryIfPossible()
    }

    private func flushPendingRecoveryIfPossible() {
        guard pendingRecoveryPresentation, let presentMainWindow else { return }
        pendingRecoveryPresentation = false
        presentMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MenuBarReopenPolicy.presentation(
            iconVisible: isMenuBarIconVisible(),
            isReopenOrLaunch: true
        ) == .showRecoveryWindow {
            if let presentMainWindow {
                presentMainWindow()
            } else {
                NotificationCenter.default.post(name: .neatWebAppOpenMainWindow, object: nil)
            }
        }
        return true
    }
}
