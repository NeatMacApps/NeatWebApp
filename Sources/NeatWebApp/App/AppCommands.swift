import SwiftUI

struct AppCommands: Commands {
    let appModel: AppModel

    var body: some Commands {
        let activeRuntimeAppID = appModel.activeRuntimeAppID

        CommandMenu("Launcher") {
            Button("Reveal Launcher") {
                appModel.revealLauncherManually()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Button("Refresh Screen Geometry") {
                appModel.refreshScreenState()
            }
            .keyboardShortcut("r", modifiers: [.command, .option, .shift])

            #if DEBUG
            // 未打磨完的调试能力：正式菜单禁止出现；仅 Debug 配置可见。
            Button(appModel.isNotchDebugOverlayVisible ? "Hide Notch Debug Overlay" : "Show Notch Debug Overlay") {
                appModel.toggleNotchDebugOverlay()
            }
            .keyboardShortcut("d", modifiers: [.command, .option, .shift])
            #endif
        }

        CommandMenu("Browser") {
            Button("Zoom In") {
                appModel.zoomInActiveWebApp()
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(activeRuntimeAppID == nil)

            Button("Zoom Out") {
                appModel.zoomOutActiveWebApp()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(activeRuntimeAppID == nil)

            Button("Actual Size") {
                appModel.resetZoomForActiveWebApp()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(activeRuntimeAppID == nil)
        }
    }
}
