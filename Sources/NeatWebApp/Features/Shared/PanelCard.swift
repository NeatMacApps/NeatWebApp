import SwiftUI

/// 主窗口内各分组统一使用的卡片底板，保证列表与设置区外观一致。
struct PanelCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.9 : 1),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor)
                            .opacity(colorScheme == .dark ? 0.5 : 0.4),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func panelCard() -> some View {
        modifier(PanelCardModifier())
    }

    /// 分组标题：只在需要区分区块时出现，正文不再堆叠说明性文字。
    func panelSectionTitle() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
