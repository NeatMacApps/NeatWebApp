import AppKit
import SwiftUI

struct LauncherOverlayRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var appModel
    @State private var isExpanded = false
    @State private var edgeFadeState = LauncherEdgeFadeState.none
    /// 应用顺序工作副本：拖动过程中不改，松手时换位并整份写回持久层。
    @State private var orderedApps: [WebAppDefinition] = []
    @State private var draggingAppID: String?
    /// 被拖图标在松手滑回槽位期间仍压在其他图标之上。
    @State private var liftedAppID: String?
    @State private var draggingStartIndex = 0
    @State private var dragTargetIndex = 0
    @State private var dragTranslationX: CGFloat = 0

    let context: LauncherPresentationContext
    let onSelectApp: (WebAppDefinition) -> Void

    private var launcherItems: [LauncherItem] {
        orderedApps.map(LauncherItem.webApp) + [.dashboard]
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
        // 非激活浮层上的第一次按下默认只用来激活窗口；图标手势必须能直接吃掉这次点击。
        .allowsWindowActivationEvents()
        .onAppear {
            orderedApps = context.apps
            isExpanded = false
            resetEdgeFadeState(for: layout)
            updateExpandedState(for: appModel.isLauncherVisible, animated: true)
        }
        .onChange(of: appModel.isLauncherVisible) { _, isLauncherVisible in
            updateExpandedState(for: isLauncherVisible, animated: true)
        }
        .onChange(of: context.apps.count) { _, _ in
            orderedApps = context.apps
            resetEdgeFadeState(for: context.layout)
        }
        .onChange(of: context.panelSize) { _, _ in
            resetEdgeFadeState(for: context.layout)
        }
    }

    private func attachedLauncher(layout: LauncherPresentationContext.Layout) -> some View {
        ZStack(alignment: .top) {
            EdgeAttachedShape(edge: .top, cornerRadius: layout.backgroundCornerRadius)
                .fill(islandFill)

            EdgeAttachedShape(edge: .top, cornerRadius: layout.backgroundCornerRadius)
                .stroke(.white.opacity(0.06), lineWidth: 1)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: layout.topInsetHeight)

                iconRow(layout: layout)
            }
        }
        .frame(width: layout.barSize.width, height: layout.barSize.height, alignment: .top)
        // 点在图标以外的黑底上就收起；图标自己的手势优先，不会被这里抢走。
        .contentShape(EdgeAttachedShape(edge: .top, cornerRadius: layout.backgroundCornerRadius))
        .onTapGesture {
            appModel.dismissLauncherVoluntarily()
        }
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
                iconButton(item: item, layout: layout)
            }
        }
    }

    /// 图标入口。不能再用 `Button`：macOS 的 Button 按下后会自己跟踪鼠标，
    /// 拖动手势的滑动事件会被它吞掉，导致「拖动不跟手」。
    /// 点击和拖动合成一个手势：位移很小当点开，否则换位。
    /// 分开写 `onTapGesture` + `DragGesture` 时，拖动手势会把点击吃掉，表现为点了没反应。
    @ViewBuilder
    private func iconButton(item: LauncherItem, layout: LauncherPresentationContext.Layout) -> some View {
        let isDragged = draggingAppID == item.id
        let icon = launcherIcon(for: item, layout: layout)
            .contentShape(Rectangle())
            .help(item.helpText)
            .accessibilityLabel(item.helpText)
            .accessibilityAddTraits(.isButton)
            .scaleEffect(isDragged ? Self.liftScale : 1)
            .animation(Self.liftAnimation, value: isDragged)
            .offset(x: iconOffsetX(for: item))
            // 被拖的图标直接等于指针位移，不能带动画，否则慢半拍；其余图标让位时滑一格。
            .animation(isDragged ? nil : Self.shiftAnimation, value: dragTargetIndex)
            .zIndex(isDragged || liftedAppID == item.id ? 1 : 0)

        switch item {
        case .webApp(let app):
            icon.gesture(webAppInteractionGesture(for: app, item: item))
        case .dashboard:
            icon.gesture(dashboardClickGesture(for: item))
        }
    }

    private func webAppInteractionGesture(
        for app: WebAppDefinition,
        item: LauncherItem
    ) -> some Gesture {
        // 必须用全局坐标：手势挂在带偏移的图标上，本地坐标会跟着图标移动，量出的位移来回跳。
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard !Self.isClick(translation: value.translation) else {
                    return
                }

                handleDragChanged(for: app, value: value)
            }
            .onEnded { value in
                let shouldOpen = draggingAppID == nil && Self.isClick(translation: value.translation)
                handleDragEnded()
                if shouldOpen {
                    handleSelection(for: item)
                }
            }
    }

    private func dashboardClickGesture(for item: LauncherItem) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                if Self.isClick(translation: value.translation) {
                    handleSelection(for: item)
                }
            }
    }

    /// 触控板单击经常带几像素抖动；小于这个距离一律当点开，不当换位。
    private static let clickSlop: CGFloat = 8

    private static func isClick(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < clickSlop
    }

    private static let liftScale: CGFloat = 1.08
    private static let liftAnimation = Animation.snappy(duration: 0.15)
    private static let shiftAnimation = Animation.snappy(duration: 0.2)
    private static let dropAnimation = Animation.snappy(duration: 0.22)

    private var slotWidth: CGFloat {
        context.layout.iconSize + context.layout.iconSpacing
    }

    /// 拖动中顺序不变，只靠偏移显示换位效果：被拖图标贴住指针，起点与目标之间的图标让出一格。
    private func iconOffsetX(for item: LauncherItem) -> CGFloat {
        guard let draggingAppID, case .webApp(let app) = item else {
            return 0
        }

        if app.id == draggingAppID {
            return dragTranslationX
        }

        guard let index = orderedApps.firstIndex(of: app) else {
            return 0
        }

        return LauncherRowReorder.displacement(
            index: index,
            startIndex: draggingStartIndex,
            targetIndex: dragTargetIndex,
            slotWidth: slotWidth
        )
    }

    private func handleDragChanged(for app: WebAppDefinition, value: DragGesture.Value) {
        guard slotWidth > 0 else {
            return
        }

        if draggingAppID != app.id {
            let startIndex = orderedApps.firstIndex(of: app) ?? 0
            draggingAppID = app.id
            liftedAppID = app.id
            draggingStartIndex = startIndex
            dragTargetIndex = startIndex
        }

        dragTranslationX = value.translation.width
        dragTargetIndex = LauncherRowReorder.targetIndex(
            startIndex: draggingStartIndex,
            translationX: value.translation.width,
            slotWidth: slotWidth,
            itemCount: orderedApps.count
        )
    }

    /// 松手时一次性换位并在同一个动画里清掉偏移：让位的图标排版位置与偏移同步抵消，看起来不动；
    /// 被拖图标从指针处滑进目标槽位。
    private func handleDragEnded() {
        guard let droppedAppID = draggingAppID else {
            return
        }

        let startIndex = draggingStartIndex
        let targetIndex = dragTargetIndex

        withAnimation(Self.dropAnimation) {
            if targetIndex != startIndex {
                orderedApps.move(
                    fromOffsets: IndexSet(integer: startIndex),
                    toOffset: targetIndex > startIndex ? targetIndex + 1 : targetIndex
                )
            }
            draggingAppID = nil
            dragTranslationX = 0
        } completion: {
            if draggingAppID == nil, liftedAppID == droppedAppID {
                liftedAppID = nil
            }
        }

        if targetIndex != startIndex {
            appModel.applyAppOrder(orderedApps)
        }
    }

    @ViewBuilder
    private func launcherIcon(for item: LauncherItem, layout: LauncherPresentationContext.Layout) -> some View {
        switch item {
        case .webApp(let app):
            WebAppIconView(
                app: app,
                size: layout.iconSize * 0.85,
                font: .system(size: layout.iconFontSize * 0.85, weight: .semibold),
                favicon: appModel.faviconImage(for: app),
                loadFavicon: { appModel.ensureFaviconLoaded(for: app) }
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
            openWindow(id: AppWindowID.main)
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
            return String(localized: "menubar.open_main_window")
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
