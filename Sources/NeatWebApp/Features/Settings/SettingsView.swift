import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
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
        .frame(width: 460, height: 360)
    }
}
