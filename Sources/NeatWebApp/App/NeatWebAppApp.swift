import AppKit
#if DIRECT_DISTRIBUTION
import MacKitUpdater
#endif
import SwiftUI

@MainActor
@main
struct NeatWebAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appModel: AppModel
    #if DIRECT_DISTRIBUTION
    private let appUpdater: AppUpdater
    #endif

    init() {
        let appModel = AppModel()
        appModel.startIfNeeded()
        #if DIRECT_DISTRIBUTION
        let updater = AppUpdater {
            appModel.prepareForApplicationUpdate()
        }
        #endif
        self.appModel = appModel
        #if DIRECT_DISTRIBUTION
        self.appUpdater = updater
        #endif
        appDelegate.prepareForTermination = { [weak appModel] in
            appModel?.prepareForApplicationTermination()
        }
        #if DIRECT_DISTRIBUTION
        appDelegate.isUpdateSessionInProgress = { [weak updater] in
            updater?.updater.sessionInProgress ?? false
        }
        #endif
        #if APP_STORE
        appDelegate.restoreWebAppOnReopen = { [weak appModel] in
            appModel?.restoreWebAppOnReopen() ?? false
        }
        #endif
    }

    var body: some Scene {
        // The single management window (catalog + settings) is the Settings scene,
        // which gives its panes native icon + label toolbar tabs. There is no second window.
        Settings {
            #if DIRECT_DISTRIBUTION
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
            #else
            DashboardView()
                .environment(appModel)
                .onAppear {
                    appDelegate.isMenuBarIconVisible = { [appModel] in
                        appModel.isMenuBarIconVisible
                    }
                }
            #endif
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        // The Settings scene never opens on launch; with the icon hidden, AppDelegate recalls it on reopen.
        .commands {
            AppCommands(appModel: appModel)
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

            #if DIRECT_DISTRIBUTION
            MenuBarUpdateButton(availability: appUpdater.availability) {
                appUpdater.updater.checkForUpdates()
            }
            #endif

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
        ManagementWindowPresenter.present()
    }
}

#if DIRECT_DISTRIBUTION
private struct MenuBarUpdateButton: View {
    let availability: UpdateAvailabilityState
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
    }

    private var title: String {
        if let availableVersion = availability.availableVersion {
            return String(
                format: String(localized: "settings.update.install_format"),
                availableVersion
            )
        }
        return String(localized: "settings.check_for_updates")
    }
}
#endif
