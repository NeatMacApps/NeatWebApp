import SwiftUI

struct LauncherOverlayRootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isExpanded = false

    let context: LauncherPresentationContext
    let onSelectApp: (WebAppDefinition) -> Void

    var body: some View {
        let layout = context.layout

        VStack(spacing: 0) {
            attachedLauncher(layout: layout)
                .frame(
                    width: layout.barSize.width,
                    height: isExpanded ? layout.barSize.height : layout.topInsetHeight,
                    alignment: .top
                )
                .clipped()
                .offset(y: isExpanded ? 0 : -6)
                .opacity(isExpanded ? 1 : 0.92)

            Spacer(minLength: 0)
        }
        .frame(width: context.panelSize.width, height: context.panelSize.height)
        .onAppear {
            isExpanded = false
            updateExpandedState(for: appModel.isLauncherVisible, animated: true)
        }
        .onChange(of: appModel.isLauncherVisible) { _, isLauncherVisible in
            updateExpandedState(for: isLauncherVisible, animated: true)
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

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: layout.iconSpacing) {
                        ForEach(context.apps) { app in
                            Button {
                                onSelectApp(app)
                            } label: {
                                WebAppIconView(
                                    app: app,
                                    size: layout.iconSize,
                                    font: .system(size: layout.iconFontSize, weight: .semibold)
                                )
                                .frame(width: layout.iconSize, height: layout.iconSize)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(app.name)
                            .accessibilityLabel(app.name)
                        }
                    }
                    .padding(.horizontal, layout.iconSpacing)
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: layout.iconRowHeight, alignment: .top)
            }
        }
        .frame(width: layout.barSize.width, height: layout.barSize.height, alignment: .top)
        // Keep the launcher body flat against the page content.
        // A drop shadow here reads as an extra translucent strip under the bar.
    }

    private var islandFill: Color {
        .black
    }

    private func updateExpandedState(for isLauncherVisible: Bool, animated: Bool) {
        if animated {
            withAnimation(.smooth(duration: 0.22)) {
                isExpanded = isLauncherVisible
            }
        } else {
            isExpanded = isLauncherVisible
        }
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
