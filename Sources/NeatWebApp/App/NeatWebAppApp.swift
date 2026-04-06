import SwiftUI

@MainActor
@main
struct NeatWebAppApp: App {
    private let appModel: AppModel

    @Environment(\.openWindow) private var openWindow

    init() {
        let appModel = AppModel()
        appModel.startIfNeeded()
        self.appModel = appModel
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

        MenuBarExtra("NeatWebApp", systemImage: "menubar.dock.rectangle") {
            Button("Open Dashboard") {
                openWindow(id: "dashboard")
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("Reveal Launcher") {
                appModel.revealLauncherManually()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appModel.isLaunchAtLoginEnabled },
                    set: { appModel.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider()

            Button("Quit NeatWebApp") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
