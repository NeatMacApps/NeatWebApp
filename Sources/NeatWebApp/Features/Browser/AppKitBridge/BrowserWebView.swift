import AppKit
import AVFoundation
import SwiftUI
import WebKit

struct BrowserWebView: NSViewRepresentable {
    let session: BrowserSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = session.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = WKUserContentController()
        configuration.userContentController.add(context.coordinator, name: BrowserThemeObserver.messageHandlerName)
        configuration.userContentController.add(context.coordinator, name: BrowserPasskeySupport.messageHandlerName)
        configuration.userContentController.add(context.coordinator, name: BrowserElementHidingScript.messageHandlerName)
        BrowserUserScripts.install(
            into: configuration.userContentController,
            hiddenElementRules: session.hiddenElementRules
        )

        let webView = BrowserKeyCommandWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = session.chromeTheme.pageColor.nsColor
        webView.session = session

        session.attach(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        session.attach(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let session: BrowserSession
        private let downloadManager: BrowserDownloadManager
        /// 通行密钥受限的解释每个窗口只给一次：站点常会连着重试，否则会连弹好几次。
        private var hasExplainedPasskeyLimitation = false
        /// 最近一次由网页主动发起的媒体请求。用户从系统设置回来时据此重检，不在启动时碰权限。
        private var pendingMediaTypes = Set<AVMediaType>()
        /// 同一类能力在一个窗口生命周期内只解释一次，避免网页重试时连续打断用户。
        private var explainedDeniedMediaTypes = Set<AVMediaType>()

        init(session: BrowserSession) {
            self.session = session
            self.downloadManager = BrowserDownloadManager(session: session)
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case BrowserThemeObserver.messageHandlerName:
                guard let pageColor = BrowserThemeColor.fromScriptMessageBody(message.body) else {
                    return
                }

                session.updateChromeThemeColor(pageColor)
            case BrowserPasskeySupport.messageHandlerName:
                explainPasskeyLimitation(pageURL: message.webView?.url)
            case BrowserElementHidingScript.messageHandlerName:
                guard let incoming = BrowserElementHidingScript.IncomingMessage(body: message.body) else {
                    return
                }

                session.handleElementHidingMessage(incoming)
            default:
                break
            }
        }

        /// 通行密钥被系统拒绝时，说清为什么，并给一条真的走得通的路：换到默认浏览器登录。
        private func explainPasskeyLimitation(pageURL: URL?) {
            guard !hasExplainedPasskeyLimitation else {
                return
            }

            hasExplainedPasskeyLimitation = true

            let alert = NSAlert()
            alert.messageText = localized("browser.permission.passkey.title")
            alert.informativeText = String(format: localized("browser.permission.passkey.message"), session.definition.name)
            alert.alertStyle = .informational
            alert.addButton(withTitle: localized("browser.permission.passkey.open_browser"))
            alert.addButton(withTitle: localized("common.got_it"))

            if alert.runModal() == .alertFirstButtonReturn {
                openExternally(pageURL ?? session.definition.homeURL)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
            notifyFirstContentPaint(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
            notifyFirstContentPaint(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            session.syncNavigationState(from: webView)
            notifyFirstContentPaint(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            session.syncNavigationState(from: webView)
            notifyFirstContentPaint(from: webView)
        }

        private func notifyFirstContentPaint(from webView: WKWebView) {
            guard session.onFirstContentPaint != nil else {
                return
            }

            webView.notifyAfterNextPresentationUpdate { [session] in
                session.consumeFirstContentPaint()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            switch BrowserExternalNavigationPolicy.decision(
                for: navigationAction.request.url,
                isUserInitiated: navigationAction.navigationType == .linkActivated
            ) {
            case .allowInWebView:
                decisionHandler(.allow)
            case .openExternally:
                openExternally(navigationAction.request.url)
                decisionHandler(.cancel)
            case .confirmBeforeOpening:
                if confirmExternalNavigation(url: navigationAction.request.url, sourceURL: webView.url) {
                    openExternally(navigationAction.request.url)
                }
                decisionHandler(.cancel)
            case .reject:
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = downloadManager
            downloadManager.track(download, suggestedFilename: navigationAction.request.url?.lastPathComponent)
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = downloadManager
            downloadManager.track(download, suggestedFilename: navigationResponse.response.suggestedFilename)
            session.syncNavigationState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil else {
                return nil
            }

            webView.load(navigationAction.request)
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            session.closeWindow()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor () -> Void
        ) {
            presentAlert(
                messageText: webView.title ?? session.definition.name,
                informativeText: message,
                style: .informational
            )
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (Bool) -> Void
        ) {
            completionHandler(
                presentConfirmation(
                    messageText: webView.title ?? session.definition.name,
                    informativeText: message
                )
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (String?) -> Void
        ) {
            completionHandler(
                presentTextInput(
                    messageText: webView.title ?? session.definition.name,
                    informativeText: prompt,
                    defaultText: defaultText
                )
            )
        }

        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor ([URL]?) -> Void
        ) {
            let openPanel = NSOpenPanel()
            openPanel.canChooseDirectories = parameters.allowsDirectories
            openPanel.canChooseFiles = true
            openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
            openPanel.canCreateDirectories = false
            openPanel.message = localized("browser.upload.choose_file")

            let response = openPanel.runModal()
            completionHandler(response == .OK ? openPanel.urls : nil)
        }

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
        ) {
            let mediaTypes = Self.mediaTypes(for: type)
            let deniedMediaTypes = mediaTypes.filter { Self.isAccessBlocked(for: $0) }

            guard deniedMediaTypes.isEmpty else {
                decisionHandler(.deny)
                presentMediaCaptureRecoveryIfNeeded(for: deniedMediaTypes)
                return
            }

            pendingMediaTypes.formUnion(mediaTypes)
            decisionHandler(.prompt)
        }

        /// 从系统设置回到应用时重检，不强迫重载页面或替用户再次触发网页的摄像头/麦克风动作。
        @objc private func applicationDidBecomeActive(_ notification: Notification) {
            guard !pendingMediaTypes.isEmpty else {
                return
            }

            let deniedMediaTypes = pendingMediaTypes.filter { Self.isAccessBlocked(for: $0) }
            if deniedMediaTypes.isEmpty,
               pendingMediaTypes.allSatisfy({ AVCaptureDevice.authorizationStatus(for: $0) == .authorized }) {
                pendingMediaTypes.removeAll()
                return
            }

            presentMediaCaptureRecoveryIfNeeded(for: Array(deniedMediaTypes))
        }

        private static func mediaTypes(for requestType: WKMediaCaptureType) -> [AVMediaType] {
            switch requestType {
            case .camera:
                [.video]
            case .microphone:
                [.audio]
            case .cameraAndMicrophone:
                [.video, .audio]
            @unknown default:
                []
            }
        }

        private static func isAccessBlocked(for mediaType: AVMediaType) -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: mediaType) {
            case .denied, .restricted:
                true
            case .notDetermined, .authorized:
                false
            @unknown default:
                true
            }
        }

        private func presentMediaCaptureRecoveryIfNeeded(for deniedMediaTypes: [AVMediaType]) {
            let newlyDeniedMediaTypes = deniedMediaTypes.filter { !explainedDeniedMediaTypes.contains($0) }
            guard !newlyDeniedMediaTypes.isEmpty else {
                return
            }

            explainedDeniedMediaTypes.formUnion(newlyDeniedMediaTypes)

            let alert = NSAlert()
            alert.messageText = mediaCaptureDeniedTitle(for: newlyDeniedMediaTypes)
            alert.informativeText = mediaCaptureDeniedDescription(for: newlyDeniedMediaTypes)
            alert.alertStyle = .warning

            if newlyDeniedMediaTypes.contains(.video) {
                alert.addButton(withTitle: localized("browser.permission.camera.open_settings"))
            }
            if newlyDeniedMediaTypes.contains(.audio) {
                alert.addButton(withTitle: localized("browser.permission.microphone.open_settings"))
            }
            alert.addButton(withTitle: localized("common.later"))

            let response = alert.runModal()
            let selectedIndex = Int(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            let selectableMediaTypes = newlyDeniedMediaTypes.filter { $0 == .video || $0 == .audio }
            guard selectableMediaTypes.indices.contains(selectedIndex) else {
                return
            }

            openMediaCaptureSettings(for: selectableMediaTypes[selectedIndex])
        }

        private func mediaCaptureDeniedTitle(for mediaTypes: [AVMediaType]) -> String {
            if mediaTypes.count == 2 {
                return localized("browser.permission.media.camera_microphone.title")
            }
            return localized(mediaTypes.first == .video ? "browser.permission.media.camera.title" : "browser.permission.media.microphone.title")
        }

        private func mediaCaptureDeniedDescription(for mediaTypes: [AVMediaType]) -> String {
            let capability = localized(
                mediaTypes.count == 2
                    ? "browser.permission.media.capability.camera_microphone"
                    : mediaTypes.first == .video
                        ? "browser.permission.media.capability.camera"
                        : "browser.permission.media.capability.microphone"
            )
            return String(format: localized("browser.permission.media.message"), session.definition.name, capability)
        }

        private func openMediaCaptureSettings(for mediaType: AVMediaType) {
            let pane = mediaType == .video ? "Privacy_Camera" : "Privacy_Microphone"
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
                return
            }

            _ = NSWorkspace.shared.open(url)
        }

        private func presentAlert(messageText: String, informativeText: String, style: NSAlert.Style) {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = style
            alert.addButton(withTitle: localized("common.confirm"))
            alert.runModal()
        }

        private func presentConfirmation(messageText: String, informativeText: String) -> Bool {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .warning
            alert.addButton(withTitle: localized("common.confirm"))
            alert.addButton(withTitle: localized("common.cancel"))
            return alert.runModal() == .alertFirstButtonReturn
        }

        private func presentTextInput(messageText: String, informativeText: String, defaultText: String?) -> String? {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .informational
            alert.addButton(withTitle: localized("common.confirm"))
            alert.addButton(withTitle: localized("common.cancel"))

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }

            return textField.stringValue
        }

        private func confirmExternalNavigation(url: URL?, sourceURL: URL?) -> Bool {
            let target = url?.absoluteString ?? localized("browser.external.unknown_address")
            let source = sourceURL?.host(percentEncoded: false) ?? session.definition.name
            return presentConfirmation(
                messageText: localized("browser.external.open_title"),
                informativeText: String(format: localized("browser.external.open_message_format"), source, target)
            )
        }

        private func localized(_ key: String) -> String {
            String(localized: LocalizedStringResource(stringLiteral: key))
        }

        private func openExternally(_ url: URL?) {
            guard let url else {
                return
            }

            if NSWorkspace.shared.open(url) == false {
                presentAlert(
                    messageText: localized("browser.external.open_failed_title"),
                    informativeText: url.absoluteString,
                    style: .warning
                )
            }
        }
    }
}

/// 承载浏览器级快捷键的 WebView。
///
/// 快捷键必须在 `performKeyEquivalent` 阶段拦截：网页内的输入框拿到焦点时，
/// 普通 `keyDown` 会先被网页消费，用户就按不动刷新、前进后退和缩放了。
final class BrowserKeyCommandWebView: WKWebView {
    weak var session: BrowserSession?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let session, let command = BrowserKeyCommand.resolve(event: event) else {
            return super.performKeyEquivalent(with: event)
        }

        switch command {
        case .zoomIn:
            session.increaseZoom()
        case .zoomOut:
            session.decreaseZoom()
        case .resetZoom:
            session.resetZoom()
        case .reload:
            session.reload()
        case .reloadIgnoringCache:
            session.reloadIgnoringCache()
        case .goBack:
            session.goBack()
        case .goForward:
            session.goForward()
        case .goHome:
            session.goHome()
        case .printPage:
            session.printPage()
        case .collapseWindow:
            session.collapseWindow()
        case .toggleBookmark:
            session.toggleCurrentPageBookmark()
        }

        return true
    }
}

/// 注入脚本的唯一安装入口。
///
/// WebKit 只允许整批清空用户脚本、不能单独摘掉某一条，所以隐藏规则一变就得把整套重装一遍；
/// 装配顺序集中在这里，免得漏掉其中一条。
enum BrowserUserScripts {
    @MainActor
    static func install(into controller: WKUserContentController, hiddenElementRules: [HiddenElementRule]) {
        controller.removeAllUserScripts()
        controller.addUserScript(BrowserThemeObserver.makeUserScript())
        controller.addUserScript(BrowserPasskeySupport.makeUserScript())
        controller.addUserScript(BrowserElementHidingScript.makeUserScript(rules: hiddenElementRules))
    }
}

private enum BrowserThemeObserver {
    static let messageHandlerName = "browserTheme"

    @MainActor
    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
                const handler = window.webkit?.messageHandlers?.browserTheme;
                if (!handler || window.__neatWebAppThemeObserverInstalled) {
                    return;
                }

                window.__neatWebAppThemeObserverInstalled = true;

                let pendingTimeouts = new Set();
                let attributeNames = ['class', 'style', 'data-theme', 'data-color-mode', 'color-scheme'];
                let metaAttributeNames = ['content', 'name', 'media'];
                let candidateSelector = 'main, [role="main"]';
                let rootStyle = [
                    'position: fixed',
                    'left: -9999px',
                    'top: -9999px',
                    'opacity: 0',
                    'pointer-events: none',
                    'contain: strict'
                ].join('; ');

                // computed style 已经是 rgb()/rgba() 时直接解析，不建探测节点、不读布局；
                // 只有站点写了颜色名、hex 等非 rgb 写法时，才走探测节点归一化。
                const fastRgbMatch = (value) => {
                    if (typeof value !== 'string') {
                        return null;
                    }

                    const match = value.match(/^rgba?\\(([0-9]+),\\s*([0-9]+),\\s*([0-9]+)(?:,\\s*([0-9.]+))?\\)$/i);
                    if (!match) {
                        return null;
                    }

                    const alpha = match[4] === undefined ? 1 : Number(match[4]);
                    if (!Number.isFinite(alpha) || alpha <= 0.01) {
                        return null;
                    }

                    return {
                        red: Number(match[1]) / 255,
                        green: Number(match[2]) / 255,
                        blue: Number(match[3]) / 255,
                        alpha
                    };
                };

                const parseColor = (value) => {
                    if (!value || value === 'transparent') {
                        return null;
                    }

                    const fast = fastRgbMatch(value);
                    if (fast) {
                        return fast;
                    }

                    const probe = ensureProbe();
                    if (!probe) {
                        return null;
                    }

                    probe.style.color = value;
                    const normalized = getComputedStyle(probe).color;

                    const match = normalized.match(/^rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([0-9.]+))?\\)$/i);
                    if (!match) {
                        return null;
                    }

                    const alpha = match[4] === undefined ? 1 : Number(match[4]);
                    if (!Number.isFinite(alpha) || alpha <= 0.01) {
                        return null;
                    }

                    return {
                        red: Number(match[1]) / 255,
                        green: Number(match[2]) / 255,
                        blue: Number(match[3]) / 255,
                        alpha
                    };
                };

                // 顶栏让位带要和页面顶端严丝合缝，所以直接取视口最上沿真正被绘制出来的颜色：
                // 从顶端中点向上找第一个不透明背景，命中的往往就是站点自己的顶部导航底色。
                // 顶端颜色命中即返回解析结果：外层不再对它做第二次解析。
                const readTopEdgeBackground = () => {
                    const width = window.innerWidth || document.documentElement?.clientWidth || 0;
                    if (width <= 0) {
                        return null;
                    }

                    let node = document.elementFromPoint(Math.floor(width / 2), 1);
                    while (node) {
                        const backgroundColor = getComputedStyle(node).backgroundColor;
                        const parsed = parseColor(backgroundColor);
                        if (parsed && parsed.alpha > 0.95) {
                            return parsed;
                        }
                        node = node.parentElement;
                    }

                    return null;
                };

                const readCandidateColors = () => {
                    const candidates = [];

                    // 顶端命中直接就是第一候选：找到了就不用再翻 body/html/main 和主题色。
                    const topEdgeBackground = readTopEdgeBackground();
                    if (topEdgeBackground) {
                        return [topEdgeBackground];
                    }

                    const nodes = [
                        document.body,
                        document.documentElement,
                        document.querySelector(candidateSelector)
                    ].filter(Boolean);

                    for (const node of nodes) {
                        const backgroundColor = getComputedStyle(node).backgroundColor;
                        if (backgroundColor) {
                            candidates.push(backgroundColor);
                        }
                    }

                    // 站点声明的主题色是给浏览器界面用的提示色，常常故意和页面背景不同
                    // （例如页面是白的、主题色却是品牌蓝或深灰），只能当兜底，不能优先。
                    const themeColor = document.head?.querySelector('meta[name="theme-color"]')?.content;
                    if (themeColor) {
                        candidates.push(themeColor);
                    }

                    // 页面没有任何显式背景时，浏览器实际画的是白色；退回深色会让让位带变成一条黑条。
                    candidates.push({ red: 1, green: 1, blue: 1, alpha: 1 });

                    return candidates;
                };

                let lastPayload = '';
                let pendingFrame = 0;
                let probe = null;

                const ensureProbe = () => {
                    if (probe?.isConnected) {
                        return probe;
                    }

                    const parent = document.body ?? document.documentElement;
                    if (!parent) {
                        return null;
                    }

                    probe = document.createElement('span');
                    probe.setAttribute('aria-hidden', 'true');
                    probe.style.cssText = rootStyle;
                    parent.appendChild(probe);
                    return probe;
                };

                const postTheme = () => {
                    for (const candidate of readCandidateColors()) {
                        // 候选已经是解析结果（顶端命中）或原始颜色字符串：字符串才需要再解析。
                        const color = typeof candidate === 'string' ? parseColor(candidate) : candidate;
                        if (!color) {
                            continue;
                        }

                        const payload = JSON.stringify(color);
                        if (payload === lastPayload) {
                            return;
                        }

                        lastPayload = payload;
                        handler.postMessage(color);
                        return;
                    }
                };

                const clearPendingTimeouts = () => {
                    for (const timeout of pendingTimeouts) {
                        clearTimeout(timeout);
                    }
                    pendingTimeouts.clear();
                    pendingDelayedPost.timeout = null;
                };

                let lastPostAt = 0;
                let pendingDelayedPost = { timeout: null };

                const schedulePost = () => {
                    // 藏起来的标签页不取色：elementFromPoint 照样强制布局，纯属浪费；
                    // 回到可见时 visibilitychange 会主动重同步。
                    if (document.hidden) {
                        return;
                    }

                    if (pendingFrame !== 0) {
                        return;
                    }

                    pendingFrame = requestAnimationFrame(() => {
                        pendingFrame = 0;
                        const now = performance.now();
                        const wait = 280 - (now - lastPostAt);
                        if (wait > 0) {
                            schedulePostAfterDelay(wait);
                            return;
                        }
                        lastPostAt = now;
                        postTheme();
                    });
                };

                const schedulePostAfterDelay = (delay) => {
                    // 普通节流最多留一个待执行的定时器：高频变更时旧的直接作废，
                    // 不堆出一串排队回调。导航/加载的主动重同步走 scheduleResyncBurst。
                    if (pendingDelayedPost.timeout !== null) {
                        return;
                    }

                    const timeout = setTimeout(() => {
                        pendingDelayedPost.timeout = null;
                        pendingTimeouts.delete(timeout);
                        schedulePost();
                    }, delay);
                    pendingDelayedPost.timeout = timeout;
                    pendingTimeouts.add(timeout);
                };

                const scheduleResyncBurst = () => {
                    clearPendingTimeouts();
                    schedulePost();
                    // 导航/加载后的两次补采：第一次清掉待执行的旧节流，第二次直接排新定时器，
                    // 不走「最多留一个」的普通节流上限，免得第一次占位把第二次吞掉。
                    const first = setTimeout(() => {
                        pendingTimeouts.delete(first);
                        schedulePost();
                    }, 180);
                    pendingTimeouts.add(first);
                    const second = setTimeout(() => {
                        pendingTimeouts.delete(second);
                        schedulePost();
                    }, 900);
                    pendingTimeouts.add(second);
                };

                const headChildListAffectsTheme = (record) => {
                    const affects = (list) => {
                        for (const node of list) {
                            if (node && node.nodeType === 1) {
                                const tag = node.tagName;
                                if (tag === 'META' || tag === 'STYLE' || tag === 'LINK') {
                                    return true;
                                }
                            }
                        }
                        return false;
                    };
                    return affects(record.addedNodes) || affects(record.removedNodes);
                };

                const observeAttributes = (node) => {
                    if (!node) {
                        return null;
                    }

                    const observer = new MutationObserver(schedulePost);
                    observer.observe(node, {
                        attributes: true,
                        attributeFilter: attributeNames
                    });
                    return observer;
                };

                const headObserver = new MutationObserver((records) => {
                    for (const record of records) {
                        if (record.type === 'childList') {
                            // head 里脚本、预加载等与顶部颜色无关的节点增删很频繁：
                            // 只有可能影响取色的 META/STYLE/LINK 才触发重采，
                            // 否则每次都会走 elementFromPoint + computed style 强制布局。
                            if (headChildListAffectsTheme(record)) {
                                schedulePost();
                                return;
                            }
                            continue;
                        }

                        if (
                            record.type === 'attributes'
                            && record.target instanceof HTMLMetaElement
                            && record.target.name === 'theme-color'
                        ) {
                            schedulePost();
                            return;
                        }
                    }
                });

                if (document.head) {
                    headObserver.observe(document.head, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: metaAttributeNames
                    });
                }

                  const observers = [
                      observeAttributes(document.documentElement),
                      observeAttributes(document.body)
                  ].filter(Boolean);

                const wrapHistoryMethod = (methodName) => {
                    const original = history[methodName];
                    if (typeof original !== 'function') {
                        return;
                    }

                    history[methodName] = function(...args) {
                        const result = original.apply(this, args);
                        scheduleResyncBurst();
                        return result;
                    };
                };

                wrapHistoryMethod('pushState');
                wrapHistoryMethod('replaceState');

                window.addEventListener('load', scheduleResyncBurst, { once: true });
                window.addEventListener('pageshow', scheduleResyncBurst);
                window.addEventListener('popstate', scheduleResyncBurst);
                window.addEventListener('hashchange', scheduleResyncBurst);
                document.addEventListener('DOMContentLoaded', scheduleResyncBurst, { once: true });
                document.addEventListener('visibilitychange', () => {
                    if (document.visibilityState === 'visible') {
                        scheduleResyncBurst();
                    }
                });

                window.addEventListener('beforeunload', () => {
                    clearPendingTimeouts();
                    headObserver.disconnect();
                    for (const observer of observers) {
                        observer.disconnect();
                    }
                });

                scheduleResyncBurst();
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}

private extension WKWebView {
    func notifyAfterNextPresentationUpdate(_ handler: @escaping @MainActor () -> Void) {
        let selector = NSSelectorFromString("_doAfterNextPresentationUpdate:")
        if responds(to: selector) {
            let block: @convention(block) () -> Void = {
                Task { @MainActor in
                    handler()
                }
            }
            perform(selector, with: unsafeBitCast(block, to: AnyObject.self))
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            handler()
        }
    }
}
