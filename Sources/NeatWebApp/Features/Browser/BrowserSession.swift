import Foundation
import Observation
import AppKit
import WebKit

@Observable
@MainActor
final class BrowserSession {
    let definition: WebAppDefinition

    var pageTitle: String
    var currentURL: URL
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

    @ObservationIgnored
    private let preferencesStore: WebAppPreferencesStore

    @ObservationIgnored
    private weak var webView: WKWebView?

    @ObservationIgnored
    var onPinnedChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onCloseRequest: (() -> Void)?

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
        self.preferencesStore = preferencesStore
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = pageZoom

        if webView.url == nil {
            webView.load(URLRequest(url: currentURL))
        } else {
            syncNavigationState(from: webView)
        }
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

    func goHome() {
        let request = URLRequest(url: definition.homeURL)
        webView?.load(request)
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

    func closeWindow() {
        onCloseRequest?()
    }

    func syncNavigationState(from webView: WKWebView) {
        pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? definition.name
        currentURL = webView.url ?? currentURL
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    private func setPageZoom(_ newValue: Double) {
        let clampedZoom = newValue.clamped(to: 0.5 ... 2.0)
        guard clampedZoom != pageZoom else {
            return
        }

        pageZoom = clampedZoom
        webView?.pageZoom = clampedZoom
        persistPreference()
    }

    private func persistPreference(windowPlacement: StoredWindowPlacement? = nil) {
        var preference = preferencesStore.load(for: definition.id)
        preference.pageZoom = pageZoom
        preference.isPinned = isPinned
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

private extension StoredDisplayIdentity {
    init(screen: NSScreen) {
        self.init(
            displayID: screen.displayID,
            localizedName: screen.localizedName,
            frame: screen.frame
        )
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
