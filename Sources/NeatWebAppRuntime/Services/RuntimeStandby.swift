import AppKit
import Foundation
import WebKit

/// An app-agnostic runtime kept warm until the host hands it a web app.
///
/// Warming loads a blank page in a throwaway, non-persistent data store so WebKit launches its
/// network, GPU and content processes and registers fonts ahead of time. No web app's data store
/// is touched until the host sends `adoptBootstrap`. See `docs/design/warm-standby-runtime.md`.
@MainActor
final class RuntimeStandby {
    private let instanceID: UUID
    private let hostProcessID: Int32?
    private let registryStore: RuntimeRegistryStore
    private let commandBus: RuntimeCommandBus
    private let commandListener: RuntimeCommandListener
    private let hostLifecycleMonitor = RuntimeHostLifecycleMonitor()
    private let onAdopt: @MainActor (RuntimeBootstrap) -> Void
    private var warmUpWebView: WKWebView?
    private var warmUpDelegate: WarmUpNavigationDelegate?
    private var hasAdopted = false

    init(
        instanceID: UUID,
        hostProcessID: Int32?,
        registryStore: RuntimeRegistryStore = RuntimeRegistryStore(),
        commandBus: RuntimeCommandBus = RuntimeCommandBus(),
        onAdopt: @escaping @MainActor (RuntimeBootstrap) -> Void
    ) {
        self.instanceID = instanceID
        self.hostProcessID = hostProcessID
        self.registryStore = registryStore
        self.commandBus = commandBus
        self.commandListener = RuntimeCommandListener(commandBus: commandBus)
        self.onAdopt = onAdopt
    }

    func start() {
        commandListener.start(instanceID: instanceID) { [weak self] command in
            self?.handle(command)
        }
        // A standby is useless without the host that launched it; never linger as an orphan.
        let hostIsAlive = hostLifecycleMonitor.start(hostProcessID: hostProcessID) {
            NSApplication.shared.terminate(nil)
        }
        guard hostIsAlive else {
            NSApplication.shared.terminate(nil)
            return
        }
        warmUpWebKit()
    }

    private func warmUpWebKit() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        let delegate = WarmUpNavigationDelegate { [weak self] in
            self?.finishWarmUp()
        }
        webView.navigationDelegate = delegate
        warmUpWebView = webView
        warmUpDelegate = delegate
        webView.loadHTMLString("<!doctype html><title></title>", baseURL: nil)
    }

    /// The blank page is released once loaded; WebKit keeps its helper processes and a
    /// prewarmed content process, which the adopted web app's first load then picks up.
    private func finishWarmUp() {
        warmUpWebView?.navigationDelegate = nil
        warmUpWebView = nil
        warmUpDelegate = nil
        guard !hasAdopted else {
            return
        }

        commandBus.send(
            RuntimeEvent(
                instanceID: instanceID,
                appID: "",
                sequence: 0,
                event: .standbyReady,
                phase: .launching,
                windowFrame: nil,
                floatingIconFrame: nil,
                lastUpdatedAt: .now
            )
        )
    }

    private func handle(_ command: RuntimeCommand) {
        guard command.instanceID == instanceID,
              command.command == .adoptBootstrap,
              !hasAdopted else {
            return
        }

        // Without a bootstrap there is nothing to adopt; quitting lets the host fall back
        // to a normal launch instead of waiting on a runtime that can never show a window.
        guard let bootstrap = registryStore.loadBootstrap(instanceID: instanceID),
              bootstrap.appID == command.appID else {
            NSApplication.shared.terminate(nil)
            return
        }

        hasAdopted = true
        commandListener.stop()
        hostLifecycleMonitor.stop()
        warmUpWebView?.navigationDelegate = nil
        warmUpWebView = nil
        warmUpDelegate = nil
        onAdopt(bootstrap)
    }
}

private final class WarmUpNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: @MainActor () -> Void

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { onFinish() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { onFinish() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { onFinish() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated { onFinish() }
    }
}
