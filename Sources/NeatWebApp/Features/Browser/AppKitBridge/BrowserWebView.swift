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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = session.chromeTheme.pageColor.nsColor

        session.attach(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        session.attach(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let session: BrowserSession

        init(session: BrowserSession) {
            self.session = session
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

        private func presentAlert(messageText: String, informativeText: String, style: NSAlert.Style) {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        private func presentConfirmation(messageText: String, informativeText: String) -> Bool {
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
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

                const readCandidateColors = () => {
                    const candidates = [];
                    const themeColor = document.head?.querySelector('meta[name="theme-color"]')?.content;
                    if (themeColor) {
                        candidates.push(themeColor);
                    }

                    const nodes = [
                        document.querySelector(candidateSelector),
                        document.body,
                        document.documentElement
                    ].filter(Boolean);

                    for (const node of nodes) {
                        const backgroundColor = getComputedStyle(node).backgroundColor;
                        if (backgroundColor) {
                            candidates.push(backgroundColor);
                        }
                    }

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
