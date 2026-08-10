import SwiftUI

/// 设置区块，内嵌在主窗口里；本应用不再提供独立的设置窗口。
struct SettingsSectionView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var focusedControl: FocusedControl?

    private enum FocusedControl: Hashable {
        case launchAtLogin
        case sideDockEdge
        case virtualNotch
        case openSystemSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.section.title")
                .panelSectionTitle()

            VStack(spacing: 0) {
                launchAtLoginRow

                // 例外状态：这个登录项曾被关掉过，系统把它挂起了，开关点了也不会生效。
                // 不解释的话表现为「怎么点都没反应」，所以只在这种时候才出现。
                if appModel.isLaunchAtLoginBlockedBySystem {
                    rowDivider
                    blockedNotice
                }

                rowDivider
                sideDockEdgeRow
                rowDivider
                virtualNotchRow
            }
            .panelCard()
        }
        // 用户可能刚在系统设置里放行完就切回来，重读一次才能去掉挂起提示。
        .onAppear {
            appModel.refreshLaunchAtLoginState()
        }
    }

    private var launchAtLoginRow: some View {
        settingRow("settings.login.startup.title") {
            Toggle(
                "",
                isOn: Binding(
                    get: { appModel.isLaunchAtLoginEnabled },
                    set: { appModel.setLaunchAtLoginEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .focusEffectDisabled()
            .focused($focusedControl, equals: .launchAtLogin)
            .settingFocusIndicator(focusedControl == .launchAtLogin)
            .accessibilityLabel(Text("settings.login.startup.title"))
        }
    }

    private var sideDockEdgeRow: some View {
        settingRow("settings.side_dock.edge.title") {
            Picker(
                "",
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
            .labelsHidden()
            .frame(width: 176)
            .focusEffectDisabled()
            .focused($focusedControl, equals: .sideDockEdge)
            .settingFocusIndicator(focusedControl == .sideDockEdge)
            .accessibilityLabel(Text("settings.side_dock.edge.title"))
        }
    }

    private var virtualNotchRow: some View {
        settingRow(
            "settings.virtual_notch.title",
            help: "settings.virtual_notch.help"
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: { appModel.isVirtualNotchEnabled },
                    set: { appModel.setVirtualNotchEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .focusEffectDisabled()
            .focused($focusedControl, equals: .virtualNotch)
            .settingFocusIndicator(focusedControl == .virtualNotch)
            .accessibilityLabel(Text("settings.virtual_notch.title"))
        }
    }

    private var blockedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text("settings.login.startup.blocked")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("settings.login.startup.open_system_settings") {
                appModel.openLoginItemsSettings()
            }
            .controlSize(.small)
            .focusEffectDisabled()
            .focused($focusedControl, equals: .openSystemSettings)
            .settingFocusIndicator(focusedControl == .openSystemSettings)
            .accessibilityLabel(Text("settings.login.startup.open_system_settings.accessibility_label"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 14)
    }

    /// 设置行统一形态：左侧一句话标题，右侧控件；补充说明只作为悬停提示，不占版面。
    private func settingRow<Control: View>(
        _ title: LocalizedStringKey,
        help: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))

            Spacer(minLength: 12)

            control()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .contentShape(Rectangle())
        .modifier(OptionalHelpModifier(text: help))
    }
}

/// 只有存在补充说明时才挂 tooltip，避免空气泡。
private struct OptionalHelpModifier: ViewModifier {
    let text: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let text {
            content.help(Text(text))
        } else {
            content
        }
    }
}

private extension View {
    /// 统一取代系统默认蓝色焦点框；颜色跟随前景色，深浅色下都能辨认。
    func settingFocusIndicator(_ isFocused: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
                .padding(-3)
        }
    }
}
