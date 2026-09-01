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

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.isUpdateSessionInProgress() ?? false
        }
        if MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: isMenuBarIconVisible()) {
            NotificationCenter.default.post(name: .neatWebAppOpenMainWindow, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MenuBarReopenPolicy.presentation(iconVisible: isMenuBarIconVisible(), isReopenOrLaunch: true)
            == .showRecoveryWindow {
            NotificationCenter.default.post(name: .neatWebAppOpenMainWindow, object: nil)
        }
        return true
    }
}
