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
                    .help(Text(session.isPinned ? "browser.chrome.unpin" : "browser.chrome.pin"))

                    BrowserChromeButton(
                        systemImage: session.isCurrentPageBookmarked ? "star.fill" : "star",
                        theme: theme,
                        isHighlighted: session.isCurrentPageBookmarked,
                        accessibilityLabel: localized(session.isCurrentPageBookmarked ? "browser.chrome.bookmark.remove" : "browser.chrome.bookmark.add"),
                        action: session.toggleCurrentPageBookmark
                    )
                    .help(Text(session.isCurrentPageBookmarked ? "browser.chrome.bookmark.remove" : "browser.chrome.bookmark.add"))
                    .disabled(!session.canBookmarkCurrentPage)

                    BrowserBookmarkListControl(session: session, theme: theme)
                }

                Spacer(minLength: 0)

                HStack(spacing: BrowserChromeLayout.buttonSpacing) {
                    BrowserDownloadIndicator(session: session, theme: theme)

                    BrowserElementHidingControl(session: session, theme: theme)

                    BrowserChromeButton(
                        systemImage: "arrow.clockwise",
                        theme: theme,
                        accessibilityLabel: localized("browser.chrome.reload"),
                        action: session.reload
                    )
                    .help(Text("browser.chrome.reload"))

                    BrowserChromeButton(
                        systemImage: session.isMobileUA ? "laptopcomputer" : "iphone",
                        theme: theme,
                        accessibilityLabel: localized(session.isMobileUA ? "browser.chrome.user_agent.desktop" : "browser.chrome.user_agent.mobile"),
                        action: session.toggleUA
                    )
                    .help(Text(session.isMobileUA ? "browser.chrome.user_agent.desktop" : "browser.chrome.user_agent.mobile"))
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
    @FocusState private var isFocused: Bool

    var body: some View {
        if let latestDownload = session.downloadItems.first {
            HStack(spacing: 0) {
                Button(action: session.revealLatestDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: iconName(for: latestDownload.phase))
                            .font(.system(size: 10, weight: .semibold))

                        Text(title(for: latestDownload))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.foregroundColor.color.opacity(0.88))
                    .padding(.leading, 7)
                    .padding(.trailing, isDismissible(latestDownload) ? 6 : 7)
                    .frame(height: BrowserChromeLayout.buttonSize)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($isFocused)
                .disabled(latestDownload.destinationURL == nil)
                .help(helpText(for: latestDownload))
                .accessibilityLabel(String(format: localized("browser.download.accessibility.label"), title(for: latestDownload)))
                .accessibilityHint(helpText(for: latestDownload))

                if isDismissible(latestDownload) {
                    Rectangle()
                        .fill(theme.foregroundColor.color.opacity(0.2))
                        .frame(width: 1, height: 12)

                    Button {
                        session.clearDownload(id: latestDownload.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.foregroundColor.color.opacity(0.72))
                            .frame(width: BrowserChromeLayout.buttonSize, height: BrowserChromeLayout.buttonSize)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help(Text("browser.download.dismiss"))
                    .accessibilityLabel(localized("browser.download.dismiss"))
                }
            }
            .background(
                Capsule(style: .continuous)
                    .fill(theme.highlightedFillColor.color)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(theme.foregroundColor.color.opacity(isFocused ? 0.8 : 0), lineWidth: 2)
                    .padding(-2)
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
private struct BrowserBookmarkListControl: View {
    let session: BrowserSession
    let theme: BrowserChromeTheme

    @State private var isPanelPresented = false

    var body: some View {
        BrowserChromeButton(
            systemImage: "list.bullet.rectangle",
            theme: theme,
            isHighlighted: isPanelPresented,
            accessibilityLabel: localized("browser.chrome.bookmark.list"),
            action: { isPanelPresented = true }
        )
        .help(Text("browser.chrome.bookmark.list"))
        .popover(isPresented: $isPanelPresented, arrowEdge: .bottom) {
            BrowserBookmarkListPanel(session: session) {
                isPanelPresented = false
            }
        }
    }
}

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
private struct BrowserElementHidingControl: View {
    let session: BrowserSession
    let theme: BrowserChromeTheme

    @State private var isPanelPresented = false

    var body: some View {
        BrowserChromeButton(
            systemImage: "wand.and.sparkles",
            theme: theme,
            isHighlighted: session.isPickingElement,
            accessibilityLabel: localized(session.isPickingElement ? "browser.element_hiding.exit" : "browser.element_hiding.enter"),
            action: toggle
        )
        .help(Text(session.isPickingElement ? "browser.element_hiding.exit.help" : "browser.element_hiding.enter"))
        .popover(isPresented: $isPanelPresented, arrowEdge: .bottom) {
            BrowserElementHidingPanel(session: session) {
                isPanelPresented = false
            }
        }
    }

    private func toggle() {
        // 已经在挑选中时，再点一次就是"算了"，不必先弹面板。
        if session.isPickingElement {
            session.cancelElementPicking()
            return
        }

        session.elementHidingNotice = nil
        isPanelPresented = true
    }
}

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
    @FocusState private var isFocused: Bool
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
                .overlay {
                    Circle()
                        .stroke(theme.foregroundColor.color.opacity(isFocused ? 0.8 : 0), lineWidth: 2)
                        .padding(-2)
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($isFocused)
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
