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
    var prepareForTermination: () -> Void = {}
    private var presentMainWindow: (() -> Void)?
    /// 后台就绪时刻；菜单栏即主入口的二次启动防呆用。
    private var readyAt = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.isUpdateSessionInProgress() ?? false
        }
        readyAt = Date()
        // The catalog/settings window is not the daily entry (the notch launcher is).
        // Never auto-present it on launch — including when the menu bar icon is hidden.
        // A later Finder/Spotlight reopen of the already-running app still uses
        // applicationShouldHandleReopen.
    }

    /// 由界面注入 openWindow。
    func installMainWindowPresenter(_ present: @escaping () -> Void) {
        presentMainWindow = present
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationGuard.shouldTerminate() else {
            return .terminateCancel
        }

        // The browser runtimes are separate processes. Ask them to finish their
        // own cleanup before AppKit tears down the host process.
        prepareForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Keep this idempotent: this is also the fallback for termination paths
        // that do not give the normal quit action another callback opportunity.
        prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let elapsed = Date().timeIntervalSince(readyAt)
        // Finder/`open` often delivers reopen as part of the same cold start.
        // That is not a second launch; showing the catalog would pop a config
        // window that is not the daily entry.
        if elapsed < 2 {
            return true
        }
        if MenuBarReopenPolicy.presentation(
            iconVisible: isMenuBarIconVisible(),
            isReopenOrLaunch: true,
            isLoginLaunch: false,
            menubarIsPrimaryEntry: true,
            secondsSinceReady: elapsed
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
