import AppKit
import SwiftUI

@MainActor
@main
struct NeatWebAppRuntimeApp: App {
    @NSApplicationDelegateAdaptor(RuntimeAppDelegate.self) private var appDelegate

    var body: some Scene {
        // 真窗是 AppKit 建的，这里只是占位 Scene。去掉系统默认的偏好设置入口，
        // 否则 Command+, 会打开一扇只有 EmptyView 的空白设置窗。
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

@MainActor
final class RuntimeAppDelegate: NSObject, NSApplicationDelegate {
    private var runtimeCoordinator: RuntimeWindowCoordinator?
    private let environment = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        do {
            let bootstrap = try RuntimeBootstrapLoader().load()
            let hostProcessID = RuntimeBootstrapLoader.processIdentifier(
                after: "--host-pid",
                in: CommandLine.arguments
            )
            let coordinator = RuntimeWindowCoordinator(
                bootstrap: bootstrap,
                hostProcessID: hostProcessID
            )
            self.runtimeCoordinator = coordinator
            try coordinator.start()
        } catch {
            guard environment["XCTestConfigurationFilePath"] == nil else {
                return
            }

            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeCoordinator?.prepareForTermination()
    }
}
