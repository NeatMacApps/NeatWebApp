import AppKit
import SwiftUI

struct BrowserContainerView: View {
    let session: BrowserSession

    var body: some View {
        let theme = session.chromeTheme

        VStack(spacing: 0) {
            BrowserWindowDragBar(session: session)

            BrowserWebView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.pageColor.color)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct BrowserWindowDragBar: View {
    let session: BrowserSession

    var body: some View {
        let theme = session.chromeTheme

        return ZStack {
            WindowDragHandle(onDoubleClick: session.collapseWindow)

            Text(session.definition.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.foregroundColor.color.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 84)
                .allowsHitTesting(false)

            HStack {
                BrowserChromeButton(
                    systemImage: "xmark",
                    foregroundStyle: theme.foregroundColor.color.opacity(0.82),
                    highlightedFillStyle: theme.highlightedFillColor.color,
                    action: session.closeWindow
                )
                .help("Close Window")

                BrowserChromeButton(
                    systemImage: "circle.dashed",
                    foregroundStyle: theme.foregroundColor.color.opacity(0.82),
                    highlightedFillStyle: theme.highlightedFillColor.color,
                    action: session.collapseWindow
                )
                .help("Collapse to Floating Icon")

                BrowserChromeButton(
                    systemImage: session.isPinned ? "pin.fill" : "pin",
                    foregroundStyle: theme.foregroundColor.color.opacity(session.isPinned ? 1 : 0.82),
                    highlightedFillStyle: theme.highlightedFillColor.color,
                    isHighlighted: session.isPinned,
                    action: session.togglePinned
                )
                .help(session.isPinned ? "Disable Always on Top" : "Enable Always on Top")

                Spacer()

                BrowserChromeButton(
                    systemImage: "arrow.clockwise",
                    foregroundStyle: theme.foregroundColor.color.opacity(0.82),
                    highlightedFillStyle: theme.highlightedFillColor.color,
                    action: session.reloadFromConfiguredURL
                )
                .help("Reset to Configured URL and Refresh")

                BrowserChromeButton(
                    systemImage: session.isMobileUA ? "laptopcomputer" : "iphone",
                    foregroundStyle: theme.foregroundColor.color.opacity(0.82),
                    highlightedFillStyle: theme.highlightedFillColor.color,
                    action: session.toggleUA
                )
                .help(session.isMobileUA ? "Switch to Desktop UA" : "Switch to Mobile UA")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 24)
        .background(theme.barBottomColor.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.dividerColor.color)
                .frame(height: 0.5)
        }
    }
}

private struct BrowserChromeButton: View {
    let systemImage: String
    let foregroundStyle: Color
    let highlightedFillStyle: Color
    var isHighlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHighlighted ? highlightedFillStyle : .clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class WindowDragHandleView: NSView {
    var onDoubleClick: (() -> Void)?

    override var isOpaque: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        window?.performDrag(with: event)
    }
}
