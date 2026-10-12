import AppKit
import SwiftUI

@MainActor
@main
struct NeatWebAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appModel: AppModel
    private let appUpdater: AppUpdater

    @Environment(\.openSettings) private var openSettings

    init() {
        let appModel = AppModel()
        appModel.startIfNeeded()
        let updater = AppUpdater {
            appModel.prepareForApplicationUpdate()
        }
        self.appModel = appModel
        self.appUpdater = updater
        appDelegate.prepareForTermination = { [weak appModel] in
            appModel?.prepareForApplicationTermination()
        }
    }

    var body: some Scene {
        // The single management window (catalog + settings) is the Settings scene,
        // which gives its panes native icon + label toolbar tabs. There is no second window.
        Settings {
            DashboardView()
                .environment(appModel)
                .environmentObject(appUpdater)
                .onAppear {
                    appDelegate.isMenuBarIconVisible = { [appModel] in
                        appModel.isMenuBarIconVisible
                    }
                    appDelegate.isUpdateSessionInProgress = { [appUpdater] in
                        appUpdater.updater.sessionInProgress
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .neatWebAppOpenMainWindow)) { _ in
                    openMainWindow()
                }
        }
        // The Settings scene never opens on launch; with the icon hidden, AppDelegate recalls it on reopen.
        .commands {
            AppCommands(appModel: appModel)
            CommandGroup(after: .appInfo) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .onAppear {
                        appDelegate.installMainWindowPresenter {
                            openMainWindow()
                        }
                    }
            }
        }

        MenuBarExtra(
            "NeatWebApp",
            image: .menuBarIcon,
            isInserted: Binding(
                get: { appModel.isMenuBarIconVisible },
                set: { visible in
                    guard visible != appModel.isMenuBarIconVisible else { return }
                    appModel.setMenuBarIconVisible(visible)
                }
            )
        ) {
            Button(String(localized: "menubar.open_main_window")) {
                openMainWindow()
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button(String(localized: "menubar.reveal_launcher")) {
                appModel.revealLauncherManually()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Toggle(
                String(localized: "settings.login.startup.title"),
                isOn: Binding(
                    get: { appModel.isLaunchAtLoginEnabled },
                    set: { appModel.setLaunchAtLoginEnabled($0) }
                )
            )

            Button(String(localized: "menubar.hide_icon")) {
                appModel.setMenuBarIconVisible(false)
            }

            Button(updateButtonTitle) {
                appUpdater.updater.checkForUpdates()
            }
            .disabled(!appUpdater.canCheckForUpdates)

            Divider()

            Button(String(localized: "settings.quit")) {
                appDelegate.terminationGuard.requestTermination()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .menuBarExtraStyle(.menu)
    }

    /// 常驻菜单栏的应用打开窗口后不会自动激活，要手动抢一次前台，否则窗口会压在别的应用下面。
    private func openMainWindow() {
        openSettings()
        NSApplication.shared.activate()
    }

    private var updateButtonTitle: String {
        if let availableVersion = appUpdater.availableVersion {
            return String(
                format: String(localized: "settings.update.install_format"),
                availableVersion
            )
        }
        return String(localized: "settings.check_for_updates")
    }
}
