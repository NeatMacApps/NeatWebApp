import WebKit
import XCTest
@testable import NeatWebAppRuntime

final class BrowserUserScriptsInstallTests: XCTestCase {
    @MainActor
    func testInstallDoesNotInjectOffscreenListParking() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        let joined = controller.userScripts.map(\.source).joined(separator: "\n")
        XCTAssertFalse(joined.contains("data-neat-parked"))
        XCTAssertFalse(joined.contains("content-visibility: hidden"))
        XCTAssertFalse(joined.contains("FULL_BIND_MS"))
        XCTAssertFalse(joined.contains("hasElementMutation"))
    }

    @MainActor
    func testInstallKeepsThemeAndHidingScriptsWhenHiddenRulesReload() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        BrowserUserScripts.install(
            into: controller,
            hiddenElementRules: [
                HiddenElementRule(host: "example.com", selector: ".ad", label: "广告")
            ]
        )

        let sources = controller.userScripts.map(\.source)
        XCTAssertEqual(sources.filter { $0.contains("data-neat-parked") }.count, 0)
        XCTAssertEqual(sources.filter { $0.contains("__neatWebAppThemeObserverInstalled") }.count, 1)
        XCTAssertTrue(sources.contains { $0.contains(".ad") })
    }
}
