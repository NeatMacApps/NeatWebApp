import AppKit
import SwiftUI

struct LauncherOverlayRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var appModel
    @State private var isExpanded = false
    @State private var edgeFadeState = LauncherEdgeFadeState.none

    let context: LauncherPresentationContext
    let onSelectApp: (WebAppDefinition) -> Void

    private var launcherItems: [LauncherItem] {
        context.apps.map(LauncherItem.webApp) + [.dashboard]
    }

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
            resetEdgeFadeState(for: layout)
            updateExpandedState(for: appModel.isLauncherVisible, animated: true)
        }
        .onChange(of: appModel.isLauncherVisible) { _, isLauncherVisible in
            updateExpandedState(for: isLauncherVisible, animated: true)
        }
        .onChange(of: context.apps.count) { _, _ in
            resetEdgeFadeState(for: context.layout)
        }
        .onChange(of: context.panelSize) { _, _ in
            resetEdgeFadeState(for: context.layout)
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

                iconRow(layout: layout)
            }
        }
        .frame(width: layout.barSize.width, height: layout.barSize.height, alignment: .top)
        // Keep the launcher body flat against the page content.
        // A drop shadow here reads as an extra translucent strip under the bar.
    }

    private var islandFill: Color {
        .black
    }

    private func iconRow(layout: LauncherPresentationContext.Layout) -> some View {
        iconRowContent(layout: layout)
            .mask(edgeFadeMask)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(height: layout.iconRowHeight, alignment: .top)
            .animation(.easeOut(duration: 0.12), value: edgeFadeState)
    }

    @ViewBuilder
    private func iconRowContent(layout: LauncherPresentationContext.Layout) -> some View {
        if layout.shouldScroll {
            ScrollView(.horizontal, showsIndicators: false) {
                iconButtons(layout: layout)
                    .scrollTargetLayout()
            }
            .contentMargins(.horizontal, layout.iconHorizontalPadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onScrollGeometryChange(for: LauncherEdgeFadeState.self) { geometry in
                LauncherEdgeFadeState(
                    scrollGeometry: geometry,
                    horizontalPadding: layout.iconHorizontalPadding
                )
            } action: { _, newValue in
                edgeFadeState = newValue
            }
        } else if launcherItems.count == 1 {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                iconButtons(layout: layout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.iconHorizontalPadding)
        } else {
            HStack(spacing: 0) {
                iconButtons(layout: layout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.iconHorizontalPadding)
        }
    }

    private func iconButtons(layout: LauncherPresentationContext.Layout) -> some View {
        HStack(alignment: .top, spacing: layout.iconSpacing) {
            ForEach(launcherItems) { item in
                Button {
                    handleSelection(for: item)
                } label: {
                    launcherIcon(for: item, layout: layout)
                }
                .buttonStyle(.plain)
                .help(item.helpText)
                .accessibilityLabel(item.helpText)
            }
        }
    }

    @ViewBuilder
    private func launcherIcon(for item: LauncherItem, layout: LauncherPresentationContext.Layout) -> some View {
        switch item {
        case .webApp(let app):
            WebAppIconView(
                app: app,
                size: layout.iconSize * 0.85,
                font: .system(size: layout.iconFontSize * 0.85, weight: .semibold)
            )
            .frame(width: layout.iconSize, height: layout.iconSize)
            .contentShape(Rectangle())
        case .dashboard:
            Image(systemName: "plus")
                .font(.system(size: layout.iconFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: layout.iconSize, height: layout.iconSize)
                .contentShape(Rectangle())
        }
    }

    private func handleSelection(for item: LauncherItem) {
        switch item {
        case .webApp(let app):
            onSelectApp(app)
        case .dashboard:
            appModel.hideLauncher(immediately: true)
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: edgeFadeState.showsLeadingFade ? .clear : .black, location: 0),
                .init(color: .black, location: 0.1),
                .init(color: .black, location: 0.9),
                .init(color: edgeFadeState.showsTrailingFade ? .clear : .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func resetEdgeFadeState(for layout: LauncherPresentationContext.Layout) {
        edgeFadeState = layout.shouldScroll ? .trailingOnly : .none
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

private enum LauncherItem: Identifiable {
    case webApp(WebAppDefinition)
    case dashboard

    var id: String {
        switch self {
        case .webApp(let app):
            return app.id
        case .dashboard:
            return "dashboard-launcher-item"
        }
    }

    var helpText: String {
        switch self {
        case .webApp(let app):
            return app.name
        case .dashboard:
            return "Open Dashboard"
        }
    }
}

struct LauncherEdgeFadeState: Equatable, Sendable {
    static let none = LauncherEdgeFadeState(showsLeadingFade: false, showsTrailingFade: false)
    static let trailingOnly = LauncherEdgeFadeState(showsLeadingFade: false, showsTrailingFade: true)

    let showsLeadingFade: Bool
    let showsTrailingFade: Bool

    init(showsLeadingFade: Bool, showsTrailingFade: Bool) {
        self.showsLeadingFade = showsLeadingFade
        self.showsTrailingFade = showsTrailingFade
    }

    init(
        visibleRect: CGRect,
        contentWidth: CGFloat,
        horizontalPadding: CGFloat,
        threshold: CGFloat = 1
    ) {
        guard visibleRect.width > 0, contentWidth > 0 else {
            self = .none
            return
        }

        let leadingHiddenWidth = max(visibleRect.minX - horizontalPadding, 0)
        let trailingVisibleLimit = contentWidth - horizontalPadding
        let trailingHiddenWidth = max(trailingVisibleLimit - visibleRect.maxX, 0)

        self.init(
            showsLeadingFade: leadingHiddenWidth > threshold,
            showsTrailingFade: trailingHiddenWidth > threshold
        )
    }

    init(scrollGeometry: ScrollGeometry, horizontalPadding: CGFloat, threshold: CGFloat = 1) {
        self.init(
            visibleRect: scrollGeometry.visibleRect,
            contentWidth: scrollGeometry.contentSize.width,
            horizontalPadding: horizontalPadding,
            threshold: threshold
        )
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
