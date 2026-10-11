import AppKit
import SwiftUI

struct SideDockOverlayRootView: View {
    @Environment(AppModel.self) private var appModel
    var state: SideDockOverlayState
    let onSelectApp: (WebAppDefinition) -> Void

    private var context: SideDockPresentationContext { state.context }

    var body: some View {
        let shape = Capsule()
        dockContent
            .padding(SideDockPresentationContext.Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clear glass needs a visible-shape hit surface for the native window drag.
            .background { shape.fill(.black.opacity(0.001)) }
            .contentShape(shape)
            .clipped()
            .modifier(SideDockGlassModifier(shape: shape))
            .allowsWindowActivationEvents()
            .disabled(state.isDragging)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "sidedock.collapsed_hint"))
            .containerBackground(.clear, for: .window)
    }

    private var dockContent: some View {
        Group {
            if context.edge.isSide {
                VStack(spacing: SideDockPresentationContext.Layout.iconSpacing) {
                    dragGrip
                    iconRow
                }
            } else {
                HStack(spacing: SideDockPresentationContext.Layout.iconSpacing) {
                    dragGrip
                    iconRow
                }
            }
        }
    }

    private var dragGrip: some View {
        HStack(spacing: 4) {
            ForEach(0..<2) { _ in
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .frame(width: 4, height: 18)
            }
        }
        .foregroundStyle(.primary)
        .shadow(color: Color(nsColor: .textBackgroundColor).opacity(0.9), radius: 0.7)
        .frame(width: context.edge.isSide
               ? SideDockPresentationContext.Layout.iconSlotSize
               : SideDockPresentationContext.Layout.horizontalGripLength,
               height: context.edge.isSide
               ? SideDockPresentationContext.Layout.verticalGripLength
               : SideDockPresentationContext.Layout.iconSlotSize)
        .contentShape(Rectangle())
        .help(String(localized: "sidedock.drag"))
        .accessibilityHidden(true)
        .onHover { isHovering in
            guard !state.isDragging else { return }
            if isHovering {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private var iconRow: some View {
        Group {
            if context.layout.shouldScroll {
                ScrollView(context.edge.isSide ? .vertical : .horizontal, showsIndicators: false) {
                    iconStack
                }
            } else {
                iconStack
            }
        }
    }

    private var iconStack: some View {
        Group {
            if context.edge.isSide {
                VStack(spacing: SideDockPresentationContext.Layout.iconSpacing) { iconList }
            } else {
                HStack(spacing: SideDockPresentationContext.Layout.iconSpacing) { iconList }
            }
        }
    }

    private var iconList: some View {
        ForEach(context.apps) { app in
            Button { onSelectApp(app) } label: {
                WebAppIconView(
                    app: app,
                    size: SideDockPresentationContext.Layout.iconSize,
                    font: .system(size: 13, weight: .semibold),
                    favicon: appModel.faviconImage(for: app),
                    loadFavicon: { appModel.ensureFaviconLoaded(for: app) }
                )
                .shadow(color: .black.opacity(0.28), radius: 1.25, x: 0, y: 0.5)
                .shadow(color: .black.opacity(0.14), radius: 2.5, x: 0, y: 1)
                .frame(width: SideDockPresentationContext.Layout.iconSlotSize,
                       height: SideDockPresentationContext.Layout.iconSlotSize)
            }
            .buttonStyle(.plain)
            .allowsWindowActivationEvents()
            .focusEffectDisabled()
            .help(app.name)
            .accessibilityLabel(app.name)
            .contextMenu {
                Button(role: .destructive) { appModel.closeCollapsedWebApp(app) } label: {
                    Label("sidedock.quit_app", systemImage: "xmark")
                }
            }
        }
    }
}

private struct SideDockGlassModifier: ViewModifier {
    let shape: Capsule

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background {
                shape.fill(.black)
                    .overlay { shape.stroke(.white.opacity(0.06), lineWidth: 1) }
            }
        }
    }
}
