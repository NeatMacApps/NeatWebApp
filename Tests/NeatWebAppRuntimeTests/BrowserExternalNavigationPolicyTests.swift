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
