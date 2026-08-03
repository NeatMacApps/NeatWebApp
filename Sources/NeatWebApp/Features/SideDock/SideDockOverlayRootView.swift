import AppKit
import SwiftUI

struct SideDockOverlayRootView: View {
    @State private var iconFrames: [String: CGRect] = [:]
    @State private var draggedAppID: String?
    @State private var dragStartMouseLocation: CGPoint?
    @State private var closeProgress: CGFloat = 0

    let context: SideDockPresentationContext
    let onSelectApp: (WebAppDefinition) -> Void
    let onDragChange: (SideDockDragUpdate) -> Void
    let onDragEnd: () -> Void

    var body: some View {
        sideNotch
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                SideDockGlassBackground(edge: context.edge.attachedShapeEdge)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
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
                        let verticalTravel = SideDockDragResolver.verticalTravel(
                            startLocation: startLocation,
                            currentLocation: mouseLocation
                        )
                        closeProgress = SideDockDragResolver.closeProgress(
                            inwardDistance: inwardDistance,
                            verticalTravel: verticalTravel
                        )
                        onDragChange(
                            SideDockDragUpdate(
                                mouseLocation: mouseLocation,
                                inwardDistance: inwardDistance,
                                verticalTravel: verticalTravel,
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("已收起的网页应用，可拖动调整位置")
    }

    private var sideNotch: some View {
        iconColumn
        .padding(.vertical, SideDockPresentationContext.Layout.verticalPadding)
        .padding(.top, SideDockPresentationContext.Layout.edgeTransitionDepth)
        .padding(.bottom, SideDockPresentationContext.Layout.edgeTransitionDepth)
    }

    private var iconColumn: some View {
        // 图标放得下时不套滚动容器：滚动视图会吃掉整块 Dock 的拖动手势。
        Group {
            if context.layout.shouldScroll {
                ScrollView(.vertical, showsIndicators: false) {
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
        VStack(spacing: SideDockPresentationContext.Layout.iconSpacing) {
            ForEach(context.apps) { app in
                iconButton(for: app)
            }
        }
        .frame(maxWidth: .infinity)
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
        .focusEffectDisabled()
        .help(app.name)
        .accessibilityLabel(app.name)
        .background {
            iconFrameReader(for: app)
        }
    }

    private func iconLabel(for app: WebAppDefinition) -> some View {
        WebAppIconView(
            app: app,
            size: SideDockPresentationContext.Layout.iconSize,
            font: .system(size: 13, weight: .semibold)
        )
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

/// Dock 底板：macOS 26 起走系统液态玻璃，旧系统退回原来的纯黑底板。
private struct SideDockGlassBackground: View {
    let edge: ScreenAttachedEdge

    var body: some View {
        if #available(macOS 26.0, *) {
            // 玻璃本身不给窗口留下不透明像素，系统会判定这块区域可穿透、
            // 把按下事件直接交给下层窗口，整块 Dock 就只有图标能拖。
            // 补一层肉眼不可见的实色兜住命中区域。
            shape
                .fill(.black.opacity(0.001))
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.black)
                .overlay {
                    shape.stroke(.white.opacity(0.06), lineWidth: 1)
                }
        }
    }

    private var shape: EdgeAttachedShape {
        EdgeAttachedShape(
            edge: edge,
            cornerRadius: SideDockPresentationContext.Layout.cornerRadius
        )
    }
}

struct SideDockDragUpdate {
    let mouseLocation: CGPoint
    let inwardDistance: CGFloat
    let verticalTravel: CGFloat
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
