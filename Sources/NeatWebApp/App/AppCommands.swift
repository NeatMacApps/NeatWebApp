import SwiftUI

struct AppCommands: Commands {
    let appModel: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let activeRuntimeAppID = appModel.activeRuntimeAppID

        // 设置并入主窗口后，⌘, 仍然沿用系统习惯，直接把主窗口带到前台。
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: AppWindowID.main)
                NSApplication.shared.activate()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

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
