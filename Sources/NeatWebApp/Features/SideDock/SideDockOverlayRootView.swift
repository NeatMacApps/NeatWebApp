import AppKit
import SwiftUI

struct SideDockOverlayRootView: View {
    @State private var iconFrames: [String: CGRect] = [:]
    @State private var draggedAppID: String?
    @State private var dragStartMouseLocation: CGPoint?
    @State private var closeProgress: CGFloat = 0

    var state: SideDockOverlayState
    let onSelectApp: (WebAppDefinition) -> Void
    let onDragChange: (SideDockDragUpdate) -> Void
    let onDragEnd: () -> Void

    private var context: SideDockPresentationContext {
        state.context
    }

    var body: some View {
        let shape = EdgeAttachedShape(
            edge: context.edge.attachedShapeEdge,
            cornerRadius: SideDockPresentationContext.Layout.cornerRadius
        )

        sideNotch
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // 玻璃本身点不中。无论是否走液态玻璃，都要垫一层命中区域。
                shape.fill(.black.opacity(0.001))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: Self.dragThreshold)
                    .onChanged { value in
                        let mouseLocation = NSEvent.mouseLocation
                        let startLocation = dragStartMouseLocation ?? mouseLocation
                        if dragStartMouseLocation == nil {
                            dragStartMouseLocation = startLocation
                            draggedAppID = app(at: value.startLocation)?.id
                        }

                        let app = draggedAppID.flatMap { id in
                            context.apps.first { $0.id == id }
                        }
                        let inwardDistance = SideDockDragResolver.inwardDistance(
                            edge: context.edge,
                            startLocation: startLocation,
                            currentLocation: mouseLocation
                        )
                        let alongEdgeTravel = SideDockDragResolver.alongEdgeTravel(
                            edge: context.edge,
                            startLocation: startLocation,
                            currentLocation: mouseLocation
                        )
                        closeProgress = SideDockDragResolver.closeProgress(
                            inwardDistance: inwardDistance,
                            alongEdgeTravel: alongEdgeTravel
                        )
                        onDragChange(
                            SideDockDragUpdate(
                                mouseLocation: mouseLocation,
                                inwardDistance: inwardDistance,
                                alongEdgeTravel: alongEdgeTravel,
                                app: app
                            )
                        )
                    }
                    .onEnded { _ in
                        onDragEnd()
                        dragStartMouseLocation = nil
                        withAnimation(.easeOut(duration: 0.16)) {
                            draggedAppID = nil
                            closeProgress = 0
                        }
                    }
            )
            .coordinateSpace(name: SideDockCoordinateSpace.name)
            .onPreferenceChange(SideDockIconFramePreferenceKey.self) { frames in
                iconFrames = frames
            }
            .clipped()
            // 玻璃必须放在所有影响外观的修饰符之后；再 clip 会把贴边外形裁回矩形。
            .modifier(SideDockGlassModifier(shape: shape))
            // 非激活浮层上的第一次按下默认只用来激活窗口；图标必须能直接点开。
            .allowsWindowActivationEvents()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("已收起的网页应用，可拖动调整位置")
            .containerBackground(.clear, for: .window)
            .onChange(of: context.edge) { _, _ in
                dragStartMouseLocation = NSEvent.mouseLocation
                closeProgress = 0
            }
    }

    private var sideNotch: some View {
        iconRow
            .padding(
                context.edge.isSide
                    ? .vertical : .horizontal,
                SideDockPresentationContext.Layout.verticalPadding
            )
            .padding(
                context.edge.isSide ? .top : .leading,
                SideDockPresentationContext.Layout.edgeTransitionDepth
            )
            .padding(
                context.edge.isSide ? .bottom : .trailing,
                SideDockPresentationContext.Layout.edgeTransitionDepth
            )
    }

    private var iconRow: some View {
        // 图标放得下时不套滚动容器：滚动视图会吃掉整块 Dock 的拖动手势。
        Group {
            if context.layout.shouldScroll {
                ScrollView(
                    context.edge.isSide ? .vertical : .horizontal,
                    showsIndicators: false
                ) {
                    iconStack
                }
                .scrollClipDisabled()
            } else {
                iconStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconStack: some View {
        Group {
            if context.edge.isSide {
                VStack(spacing: SideDockPresentationContext.Layout.iconSpacing) {
                    iconList
                }
            } else {
                HStack(spacing: SideDockPresentationContext.Layout.iconSpacing) {
                    iconList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconList: some View {
        ForEach(context.apps) { app in
            iconButton(for: app)
        }
    }

    private func app(at location: CGPoint) -> WebAppDefinition? {
        context.apps.first { app in
            iconFrames[app.id]?.contains(location) == true
        }
    }

    private func iconButton(for app: WebAppDefinition) -> some View {
        let isDragTarget = draggedAppID == app.id
        let scale = isDragTarget ? 1 - (0.16 * closeProgress) : 1
        let opacity = isDragTarget ? 1 - (0.58 * closeProgress) : 1

        return Button {
            onSelectApp(app)
        } label: {
            iconLabel(for: app)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .buttonStyle(.plain)
        .allowsWindowActivationEvents()
        .focusEffectDisabled()
        .help(app.name)
        .accessibilityLabel(app.name)
        .background {
            iconFrameReader(for: app)
        }
    }

    /// 小于这个位移不当整块拖动，避免触控板单击的抖动把点开吃掉。
    private static let dragThreshold: CGFloat = 8

    private func iconLabel(for app: WebAppDefinition) -> some View {
        WebAppIconView(
            app: app,
            size: SideDockPresentationContext.Layout.iconSize,
            font: .system(size: 13, weight: .semibold)
        )
        // Soft edge shadow so light/white favicons stay readable on liquid glass.
        .shadow(color: .black.opacity(0.28), radius: 1.25, x: 0, y: 0.5)
        .shadow(color: .black.opacity(0.14), radius: 2.5, x: 0, y: 1)
        .frame(
            width: SideDockPresentationContext.Layout.iconSlotSize,
            height: SideDockPresentationContext.Layout.iconSlotSize
        )
    }

    private func iconFrameReader(for app: WebAppDefinition) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SideDockIconFramePreferenceKey.self,
                value: [
                    app.id: proxy.frame(in: .named(SideDockCoordinateSpace.name))
                ]
            )
        }
    }
}

/// Dock 底板：macOS 26 起把通透液态玻璃套在整块内容上，贴边外形由形状参数决定；
/// 旧系统仍画原来的纯黑底板。两条路径共用同一套贴边形状。
///
/// 不要把 `glassEffect` 套在 `Shape.fill` 上：那样玻璃会按视图的矩形包围盒
/// 走默认胶囊，屏幕上就是一块浅色圆角矩形，贴边外形丢失。
private struct SideDockGlassModifier: ViewModifier {
    let shape: EdgeAttachedShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background {
                shape
                    .fill(.black)
                    .overlay {
                        shape.stroke(.white.opacity(0.06), lineWidth: 1)
                    }
            }
        }
    }
}

struct SideDockDragUpdate {
    let mouseLocation: CGPoint
    let inwardDistance: CGFloat
    let alongEdgeTravel: CGFloat
    let app: WebAppDefinition?
}

private enum SideDockCoordinateSpace {
    static let name = "侧边刘海"
}

private struct SideDockIconFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
