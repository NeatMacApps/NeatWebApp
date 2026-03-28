import Foundation
import CryptoKit
import Observation
import AppKit
import WebKit

@Observable
@MainActor
final class BrowserSession {
    let definition: WebAppDefinition

    var pageTitle: String
    var currentURL: URL
    var chromeTheme = BrowserChromeTheme.fallback
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

    private static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    @ObservationIgnored
    private let preferencesStore: WebAppPreferencesStore

    @ObservationIgnored
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored
    private weak var webView: WKWebView?

    @ObservationIgnored
    var onPinnedChange: ((Bool) -> Void)?

    @ObservationIgnored
    var onCloseRequest: (() -> Void)?

    @ObservationIgnored
    var onChromeThemeChange: ((BrowserChromeTheme) -> Void)?

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
        self.preferencesStore = preferencesStore
        self.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.websiteDataStoreIdentifier(for: definition.id))
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = pageZoom
        webView.underPageBackgroundColor = chromeTheme.pageColor.nsColor
        applyUserAgent()

        if webView.url == nil {
            webView.load(URLRequest(url: currentURL))
        } else {
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

    func goHome() {
        loadConfiguredHomePage()
    }

    func reloadFromConfiguredURL() {
        loadConfiguredHomePage()
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

    func updateChromeThemeColor(_ pageColor: BrowserThemeColor?) {
        let nextTheme = pageColor.map(BrowserChromeTheme.init(pageColor:)) ?? .fallback
        guard nextTheme != chromeTheme else {
            return
        }

        chromeTheme = nextTheme
        webView?.underPageBackgroundColor = nextTheme.pageColor.nsColor
        onChromeThemeChange?(nextTheme)
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
        preference.isMobileUA = isMobileUA
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
