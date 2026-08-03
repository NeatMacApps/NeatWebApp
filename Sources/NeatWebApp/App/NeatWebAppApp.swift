import SwiftUI

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
        Window("NeatWebApp", id: "dashboard") {
            DashboardView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(appModel)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            AppCommands(appModel: appModel)
        }

        Settings {
            SettingsView()
                .environment(appModel)
        }

        MenuBarExtra("NeatWebApp", image: .menuBarIcon) {
            Button("Open Dashboard") {
                openWindow(id: "dashboard")
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Reveal Launcher") {
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

            SettingsLink {
                Text("设置…")
            }

            CheckForUpdatesButton(appUpdater: appUpdater)

            Divider()

            Button("Quit NeatWebApp") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
