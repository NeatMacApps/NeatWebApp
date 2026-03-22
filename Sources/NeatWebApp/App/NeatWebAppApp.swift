import SwiftUI

@main
struct NeatWebAppApp: App {
    @State private var appModel = AppModel()

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
    }
}
