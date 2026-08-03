import AppKit
import SwiftUI

struct BrowserContainerView: View {
    let session: BrowserSession

    var body: some View {
        let theme = session.chromeTheme

        VStack(spacing: 0) {
            BrowserChromeBand(session: session)

            BrowserWebView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.pageColor.color)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private enum BrowserChromeLayout {
    static let bandHeight: CGFloat = 40
    static let windowMargin: CGFloat = 10
    static let buttonSize: CGFloat = 24
    static let buttonSpacing: CGFloat = 2
}

/// 顶部让位带：整条只铺网页自己的背景色、不画分割线，所以看不出是一条独立的横条；
/// 网页内容从带子下方开始，永远不会被两组悬浮按钮盖住。
private struct BrowserChromeBand: View {
    let session: BrowserSession

    var body: some View {
        let theme = session.chromeTheme

        ZStack {
            // 让位带里没有任何网页内容，整条都可以拿来拖动窗口。
            WindowDragHandle()

            // 顶部渐变：越往下越透明，和网页背景无缝接上，不会出现一条有边界的横条。
            LinearGradient(
                colors: [theme.chromeScrimColor.color, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                HStack(spacing: BrowserChromeLayout.buttonSpacing) {
                    BrowserChromeButton(
                        systemImage: "xmark",
                        theme: theme,
                        action: session.collapseWindow
                    )
                    .help("收进侧边刘海")

                    BrowserChromeButton(
                        systemImage: session.isPinned ? "pin.fill" : "pin",
                        theme: theme,
                        isHighlighted: session.isPinned,
                        action: session.togglePinned
                    )
                    .help(session.isPinned ? "取消窗口置顶" : "窗口置顶")
                }

                Spacer(minLength: 0)

                HStack(spacing: BrowserChromeLayout.buttonSpacing) {
                    BrowserDownloadIndicator(session: session, theme: theme)

                    BrowserChromeButton(
                        systemImage: "arrow.clockwise",
                        theme: theme,
                        action: session.reloadFromConfiguredURL
                    )
                    .help("回到配置地址并刷新")

                    BrowserChromeButton(
                        systemImage: session.isMobileUA ? "laptopcomputer" : "iphone",
                        theme: theme,
                        action: session.toggleUA
                    )
                    .help(session.isMobileUA ? "切换为桌面网页标识" : "切换为手机网页标识")
                }
            }
            .padding(.horizontal, BrowserChromeLayout.windowMargin)
        }
        .frame(height: BrowserChromeLayout.bandHeight)
    }
}

private struct BrowserDownloadIndicator: View {
    let session: BrowserSession
    let theme: BrowserChromeTheme

    var body: some View {
        if let latestDownload = session.downloadItems.first {
            Button(action: session.revealLatestDownload) {
                HStack(spacing: 4) {
                    Image(systemName: iconName(for: latestDownload.phase))
                        .font(.system(size: 10, weight: .semibold))

                    Text(title(for: latestDownload))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.foregroundColor.color.opacity(0.88))
                .padding(.horizontal, 7)
                .frame(height: BrowserChromeLayout.buttonSize)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.highlightedFillColor.color)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(latestDownload.destinationURL == nil)
            .help(helpText(for: latestDownload))
        }
    }

    private func title(for item: BrowserDownloadItem) -> String {
        switch item.phase {
        case .running:
            let activeCount = session.downloadItems.filter { $0.phase == .running }.count
            if activeCount > 1 {
                return "下载中 \(activeCount)"
            }
            if let fractionCompleted = item.fractionCompleted, fractionCompleted > 0, fractionCompleted < 1 {
                return "下载中 \(Int(fractionCompleted * 100))%"
            }
            return "下载中"
        case .completed:
            return "下载完成"
        case .failed:
            return "下载失败"
        }
    }

    private func iconName(for phase: BrowserDownloadPhase) -> String {
        switch phase {
        case .running:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private func helpText(for item: BrowserDownloadItem) -> String {
        switch item.phase {
        case .running:
            return "正在下载 \(item.filename)"
        case .completed:
            return "在访达中显示 \(item.filename)"
        case .failed:
            return item.message ?? "下载失败"
        }
    }
}

private struct BrowserChromeButton: View {
    let systemImage: String
    let theme: BrowserChromeTheme
    var isHighlighted = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.foregroundColor.color.opacity(isHighlighted ? 1 : 0.82))
                .frame(width: BrowserChromeLayout.buttonSize, height: BrowserChromeLayout.buttonSize)
                .background {
                    Circle()
                        .fill(
                            isHighlighted || isHovered
                                ? theme.highlightedFillColor.color
                                : .clear
                        )
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    override var isOpaque: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
            return
        }

        window?.performDrag(with: event)
    }
}
