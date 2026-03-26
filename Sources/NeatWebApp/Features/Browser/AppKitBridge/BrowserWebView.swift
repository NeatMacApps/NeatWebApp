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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = .black

        session.attach(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        session.attach(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let session: BrowserSession

        init(session: BrowserSession) {
            self.session = session
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
