import WebKit
import XCTest
@testable import NeatWebAppRuntime

final class BrowserExternalNavigationPolicyTests: XCTestCase {
    func testAllowsHttpAndHttpsInWebView() {
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "https://example.com"), isUserInitiated: true),
            .allowInWebView
        )
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "http://example.com"), isUserInitiated: false),
            .allowInWebView
        )
    }

    func testRejectsJavaScriptURLs() {
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "javascript:alert(1)"), isUserInitiated: true),
            .reject
        )
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "applescript://example"), isUserInitiated: true),
            .reject
        )
    }

    func testUserClickedExternalSchemeOpensWithoutExtraConfirmation() {
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "mailto:hello@example.com"), isUserInitiated: true),
            .openExternally
        )
    }

    func testScriptTriggeredExternalSchemeRequiresConfirmation() {
        XCTAssertEqual(
            BrowserExternalNavigationPolicy.decision(for: URL(string: "zoommtg://example"), isUserInitiated: false),
            .confirmBeforeOpening
        )
    }
}

@MainActor
final class BrowserLoadRecoveryTests: XCTestCase {
    func testShouldLogLoadErrorFiltersCancelledAndPolicyInterruptions() {
        XCTAssertFalse(
            BrowserSession.shouldLogLoadError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            )
        )
        XCTAssertFalse(
            BrowserSession.shouldLogLoadError(
                NSError(domain: "WebKitErrorDomain", code: 102)
            )
        )
        XCTAssertFalse(
            BrowserSession.shouldLogLoadError(
                NSError(domain: "WebKitErrorDomain", code: 204)
            )
        )

        XCTAssertTrue(
            BrowserSession.shouldLogLoadError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
            )
        )
        XCTAssertTrue(
            BrowserSession.shouldLogLoadError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
            )
        )
        XCTAssertTrue(
            BrowserSession.shouldLogLoadError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            )
        )
    }

    func testReloadAndReloadIgnoringCacheFallBackToFailedOrHomeURLWhenWebViewURLIsNil() throws {
        let (session, homeURL) = try makeSession()
        let webView = SpyLoadWebView()
        session.continueWithoutImportedCookies()
        session.attach(webView: webView)
        webView.recordedRequests.removeAll()

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."]
        )
        let failedURL = try XCTUnwrap(URL(string: "https://chatgpt.com/chat"))
        session.isLoading = true
        session.handleNavigationFailure(error, failingURL: failedURL)

        XCTAssertFalse(session.isLoading)
        XCTAssertNil(webView.url)

        session.reload()
        XCTAssertTrue(session.isLoading)
        XCTAssertEqual(webView.recordedRequests.map(\.url), [failedURL])

        webView.recordedRequests.removeAll()
        session.reloadIgnoringCache()
        XCTAssertEqual(webView.recordedRequests.map(\.url), [homeURL])
        XCTAssertEqual(webView.recordedRequests.first?.cachePolicy, .reloadIgnoringLocalCacheData)

        session.handleNavigationFailure(error, failingURL: failedURL)
        session.handleNavigationCommitted()
        webView.recordedRequests.removeAll()
        session.reload()
        XCTAssertEqual(webView.recordedRequests.map(\.url), [homeURL])
    }

    func testReattachingSameWebViewDoesNotLoopLoadWhenURLIsNil() throws {
        let (session, homeURL) = try makeSession()
        let webView = SpyLoadWebView()
        session.continueWithoutImportedCookies()
        session.attach(webView: webView)
        XCTAssertEqual(webView.recordedRequests.map(\.url), [homeURL])

        session.attach(webView: webView)
        XCTAssertEqual(webView.recordedRequests.count, 1)
    }

    func testWebContentProcessTerminationReloadsOnceThenStopsLoop() throws {
        let (session, _) = try makeSession()
        let webView = SpyLoadWebView()
        session.continueWithoutImportedCookies()
        session.attach(webView: webView)
        webView.recordedRequests.removeAll()

        let start = Date(timeIntervalSince1970: 1_000)
        session.handleWebContentProcessDidTerminate(now: start)
        XCTAssertEqual(webView.recordedRequests.count, 1)

        session.handleWebContentProcessDidTerminate(now: start.addingTimeInterval(5))
        XCTAssertFalse(session.isLoading)
        XCTAssertEqual(webView.recordedRequests.count, 1)
    }

    private func makeSession() throws -> (BrowserSession, URL) {
        let suiteID = "BrowserLoadRecoveryTests-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(path: suiteID)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteID))
        let store = WebAppPreferencesStore(userDefaults: defaults, rootDirectoryURL: root)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteID)
        }

        let homeURL = try XCTUnwrap(URL(string: "https://chatgpt.com/"))
        let definition = WebAppDefinition(
            id: "test-load-\(UUID().uuidString)",
            name: "ChatGPT",
            homeURL: homeURL,
            accentColorName: "WebAppAccentBlue",
            shortDescription: "chatgpt.com"
        )
        let session = BrowserSession(
            definition: definition,
            preference: StoredWebAppPreference(),
            preferencesStore: store
        )
        return (session, homeURL)
    }
}

@MainActor
private final class SpyLoadWebView: WKWebView {
    var recordedRequests: [URLRequest] = []

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        recordedRequests.append(request)
        return nil
    }
}
