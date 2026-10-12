import AppKit
import SwiftUI

/// "General" pane of the management window: every app-level setting fits here without scrolling.
/// Startup and menu bar presence, then launcher and Dock behavior, then one about row with
/// the maintenance actions (updates, quit) mirrored from the menu bar.
struct GeneralSettingsPane: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var appUpdater: AppUpdater

    var body: some View {
        Form {
            Section {
                Toggle(
                    "settings.login.startup.title",
                    isOn: Binding(
                        get: { appModel.isLaunchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    )
                )

                // Exception state: the system suspended this login item, so the switch has no effect.
                // Without this notice the switch looks broken, so it only appears in that state.
                if appModel.isLaunchAtLoginBlockedBySystem {
                    blockedNotice
                }

                Toggle(
                    "settings.menubar.icon.title",
                    isOn: Binding(
                        get: { appModel.isMenuBarIconVisible },
                        set: { appModel.setMenuBarIconVisible($0) }
                    )
                )
            }

            Section("settings.section.launcher_dock") {
                Toggle(
                    "settings.virtual_notch.title",
                    isOn: Binding(
                        get: { appModel.isVirtualNotchEnabled },
                        set: { appModel.setVirtualNotchEnabled($0) }
                    )
                )
                .help(Text("settings.virtual_notch.help"))

                Picker(
                    "settings.side_dock.edge.title",
                    selection: Binding(
                        get: { appModel.sideDockEdge },
                        set: { appModel.setSideDockEdge($0) }
                    )
                ) {
                    ForEach(SideDockEdge.allCases, id: \.self) { edge in
                        Text(edge.title)
                            .tag(edge)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                AboutRow()
            }
        }
        .settingsPaneStyle()
        // The user may have just approved the item in System Settings; re-read to clear the notice.
        .onAppear {
            appModel.refreshLaunchAtLoginState()
        }
    }

    private var blockedNotice: some View {
        LabeledContent {
            Button("settings.login.startup.open_system_settings") {
                appModel.openLoginItemsSettings()
            }
            .accessibilityLabel(Text("settings.login.startup.open_system_settings.accessibility_label"))
        } label: {
            Label {
                Text("settings.login.startup.blocked")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// App identity on the left, maintenance actions on the right, so no action sits alone in a row.
private struct AboutRow: View {
    @EnvironmentObject private var appUpdater: AppUpdater

    private var updateButtonTitle: String {
        if let availableVersion = appUpdater.availableVersion {
            return String(
                format: String(localized: "settings.update.install_format"),
                availableVersion
            )
        }
        return String(localized: "settings.check_for_updates")
    }

    private var versionTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return String(format: String(localized: "settings.version_format"), version)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "NeatWebApp")
                    .fontWeight(.medium)

                Text(versionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            Button(updateButtonTitle) {
                appUpdater.updater.checkForUpdates()
            }
            .disabled(!appUpdater.canCheckForUpdates)

            Button("settings.quit.short") {
                (NSApp.delegate as? AppDelegate)?.terminationGuard.requestTermination()
            }
            .accessibilityLabel(Text("settings.quit"))
        }
    }
}

extension View {
    /// Shared look of every main-window pane: native grouped form and switch toggles.
    /// The pane takes exactly its content height, so settings never scroll; only content
    /// taller than `maxHeight` (the user's web app list) scrolls inside the pane.
    func settingsPaneStyle(maxHeight: CGFloat = .infinity) -> some View {
        formStyle(.grouped)
            .toggleStyle(.switch)
            .modifier(FitToContentHeight(maxHeight: maxHeight))
    }
}

private struct FitToContentHeight: ViewModifier {
    let maxHeight: CGFloat

    @State private var contentHeight: CGFloat?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height
            } action: { _, height in
                contentHeight = height
            }
            .scrollDisabled((contentHeight ?? 0) <= maxHeight)
            .frame(height: contentHeight.map { min($0, maxHeight) })
    }
}
