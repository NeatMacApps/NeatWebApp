import WebKit
import XCTest
@testable import NeatWebAppRuntime

final class BrowserOffscreenBlockParkingTests: XCTestCase {
    func testParkingScriptIsSiteAgnostic() {
        let source = BrowserOffscreenBlockParkingScript.source
        XCTAssertTrue(source.contains("content-visibility: hidden"))
        XCTAssertFalse(source.contains("content-visibility: auto"))
        XCTAssertTrue(source.contains("data-neat-parked"))
        XCTAssertTrue(source.contains("MIN_SIBLINGS"))
        XCTAssertFalse(source.contains("chatgpt.com"))
        XCTAssertFalse(source.contains("chat.openai.com"))
        XCTAssertFalse(source.contains("gemini.google.com"))
        XCTAssertFalse(source.contains("conversation-turn"))
    }

    @MainActor
    func testInstallKeepsParkingScriptWhenHiddenRulesReload() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        BrowserUserScripts.install(
            into: controller,
            hiddenElementRules: [
                HiddenElementRule(host: "example.com", selector: ".ad", label: "广告")
            ]
        )

        let sources = controller.userScripts.map { $0.source }
        XCTAssertEqual(sources.filter { $0.contains("data-neat-parked") }.count, 1)
        XCTAssertEqual(sources.filter { $0.contains("__neatWebAppThemeObserverInstalled") }.count, 1)
    }
}
