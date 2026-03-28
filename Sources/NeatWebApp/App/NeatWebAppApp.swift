import SwiftUI

@main
struct NeatWebAppApp: App {
    @State private var appModel = AppModel()

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("NeatWebApp", id: "dashboard") {
            DashboardView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(appModel)
                .task {
                    appModel.startIfNeeded()
                }
        }
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

            Divider()

            Button("Quit NeatWebApp") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
