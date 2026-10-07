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
    private var standby: RuntimeStandby?
    private let environment = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        let hostProcessID = RuntimeBootstrapLoader.processIdentifier(
            after: "--host-pid",
            in: CommandLine.arguments
        )

        if let standbyID = RuntimeBootstrapLoader.standbyIdentifier(in: CommandLine.arguments) {
            let standby = RuntimeStandby(instanceID: standbyID, hostProcessID: hostProcessID) { [weak self] bootstrap in
                self?.standby = nil
                self?.startCoordinator(bootstrap: bootstrap, hostProcessID: hostProcessID)
            }
            self.standby = standby
            standby.start()
            return
        }

        do {
            let bootstrap = try RuntimeBootstrapLoader().load()
            startCoordinator(bootstrap: bootstrap, hostProcessID: hostProcessID)
        } catch {
            terminateUnlessTesting()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeCoordinator?.prepareForTermination()
    }

    private func startCoordinator(bootstrap: RuntimeBootstrap, hostProcessID: Int32?) {
        let coordinator = RuntimeWindowCoordinator(
            bootstrap: bootstrap,
            hostProcessID: hostProcessID
        )
        runtimeCoordinator = coordinator
        do {
            try coordinator.start()
        } catch {
            terminateUnlessTesting()
        }
    }

    private func terminateUnlessTesting() {
        guard environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        NSApplication.shared.terminate(nil)
    }
}
