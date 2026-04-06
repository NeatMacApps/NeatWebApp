import AppKit
import SwiftUI

@MainActor
@main
struct NeatWebAppRuntimeApp: App {
    @NSApplicationDelegateAdaptor(RuntimeAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class RuntimeAppDelegate: NSObject, NSApplicationDelegate {
    private var runtimeCoordinator: RuntimeWindowCoordinator?
    private let environment = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let bootstrap = try RuntimeBootstrapLoader().load()
            let coordinator = RuntimeWindowCoordinator(bootstrap: bootstrap)
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
