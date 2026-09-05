import AppKit
import SwiftUI

struct WebAppIconView: View {
    let app: WebAppDefinition
    let size: CGFloat
    let font: Font
    /// 已缓存的 favicon；为 nil 时显示首字母回退。
    let favicon: NSImage?
    /// 视图出现时触发加载（例如从磁盘/网络补齐）。调用方负责接到具体服务。
    let loadFavicon: () -> Void

    var body: some View {
        ZStack {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Circle()
                    .fill(backgroundStyle)

                Text(app.fallbackIconLetter)
                    .font(font)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        // Launcher icons intentionally avoid drop shadows.
        // When six icons sit in one row, their shadows merge into a gray band under the bar.
        .overlay {
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .task {
            loadFavicon()
        }
    }

    private var backgroundStyle: some ShapeStyle {
        return AnyShapeStyle(Color.webAppAccent(named: app.accentColorName).opacity(0.92))
    }
}

private extension WebAppDefinition {
    var fallbackIconLetter: String {
        guard let firstLetter = name.first(where: \.isLetter) else {
            return "#"
        }

        return String(firstLetter).uppercased()
    }
}

private extension Color {
    static func webAppAccent(named name: String) -> Color {
        switch name {
        case "WebAppAccentOrange":
            return .orange
        case "WebAppAccentGreen":
            return .green
        case "WebAppAccentGray":
            return .gray
        case "WebAppAccentRed":
            return .red
        case "WebAppAccentBlue":
            return .blue
        case "WebAppAccentPurple":
            return .indigo
        default:
            return .white
        }
    }
}
