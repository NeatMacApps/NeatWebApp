import SwiftUI

struct LauncherOverlayRootView: View {
    @State private var isExpanded = false

    let context: LauncherPresentationContext
    let onSelectApp: (WebAppDefinition) -> Void

    var body: some View {
        let layout = context.layout

        VStack(spacing: 0) {
            attachedLauncher(layout: layout)
                .scaleEffect(
                    x: isExpanded ? 1 : 0.92,
                    y: isExpanded ? 1 : 0.32,
                    anchor: .top
                )
                .opacity(isExpanded ? 1 : 0)
                .blur(radius: isExpanded ? 0 : 8)

            Spacer(minLength: 0)
        }
        .frame(width: context.panelSize.width, height: context.panelSize.height)
        .onAppear {
            isExpanded = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isExpanded = true
            }
        }
        .onDisappear {
            isExpanded = false
        }
    }

    private func attachedLauncher(layout: LauncherPresentationContext.Layout) -> some View {
        ZStack(alignment: .top) {
            TopAttachedLauncherShape(cornerRadius: layout.backgroundCornerRadius)
                .fill(islandFill)

            TopAttachedLauncherShape(cornerRadius: layout.backgroundCornerRadius)
                .stroke(.white.opacity(0.06), lineWidth: 1)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: layout.topInsetHeight)

                HStack(spacing: 0) {
                    ForEach(context.apps) { app in
                        Button {
                            onSelectApp(app)
                        } label: {
                            WebAppIconView(
                                app: app,
                                size: layout.iconSize,
                                cornerRadius: layout.iconCornerRadius,
                                font: .system(size: layout.iconFontSize, weight: .semibold)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(app.name)
                        .accessibilityLabel(app.name)
                    }
                }
                .frame(height: layout.iconRowHeight)
            }
        }
        .frame(width: layout.barSize.width, height: layout.barSize.height, alignment: .top)
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }

    private var islandFill: Color {
        .black
    }
}

private struct TopAttachedLauncherShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()

        return path
    }
}

#Preview {
    LauncherOverlayRootView(
        context: LauncherPresentationContext(
            geometry: ScreenNotchGeometry(
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
                safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
                auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
                localizedName: "Built-in Display"
            ),
            apps: WebAppDefinition.examples
        ),
        onSelectApp: { _ in }
    )
    .background(Color.gray.opacity(0.1))
    .environment(AppModel())
}
