import SwiftUI

/// 窗口标识：启动器、菜单栏和快捷键都要打开同一个主窗口。
enum AppWindowID {
    static let main = "main"
}

@MainActor
@main
struct NeatWebAppApp: App {
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
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .commands {
            AppCommands(appModel: appModel)
        }

        MenuBarExtra("NeatWebApp", image: .menuBarIcon) {
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

            CheckForUpdatesButton(appUpdater: appUpdater)

            Divider()

            Button("退出 NeatWebApp") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    /// 常驻菜单栏的应用打开窗口后不会自动激活，要手动抢一次前台，否则窗口会压在别的应用下面。
    private func openMainWindow() {
        openWindow(id: AppWindowID.main)
        NSApplication.shared.activate()
    }

}
