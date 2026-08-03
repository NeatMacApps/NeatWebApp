import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section("启动") {
                Toggle(
                    "开机时自动启动",
                    isOn: Binding(
                        get: { appModel.isLaunchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    )
                )
                .focusEffectDisabled()

                Text("开启后登录系统时会自动启动并常驻菜单栏，不会打开任何窗口。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 例外状态：这个登录项曾被关掉过，系统把它挂起了，开关点了也不会生效。
                // 不解释的话表现为「怎么点都没反应」，所以只在这种时候才出现。
                if appModel.isLaunchAtLoginBlockedBySystem {
                    Text("这台电脑上的这一项曾被关闭过，系统已把它挂起，需要在系统设置里重新打开一次。")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("打开系统设置") {
                        appModel.openLoginItemsSettings()
                    }
                    .focusEffectDisabled()
                }
            }

            Section("侧边刘海") {
                Picker(
                    "显示位置",
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
                .focusEffectDisabled()

                Text("如果系统程序坞位于同侧，侧边刘海会放在它的内侧，不会遮挡程序坞或占用最外侧唤出区域。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("虚拟刘海") {
                Toggle(
                    "在没有刘海的屏幕上启用",
                    isOn: Binding(
                        get: { appModel.isVirtualNotchEnabled },
                        set: { appModel.setVirtualNotchEnabled($0) }
                    )
                )
                .focusEffectDisabled()

                Text("外接显示器、Mac mini / Studio 以及旧款 MacBook 没有硬件刘海。开启后，屏幕顶部中央会有一块与刘海等效的隐形热区：指针在那里停留一下即可唤出启动器，点击菜单栏时不会被打断。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        // 高度按「等待放行」这个最高的状态取值：那时「启动」一节多出提示文字与放行按钮，
        // 取矮了最后一节会被裁掉，而这一节恰好是用户最需要看到的。
        .frame(width: 460, height: 560)
        // 用户可能刚在系统设置里放行完就切回来，重读一次才能去掉「等待放行」提示。
        .onAppear {
            appModel.refreshLaunchAtLoginState()
        }
    }
}
