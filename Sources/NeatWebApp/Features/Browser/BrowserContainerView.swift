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

private typealias BrowserChromeLayout = BrowserChromeMetrics

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
                        accessibilityLabel: localized("browser.chrome.collapse"),
                        action: session.collapseWindow
                    )
                    .help(Text("browser.chrome.collapse"))

                    BrowserChromeButton(
                        systemImage: session.isPinned ? "pin.fill" : "pin",
                        theme: theme,
                        isHighlighted: session.isPinned,
                        accessibilityLabel: localized(session.isPinned ? "browser.chrome.unpin" : "browser.chrome.pin"),
                        action: session.togglePinned
                    )
                    .help(Text(LocalizedStringKey(session.isPinned ? "browser.chrome.unpin" : "browser.chrome.pin")))

                    BrowserChromeButton(
                        systemImage: session.isCurrentPageBookmarked ? "star.fill" : "star",
                        theme: theme,
                        isHighlighted: session.isCurrentPageBookmarked,
                        accessibilityLabel: localized(session.isCurrentPageBookmarked ? "browser.chrome.bookmark.remove" : "browser.chrome.bookmark.add"),
                        action: session.toggleCurrentPageBookmark
                    )
                    .help(Text(LocalizedStringKey(session.isCurrentPageBookmarked ? "browser.chrome.bookmark.remove" : "browser.chrome.bookmark.add")))
                    .disabled(!session.canBookmarkCurrentPage)

                }

                Spacer(minLength: 0)

                BrowserMoreActionsControl(session: session, theme: theme)
            }
            .padding(.horizontal, BrowserChromeLayout.windowMargin)
        }
        .frame(height: BrowserChromeLayout.bandHeight)
    }
}

private struct BrowserMoreActionsControl: View {
    let session: BrowserSession
    let theme: BrowserChromeTheme

    private enum Panel: String, Identifiable {
        case bookmarks
        case elementHiding

        var id: String { rawValue }
    }

    @State private var presentedPanel: Panel?

    var body: some View {
        Menu {
            Button {
                presentedPanel = .bookmarks
            } label: {
                Label("browser.chrome.bookmark.list", systemImage: "bookmark")
            }

            Button(action: toggleElementHiding) {
                Label(
                    LocalizedStringKey(session.isPickingElement ? "browser.element_hiding.exit" : "browser.element_hiding.enter"),
                    systemImage: "wand.and.sparkles"
                )
            }

            Divider()

            Button(action: session.reload) {
                Label("browser.chrome.reload", systemImage: "arrow.clockwise")
            }

            Button(action: session.toggleUA) {
                Label(
                    LocalizedStringKey(session.isMobileUA ? "browser.chrome.user_agent.desktop" : "browser.chrome.user_agent.mobile"),
                    systemImage: session.isMobileUA ? "laptopcomputer" : "iphone"
                )
            }

            BrowserDownloadMenuItems(session: session)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: BrowserChromeLayout.iconFontSize, weight: .semibold))
                .rotationEffect(.degrees(90))
                .foregroundStyle(theme.foregroundColor.color.opacity(0.82))
                .frame(width: BrowserChromeLayout.buttonSize, height: BrowserChromeLayout.buttonSize)
                .overlay(alignment: .topTrailing) {
                    if !session.downloadItems.isEmpty || session.isPickingElement {
                        Circle()
                            .fill(theme.foregroundColor.color)
                            .frame(width: 4, height: 4)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusEffectDisabled()
        .help(Text("browser.chrome.more"))
        .accessibilityLabel(localized("browser.chrome.more"))
        .popover(item: $presentedPanel, arrowEdge: .bottom) { panel in
            switch panel {
            case .bookmarks:
                BrowserBookmarkListPanel(session: session) { presentedPanel = nil }
            case .elementHiding:
                BrowserElementHidingPanel(session: session) { presentedPanel = nil }
            }
        }
    }

    private func toggleElementHiding() {
        if session.isPickingElement {
            session.cancelElementPicking()
            return
        }

        session.elementHidingNotice = nil
        presentedPanel = .elementHiding
    }
}

private struct BrowserDownloadMenuItems: View {
    let session: BrowserSession

    var body: some View {
        if let latestDownload = session.downloadItems.first {
            Divider()

            Button(action: session.revealLatestDownload) {
                Label(title(for: latestDownload), systemImage: iconName(for: latestDownload.phase))
            }
            .disabled(latestDownload.destinationURL == nil)
            .help(helpText(for: latestDownload))
            .accessibilityLabel(String(format: localized("browser.download.accessibility.label"), title(for: latestDownload)))
            .accessibilityHint(helpText(for: latestDownload))

            if isDismissible(latestDownload) {
                Button {
                    session.clearDownload(id: latestDownload.id)
                } label: {
                    Label("browser.download.dismiss", systemImage: "xmark")
                }
            }
        }
    }

    private func isDismissible(_ item: BrowserDownloadItem) -> Bool {
        item.phase != .running
    }

    private func title(for item: BrowserDownloadItem) -> String {
        switch item.phase {
        case .running:
            let activeCount = session.downloadItems.filter { $0.phase == .running }.count
            if activeCount > 1 {
                return String(format: localized("browser.download.status.multiple"), activeCount)
            }
            if let fractionCompleted = item.fractionCompleted, fractionCompleted > 0, fractionCompleted < 1 {
                return String(format: localized("browser.download.status.progress"), Int(fractionCompleted * 100))
            }
            return localized("browser.download.status.running")
        case .completed:
            return localized("browser.download.status.completed")
        case .failed:
            return localized("browser.download.status.failed")
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
            return String(format: localized("browser.download.help.running"), item.filename)
        case .completed:
            return String(format: localized("browser.download.help.reveal"), item.filename)
        case .failed:
            return item.message ?? localized("browser.download.status.failed")
        }
    }
}

/// 收藏列表：只展示当前这个网页应用里收藏过的页面。
private struct BrowserBookmarkListPanel: View {
    let session: BrowserSession
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("browser.chrome.bookmark.list")
                .font(.system(size: 12, weight: .semibold))

            if session.bookmarks.isEmpty {
                Text("browser.bookmark.empty")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.bookmarks) { bookmark in
                            HStack(spacing: 8) {
                                Button {
                                    session.openBookmark(bookmark)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: bookmark.title)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)

                                        Text(verbatim: bookmark.displayHost)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                .help(Text("browser.bookmark.open"))

                                Button {
                                    session.removeBookmark(id: bookmark.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(.borderless)
                                .focusEffectDisabled()
                                .help(Text("browser.bookmark.delete"))
                                .accessibilityLabel(localized("browser.bookmark.delete"))
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

/// 魔法棒：进入"点一下就隐藏"的挑选模式，以及还原这个网页应用已经隐藏掉的元素。
private struct BrowserElementHidingPanel: View {
    let session: BrowserSession
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: startPicking) {
                Label("browser.element_hiding.pick", systemImage: "wand.and.sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focusEffectDisabled()

            if let notice = session.elementHidingNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if session.hiddenElementRules.isEmpty {
                Text("browser.element_hiding.empty")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        section(title: "browser.element_hiding.section.current", rules: session.hiddenElementRulesForCurrentSite, showsHost: false)
                        section(title: "browser.element_hiding.section.other", rules: session.hiddenElementRulesForOtherSites, showsHost: true)
                    }
                }
                .frame(maxHeight: 220)

                Button("browser.element_hiding.restore_all", action: session.restoreAllHiddenElements)
                    .font(.system(size: 11))
                    .buttonStyle(.link)
                    .focusEffectDisabled()
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    @ViewBuilder
    private func section(title: String, rules: [HiddenElementRule], showsHost: Bool) -> some View {
        if !rules.isEmpty {
            Text(LocalizedStringKey(title))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            ForEach(rules) { rule in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.label)
                            .font(.system(size: 11))
                            .lineLimit(1)

                        if showsHost {
                            Text(rule.host)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        session.restoreHiddenElement(id: rule.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .focusEffectDisabled()
                    .help(Text("browser.element_hiding.restore"))
                }
            }
        }
    }

    private func startPicking() {
        dismiss()
        session.beginElementPicking()
    }
}

private func localized(_ key: String) -> String {
    String(localized: LocalizedStringResource(stringLiteral: key))
}

private struct BrowserChromeButton: View {
    let systemImage: String
    let theme: BrowserChromeTheme
    var isHighlighted = false
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: BrowserChromeLayout.iconFontSize, weight: .semibold))
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
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(accessibilityLabel)
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
