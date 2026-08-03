import AppKit
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
        configuration.userContentController.addUserScript(BrowserThemeObserver.makeUserScript())

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

        init(session: BrowserSession) {
            self.session = session
            self.downloadManager = BrowserDownloadManager(session: session)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                message.name == BrowserThemeObserver.messageHandlerName,
                let pageColor = BrowserThemeColor.fromScriptMessageBody(message.body)
            else {
                return
            }

            session.updateChromeThemeColor(pageColor)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            session.syncNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            session.syncNavigationState(from: webView)
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
            openPanel.message = "选择要上传到网页的文件"

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
            decisionHandler(.prompt)
        }

        private func presentAlert(messageText: String, informativeText: String, style: NSAlert.Style) {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = style
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }

        private func presentConfirmation(messageText: String, informativeText: String) -> Bool {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            return alert.runModal() == .alertFirstButtonReturn
        }

        private func presentTextInput(messageText: String, informativeText: String, defaultText: String?) -> String? {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }

            return textField.stringValue
        }

        private func confirmExternalNavigation(url: URL?, sourceURL: URL?) -> Bool {
            let target = url?.absoluteString ?? "未知地址"
            let source = sourceURL?.host(percentEncoded: false) ?? session.definition.name
            return presentConfirmation(
                messageText: "打开外部应用？",
                informativeText: "\(source) 想打开：\n\(target)"
            )
        }

        private func openExternally(_ url: URL?) {
            guard let url else {
                return
            }

            if NSWorkspace.shared.open(url) == false {
                presentAlert(
                    messageText: "无法打开外部链接",
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
        }

        return true
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

                const parseColor = (value) => {
                    if (!value || value === 'transparent') {
                        return null;
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
                            return backgroundColor;
                        }
                        node = node.parentElement;
                    }

                    return null;
                };

                const readCandidateColors = () => {
                    const candidates = [];

                    const topEdgeBackground = readTopEdgeBackground();
                    if (topEdgeBackground) {
                        candidates.push(topEdgeBackground);
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
                    candidates.push('rgb(255, 255, 255)');

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
                        const color = parseColor(candidate);
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
                };

                const schedulePost = () => {
                    if (pendingFrame !== 0) {
                        return;
                    }

                    pendingFrame = requestAnimationFrame(() => {
                        pendingFrame = 0;
                        postTheme();
                    });
                };

                const schedulePostAfterDelay = (delay) => {
                    const timeout = setTimeout(() => {
                        pendingTimeouts.delete(timeout);
                        schedulePost();
                    }, delay);
                    pendingTimeouts.add(timeout);
                };

                const scheduleResyncBurst = () => {
                    clearPendingTimeouts();
                    schedulePost();
                    schedulePostAfterDelay(180);
                    schedulePostAfterDelay(900);
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
                            schedulePost();
                            return;
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
                    observeAttributes(document.body),
                    observeAttributes(document.querySelector(candidateSelector))
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
