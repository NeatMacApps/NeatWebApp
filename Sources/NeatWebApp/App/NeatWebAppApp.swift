import AppKit
import SwiftUI

/// 窗口标识：启动器、菜单栏和快捷键都要打开同一个主窗口。
enum AppWindowID {
    static let main = "main"
}

@MainActor
@main
struct NeatWebAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appModel: AppModel
    private let appUpdater: AppUpdater

    @Environment(\.openWindow) private var openWindow

    init() {
        let appModel = AppModel()
        appModel.startIfNeeded()
        self.appModel = appModel
        appUpdater = AppUpdater {
            appModel.prepareForApplicationUpdate()
        }
    }

    var body: some Scene {
        // 主窗口同时承担设置界面，不再提供独立的设置窗口。
        Window("NeatWebApp", id: AppWindowID.main) {
            DashboardView()
                .environment(appModel)
                .environmentObject(appUpdater)
                .onAppear {
                    appDelegate.isMenuBarIconVisible = { [appModel] in
                        appModel.isMenuBarIconVisible
                    }
                    appDelegate.isUpdateSessionInProgress = { [appUpdater] in
                        appUpdater.updater.sessionInProgress
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .neatWebAppOpenMainWindow)) { _ in
                    openMainWindow()
                }
        }
        // 登录与图标可见时的冷启动都不自动开主窗；图标已隐藏且非登录时由 AppDelegate 唤回。
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .commands {
            AppCommands(appModel: appModel)
            CommandGroup(after: .appInfo) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .onAppear {
                        appDelegate.installMainWindowPresenter {
                            openMainWindow()
                        }
                    }
            }
        }

        MenuBarExtra(
            "NeatWebApp",
            image: .menuBarIcon,
            isInserted: Binding(
                get: { appModel.isMenuBarIconVisible },
                set: { visible in
                    guard visible != appModel.isMenuBarIconVisible else { return }
                    appModel.setMenuBarIconVisible(visible)
                }
            )
        ) {
            Button("打开主窗口") {
                openMainWindow()
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("唤出启动器") {
                appModel.revealLauncherManually()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Toggle(
                "开机时自动启动",
                isOn: Binding(
                    get: { appModel.isLaunchAtLoginEnabled },
                    set: { appModel.setLaunchAtLoginEnabled($0) }
                )
            )

            Button("隐藏菜单栏图标") {
                appModel.setMenuBarIconVisible(false)
            }

            Button(updateButtonTitle) {
                appUpdater.updater.checkForUpdates()
            }
            .disabled(!appUpdater.canCheckForUpdates)

            Divider()

            Button("退出 NeatWebApp") {
                appDelegate.terminationGuard.requestTermination()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .menuBarExtraStyle(.menu)
    }

    /// 常驻菜单栏的应用打开窗口后不会自动激活，要手动抢一次前台，否则窗口会压在别的应用下面。
    private func openMainWindow() {
        openWindow(id: AppWindowID.main)
        NSApplication.shared.activate()
    }

    private var updateButtonTitle: String {
        if let availableVersion = appUpdater.availableVersion {
            return "安装 NeatWebApp \(availableVersion) 更新…"
        }
        return "检查更新…"
    }
}
