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

                HStack(spacing: BrowserChromeLayout.buttonSpacing) {
                    BrowserDownloadControl(session: session, theme: theme)
                    BrowserMoreActionsControl(session: session, theme: theme)
                }
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
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        BrowserNativeActionsMenu(theme: theme, entries: entries)
            .frame(width: BrowserChromeLayout.buttonSize, height: BrowserChromeLayout.buttonSize)
            .background {
                Circle()
                    .fill(isHovered ? theme.highlightedFillColor.color : .clear)
            }
            .onHover { isHovered = $0 }
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .overlay(alignment: .topTrailing) {
                if session.isPickingElement {
                    Circle()
                        .fill(theme.foregroundColor.color)
                        .frame(width: 4, height: 4)
                        .allowsHitTesting(false)
                }
            }
        .popover(item: $presentedPanel, arrowEdge: .bottom) { panel in
            switch panel {
            case .bookmarks:
                BrowserBookmarkListPanel(session: session) { presentedPanel = nil }
            case .elementHiding:
                BrowserElementHidingPanel(session: session) { presentedPanel = nil }
            }
        }
    }

    private var entries: [BrowserMenuEntry] {
        [
            .action(localized("browser.chrome.bookmark.list"), "bookmark", true, { presentedPanel = .bookmarks }),
            .action(localized(session.isPickingElement ? "browser.element_hiding.exit" : "browser.element_hiding.enter"), "wand.and.sparkles", true, toggleElementHiding),
            .separator,
            .action(localized("browser.chrome.reload"), "arrow.clockwise", true, session.reload),
            .action(localized(session.isMobileUA ? "browser.chrome.user_agent.desktop" : "browser.chrome.user_agent.mobile"), session.isMobileUA ? "laptopcomputer" : "iphone", true, session.toggleUA)
        ]
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

private enum BrowserMenuEntry {
    case separator
    case action(String, String, Bool, @MainActor () -> Void)
}

@MainActor
private struct BrowserNativeActionsMenu: NSViewRepresentable {
    let theme: BrowserChromeTheme
    let entries: [BrowserMenuEntry]

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.preferredEdge = .maxY
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.image = kebabImage()
        menu.addItem(titleItem)

        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .action(title, symbol, isEnabled, action):
                let handler = ActionHandler(action: action)
                let item = NSMenuItem(title: title, action: #selector(ActionHandler.performAction), keyEquivalent: "")
                item.target = handler
                item.representedObject = handler
                item.isEnabled = isEnabled
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.image?.size = NSSize(width: 16, height: 16)
                if #available(macOS 27.0, *) {
                    item.preferredImageVisibility = .visible
                }
                menu.addItem(item)
            }
        }

        button.menu = menu
        button.contentTintColor = theme.foregroundColor.nsColor.withAlphaComponent(0.82)
        button.toolTip = localized("browser.chrome.more")
        button.setAccessibilityLabel(localized("browser.chrome.more"))
    }

    private func kebabImage() -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: BrowserChromeLayout.iconFontSize, weight: .semibold)) else {
            return nil
        }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: 90)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            let symbolRect = NSRect(
                x: (rect.width - symbol.size.width) / 2,
                y: (rect.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
            return true
        }
        image.isTemplate = true
        return image
    }

    @MainActor
    private final class ActionHandler: NSObject {
        let action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

/// 收藏列表：只展示当前这个网页应用里收藏过的页面。
private struct BrowserBookmarkListPanel: View {
    let session: BrowserSession
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("browser.chrome.bookmark.list")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .focusEffectDisabled()
                .accessibilityLabel(Text("browser.bookmark.close"))
            }

            if session.bookmarks.isEmpty {
                Text("browser.bookmark.empty")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.bookmarks) { bookmark in
                            BrowserBookmarkRow(bookmark: bookmark, session: session, dismiss: dismiss)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if session.isCreatingBookmarkWebApp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("browser.bookmark.adding")
                }
                .font(.system(size: 11))
            } else if let notice = session.bookmarkCreationNotice {
                Text(verbatim: notice)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

/// Native row actions and an inline title editor keep the bookmark list in place.
private struct BrowserBookmarkRow: View {
    let bookmark: WebAppBookmark
    let session: BrowserSession
    let dismiss: () -> Void
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRenaming {
                VStack(alignment: .leading, spacing: 1) {
                    TextField("browser.bookmark.name", text: $draftTitle)
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .task { isNameFocused = true }
                        .focusEffectDisabled()
                        .onSubmit { finishRename() }
                        .onExitCommand { finishRename(cancel: true) }
                    host
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { finishRename() } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Text("browser.bookmark.rename"))
            } else {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: bookmark.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        host
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(Text("browser.bookmark.open"))
            }

            Button {
                if isRenaming {
                    finishRename(cancel: true)
                } else {
                    session.removeBookmark(id: bookmark.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .help(Text(LocalizedStringKey(isRenaming ? "common.cancel" : "browser.bookmark.delete")))
            .accessibilityLabel(Text(LocalizedStringKey(isRenaming ? "common.cancel" : "browser.bookmark.delete")))
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: open) {
                Label("browser.bookmark.open", systemImage: "arrow.up.right")
            }
            RenameButton()
            Button {
                Task { await session.createWebApp(from: bookmark) }
            } label: {
                Label("browser.bookmark.add_webapp", systemImage: "plus.app")
            }
            .disabled(session.isCreatingBookmarkWebApp || session.createdBookmarkIDs.contains(bookmark.id))
            Divider()
            Button(role: .destructive) { session.removeBookmark(id: bookmark.id) } label: {
                Label("browser.bookmark.delete", systemImage: "trash")
            }
        }
        .renameAction {
            draftTitle = bookmark.title
            isRenaming = true
            isNameFocused = true
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused, isRenaming { finishRename() }
        }
    }

    private var host: some View {
        Text(verbatim: bookmark.displayHost)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private func open() {
        session.openBookmark(bookmark)
        dismiss()
    }

    private func finishRename(cancel: Bool = false) {
        if !cancel {
            session.renameBookmark(id: bookmark.id, title: draftTitle)
        }
        isRenaming = false
        isNameFocused = false
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
