import AppKit
import SwiftUI

struct WebAppIconView: View {
    @Environment(AppModel.self) private var appModel

    let app: WebAppDefinition
    let size: CGFloat
    let cornerRadius: CGFloat
    let font: Font

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundStyle)

            if let favicon = appModel.faviconImage(for: app) {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Text(app.fallbackIconLetter)
                    .font(font)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .task {
            appModel.ensureFaviconLoaded(for: app)
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if appModel.faviconImage(for: app) != nil {
            return AnyShapeStyle(.white.opacity(0.96))
        }

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
