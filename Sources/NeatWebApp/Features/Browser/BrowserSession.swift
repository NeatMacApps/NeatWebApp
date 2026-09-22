import Foundation
import CryptoKit
import Observation
import AppKit
import WebKit

@MainActor
protocol BrowserSessionCommandHandling: AnyObject {
    func browserSessionDidRequestClose(_ session: BrowserSession)
    func browserSessionDidRequestCollapse(_ session: BrowserSession)
}

@Observable
@MainActor
final class BrowserSession {
    private(set) var definition: WebAppDefinition

    var pageTitle: String
    var currentURL: URL
    var chromeTheme = BrowserChromeTheme.fallback
    var downloadItems: [BrowserDownloadItem] = []
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    private(set) var pageZoom: Double
    var isPinned: Bool {
        didSet {
            onPinnedChange?(isPinned)
            persistPreference()
        }
    }
    var isMobileUA: Bool {
        didSet {
            applyUserAgent()
            persistPreference()
        }
    }

    /// 用户手动隐藏掉的元素，按站点归属，跨页面生效。
    private(set) var hiddenElementRules: [HiddenElementRule]
    /// 只属于当前这个网页应用的收藏，不会出现在别的网页应用窗口。
    private(set) var bookmarks: [WebAppBookmark]
    /// 是否正处在"点一下就隐藏"的挑选模式。
    private(set) var isPickingElement = false
    /// 挑选失败时给用户的一句话解释，展示过一次就清掉。
    var elementHidingNotice: String?

    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    @ObservationIgnored
    private let preferencesStore: WebAppPreferencesStore

    @ObservationIgnored
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored
    private weak var webView: WKWebView?

    @ObservationIgnored
    private weak var userContentController: WKUserContentController?

    /// attach 是高频入口：SwiftUI 每次刷新都会调一次。WebKit 的属性设置不是免费的
    /// （跨进程 IPC，甚至触发重排），值没变时必须跳过，否则窗口缩放/任何界面刷新
    /// 都会给内容进程加税。

    @ObservationIgnored
    private var lastAppliedPageZoom: Double?

    @ObservationIgnored
    private var lastAppliedUserAgentIsMobile: Bool?

    @ObservationIgnored
    private var lastAppliedBackgroundColor: BrowserThemeColor?

    @ObservationIgnored
    weak var commandHandler: (any BrowserSessionCommandHandling)?

    @ObservationIgnored
    var onPinnedChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onChromeThemeChange: ((BrowserChromeTheme) -> Void)?

    /// 宿主盖还在时，网页第一帧画完再揭盖。只触发一次。
    @ObservationIgnored
    var onFirstContentPaint: (() -> Void)?

    init(
        definition: WebAppDefinition,
        preference: StoredWebAppPreference,
        preferencesStore: WebAppPreferencesStore
    ) {
        self.definition = definition
        self.pageTitle = definition.name
        self.currentURL = definition.homeURL
        self.pageZoom = preference.pageZoom
        self.isPinned = preference.isPinned
        self.isMobileUA = preference.isMobileUA
        self.hiddenElementRules = preference.resolvedHiddenElements
        self.bookmarks = preference.resolvedBookmarks.sorted { $0.createdAt > $1.createdAt }
        self.preferencesStore = preferencesStore
        self.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.websiteDataStoreIdentifier(for: definition.id))
    }

    func attach(webView: WKWebView) {
        let alreadyAttached = self.webView === webView
        self.webView = webView
        self.userContentController = webView.configuration.userContentController
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        if lastAppliedPageZoom != pageZoom {
            lastAppliedPageZoom = pageZoom
            webView.pageZoom = pageZoom
        }
        if lastAppliedBackgroundColor != chromeTheme.pageColor {
            lastAppliedBackgroundColor = chromeTheme.pageColor
            webView.underPageBackgroundColor = chromeTheme.pageColor.nsColor
        }
        if lastAppliedUserAgentIsMobile != isMobileUA {
            lastAppliedUserAgentIsMobile = isMobileUA
            applyUserAgent()
        }

        if webView.url == nil {
            webView.load(URLRequest(url: currentURL))
        } else if !alreadyAttached {
            syncNavigationState(from: webView)
        }
    }

    func focusWebView() {
        guard let webView, let window = webView.window else {
            return
        }

        guard window.firstResponder !== webView else {
            return
        }

        window.makeFirstResponder(webView)
    }

    func toggleUA() {
        isMobileUA.toggle()
        reload()
    }

    private func applyUserAgent() {
        lastAppliedUserAgentIsMobile = isMobileUA
        webView?.customUserAgent = isMobileUA ? Self.mobileUserAgent : nil
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    /// 绕过缓存重新拉取，对应浏览器里的"硬刷新"。
    func reloadIgnoringCache() {
        webView?.reloadFromOrigin()
    }

    func printPage() {
        guard let webView, let window = webView.window else {
            return
        }

        let printOperation = webView.printOperation(with: NSPrintInfo.shared)
        printOperation.view?.frame = webView.bounds
        printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func goHome() {
        loadConfiguredHomePage()
    }

    func reloadFromConfiguredURL() {
        loadConfiguredHomePage()
    }

    /// 宿主改了这个网页应用的名字或首页地址时，把还在跑的窗口对齐过去。
    /// 只有首页变了才重新打开首页；只改名字不打断用户当前浏览。
    func applyDefinition(_ newDefinition: WebAppDefinition) {
        guard newDefinition.id == definition.id else {
            return
        }

        let previous = definition
        definition = newDefinition

        if previous.homeURL != newDefinition.homeURL {
            loadConfiguredHomePage()
            return
        }

        if pageTitle == previous.name {
            pageTitle = newDefinition.name
        }
    }

    func decreaseZoom() {
        setPageZoom(pageZoom - 0.1)
    }

    func increaseZoom() {
        setPageZoom(pageZoom + 0.1)
    }

    func resetZoom() {
        setPageZoom(1.0)
    }

    func togglePinned() {
        isPinned.toggle()
    }

    // MARK: - 收藏

    var canBookmarkCurrentPage: Bool {
        WebAppBookmark.canonicalURLString(currentURL) != nil
    }

    var isCurrentPageBookmarked: Bool {
        bookmarks.contains { $0.matches(currentURL) }
    }

    func toggleCurrentPageBookmark() {
        guard let canonical = WebAppBookmark.canonicalURLString(currentURL) else {
            return
        }

        if let existing = bookmarks.first(where: { $0.urlString == canonical }) {
            removeBookmark(id: existing.id)
            return
        }

        let trimmedTitle = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.nonEmpty ?? currentURL.host() ?? canonical
        bookmarks.insert(
            WebAppBookmark(title: title, urlString: canonical),
            at: 0
        )
        persistPreference()
    }

    func removeBookmark(id: UUID) {
        let originalCount = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        guard bookmarks.count != originalCount else {
            return
        }

        persistPreference()
    }

    func openBookmark(_ bookmark: WebAppBookmark) {
        guard let url = bookmark.url else {
            return
        }

        currentURL = url
        pageTitle = bookmark.title
        isLoading = true
        webView?.load(URLRequest(url: url))
    }

    // MARK: - 手动隐藏网页元素

    var currentSiteHost: String {
        HiddenElementRule.normalizedHost(currentURL.host())
    }

    /// 当前站点已隐藏的元素，最近隐藏的排在最前。
    var hiddenElementRulesForCurrentSite: [HiddenElementRule] {
        hiddenElementRules
            .filter { $0.host == currentSiteHost }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 其他站点上隐藏的元素——同一个网页应用里跨站跳转很常见，这些也要能还原。
    var hiddenElementRulesForOtherSites: [HiddenElementRule] {
        hiddenElementRules
            .filter { $0.host != currentSiteHost }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func beginElementPicking() {
        guard !currentSiteHost.isEmpty else {
            elementHidingNotice = "当前页面不是普通网页，没法在上面隐藏元素"
            return
        }

        elementHidingNotice = nil
        isPickingElement = true
        focusWebView()
        webView?.evaluateJavaScript(BrowserElementHidingScript.startPickingScript)
    }

    func cancelElementPicking() {
        guard isPickingElement else {
            return
        }

        isPickingElement = false
        webView?.evaluateJavaScript(BrowserElementHidingScript.stopPickingScript)
    }

    func handleElementHidingMessage(_ message: BrowserElementHidingScript.IncomingMessage) {
        switch message {
        case let .picked(selector, label, host):
            isPickingElement = false
            hideElement(selector: selector, label: label, host: host)
        case .cancelled:
            isPickingElement = false
        case .undoLatest:
            restoreMostRecentlyHiddenElement()
        case let .failed(reason):
            isPickingElement = false
            elementHidingNotice = reason
        case let .broad(_, count, label):
            elementHidingNotice = "「\(label)」在本站命中了 \(count) 处，已全部隐藏。若页面看起来不对、越用越卡，去魔法棒里还原最近隐藏的那条"
        }
    }

    func restoreHiddenElement(id: UUID) {
        guard hiddenElementRules.contains(where: { $0.id == id }) else {
            return
        }

        hiddenElementRules.removeAll { $0.id == id }
        commitHiddenElementRules()
    }

    func restoreAllHiddenElements() {
        guard !hiddenElementRules.isEmpty else {
            return
        }

        hiddenElementRules.removeAll()
        commitHiddenElementRules()
    }

    private func hideElement(selector: String, label: String, host: String) {
        let resolvedHost = host.isEmpty ? currentSiteHost : HiddenElementRule.normalizedHost(host)
        guard
            !resolvedHost.isEmpty,
            BrowserElementHidingScript.isUsableSelector(selector)
        else {
            elementHidingNotice = "这个元素没法被稳定定位，换一块试试"
            return
        }

        // 同一块东西点两次不该攒出两条规则。
        guard !hiddenElementRules.contains(where: { $0.host == resolvedHost && $0.selector == selector }) else {
            return
        }

        hiddenElementRules.append(
            HiddenElementRule(host: resolvedHost, selector: selector, label: label)
        )
        commitHiddenElementRules()

        webView?.evaluateJavaScript(BrowserElementHidingScript.undoToastScript(label: label))
        // 刚藏完就数一遍命中数：通用类名超标时页面会主动报 broad，面板里给出还原指引。
        webView?.evaluateJavaScript(
            BrowserElementHidingScript.reportBroadRuleScript(selector: selector, label: label)
        )
    }

    private func restoreMostRecentlyHiddenElement() {
        guard let latest = hiddenElementRules.max(by: { $0.createdAt < $1.createdAt }) else {
            return
        }

        restoreHiddenElement(id: latest.id)
    }

    /// 规则一变就要做三件事：存盘、把已经打开的页面立刻改过来、把后续页面的注入脚本也换掉。
    private func commitHiddenElementRules() {
        persistPreference()

        webView?.evaluateJavaScript(
            BrowserElementHidingScript.applyRulesScript(rules: hiddenElementRules)
        )

        if let userContentController {
            BrowserUserScripts.install(
                into: userContentController,
                hiddenElementRules: hiddenElementRules
            )
        }
    }

    func closeWindow() {
        commandHandler?.browserSessionDidRequestClose(self)
    }

    func collapseWindow() {
        commandHandler?.browserSessionDidRequestCollapse(self)
    }

    @discardableResult
    func startDownload(filename: String) -> UUID {
        let item = BrowserDownloadItem(filename: filename)
        downloadItems.insert(item, at: 0)
        return item.id
    }

    func updateDownload(id: UUID, fractionCompleted: Double?) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadItems[index].fractionCompleted = fractionCompleted
    }

    func updateDownload(id: UUID, filename: String) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadItems[index].filename = filename
    }

    func finishDownload(id: UUID, destinationURL: URL) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadItems[index].phase = .completed
        downloadItems[index].destinationURL = destinationURL
        downloadItems[index].fractionCompleted = 1
    }

    func failDownload(id: UUID, message: String) {
        guard let index = downloadItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloadItems[index].phase = .failed
        downloadItems[index].message = message
    }

    /// 把完成或失败的下载状态从顶栏拿掉，只清界面提示，不删已落盘的文件。
    /// 正在下载的不让关：关掉会像取消下载，但文件其实还在继续写。
    func clearDownload(id: UUID) {
        guard let item = downloadItems.first(where: { $0.id == id }), item.phase != .running else {
            return
        }

        downloadItems.removeAll { $0.id == id }
    }

    func revealLatestDownload() {
        guard let destinationURL = downloadItems.first(where: { $0.destinationURL != nil })?.destinationURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func updateChromeThemeColor(_ pageColor: BrowserThemeColor?) {
        let nextTheme = pageColor.map(BrowserChromeTheme.init(pageColor:)) ?? .fallback
        guard nextTheme != chromeTheme else {
            return
        }

        chromeTheme = nextTheme
        lastAppliedBackgroundColor = nextTheme.pageColor
        webView?.underPageBackgroundColor = nextTheme.pageColor.nsColor
        onChromeThemeChange?(nextTheme)
    }

    func syncNavigationState(from webView: WKWebView) {
        // 页面一换，注入到旧文档里的挑选模式就跟着没了，按钮状态必须复位，
        // 否则魔法棒会一直亮着、再点一次只是"取消"，用户按不出挑选来。
        if isPickingElement, let url = webView.url, url != currentURL {
            isPickingElement = false
        }

        pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? definition.name
        currentURL = webView.url ?? currentURL
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    func consumeFirstContentPaint() {
        let callback = onFirstContentPaint
        onFirstContentPaint = nil
        callback?()
    }

    private func setPageZoom(_ newValue: Double) {
        let clampedZoom = newValue.clamped(to: 0.5 ... 2.0)
        guard clampedZoom != pageZoom else {
            return
        }

        pageZoom = clampedZoom
        lastAppliedPageZoom = clampedZoom
        webView?.pageZoom = clampedZoom
        persistPreference()
    }

    private func persistPreference(windowPlacement: StoredWindowPlacement? = nil) {
        var preference = preferencesStore.load(for: definition.id)
        preference.pageZoom = pageZoom
        preference.isPinned = isPinned
        preference.isMobileUA = isMobileUA
        preference.hiddenElements = hiddenElementRules
        preference.bookmarks = bookmarks
        if let windowPlacement {
            preference.windowPlacement = windowPlacement
            preference.windowFrame = windowPlacement.frame
        }
        preferencesStore.save(preference, for: definition.id)
    }

    func persistWindowFrame(_ frame: CGRect, on screen: NSScreen?) {
        let placement = StoredWindowPlacement(
            frame: frame,
            display: screen.map(StoredDisplayIdentity.init(screen:))
        )
        persistPreference(windowPlacement: placement)
    }

    private func loadConfiguredHomePage() {
        currentURL = definition.homeURL
        pageTitle = definition.name
        canGoBack = false
        canGoForward = false
        isLoading = true

        let request = URLRequest(url: definition.homeURL)
        webView?.load(request)
    }

    private static func websiteDataStoreIdentifier(for appID: String) -> UUID {
        let digest = SHA256.hash(data: Data("NeatWebApp.WebsiteDataStore.\(appID)".utf8))
        var bytes = Array(digest.prefix(16))

        // Keep the mapping stable across launches while producing a valid UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15]
        ))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

enum BrowserDownloadPhase: Equatable {
    case running
    case completed
    case failed
}

struct BrowserDownloadItem: Identifiable, Equatable {
    let id: UUID
    var filename: String
    var phase: BrowserDownloadPhase
    var fractionCompleted: Double?
    var destinationURL: URL?
    var message: String?

    init(
        id: UUID = UUID(),
        filename: String,
        phase: BrowserDownloadPhase = .running,
        fractionCompleted: Double? = 0,
        destinationURL: URL? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.phase = phase
        self.fractionCompleted = fractionCompleted
        self.destinationURL = destinationURL
        self.message = message
    }
}

private extension StoredDisplayIdentity {
    init(screen: NSScreen) {
        self.init(
            displayID: screen.displayID,
            localizedName: screen.localizedName,
            frame: screen.frame
        )
    }
}
