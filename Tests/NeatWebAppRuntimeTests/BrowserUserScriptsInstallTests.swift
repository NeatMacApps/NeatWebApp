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
    func testThemeScriptParsesRgbDirectlyAndCapsPendingTimers() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        let joined = controller.userScripts.map(\.source).joined(separator: "\n")

        // rgb() 直接解析：computed style 已是 rgb 写法时不建探测节点。
        XCTAssertTrue(joined.contains("fastRgbMatch"))
        // 顶端命中直接返回解析结果，外层不再二次解析。
        XCTAssertTrue(joined.contains("return [topEdgeBackground]"))
        // 普通节流最多留一个待执行定时器；导航重同步的两次补采不受该上限吞掉。
        XCTAssertTrue(joined.contains("pendingDelayedPost"))
    }

    @MainActor
    func testThemeScriptIgnoresIrrelevantHeadInsertionsAndHiddenDocuments() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        let joined = controller.userScripts.map(\.source).joined(separator: "\n")

        // head 里只有 META/STYLE/LINK 的增删才触发重采，脚本/预加载等不强制布局。
        XCTAssertTrue(joined.contains("headChildListAffectsTheme"))
        XCTAssertTrue(joined.contains("addedNodes"))
        // 藏起来的标签页跳过取色，可见时由 visibilitychange 重同步。
        XCTAssertTrue(joined.contains("document.hidden"))
    }

    @MainActor
    func testHidingScriptReportsBroadRules() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller, hiddenElementRules: [])
        let joined = controller.userScripts.map(\.source).joined(separator: "\n")
        XCTAssertTrue(joined.contains("reportBroadRule"))
        XCTAssertTrue(joined.contains("type: 'broad'"))

        let report = BrowserElementHidingScript.reportBroadRuleScript(selector: ".visible", label: "一片区域")
        XCTAssertTrue(report.contains(".visible"))
        XCTAssertTrue(report.contains("\(BrowserElementHidingScript.broadRuleMatchLimit)"))

        let message = BrowserElementHidingScript.IncomingMessage(body: [
            "type": "broad", "selector": ".visible", "label": "一片区域", "count": 120,
        ])
        guard case let .broad(selector, count, label) = message else {
            XCTFail("broad 消息应被解析")
            return
        }
        XCTAssertEqual(selector, ".visible")
        XCTAssertEqual(count, 120)
        XCTAssertEqual(label, "一片区域")
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
