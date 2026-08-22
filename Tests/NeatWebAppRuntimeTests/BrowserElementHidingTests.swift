import XCTest
@testable import NeatWebAppRuntime

final class BrowserElementHidingTests: XCTestCase {
    func testHostNormalizationTreatsWWWAsSameSite() {
        XCTAssertEqual(HiddenElementRule.normalizedHost("WWW.Example.com"), "example.com")
        XCTAssertEqual(HiddenElementRule.normalizedHost("example.com"), "example.com")
        XCTAssertEqual(HiddenElementRule.normalizedHost(nil), "")
    }

    func testRuleAppliesAcrossWWWVariantsOfSameSite() {
        let rule = HiddenElementRule(host: "www.example.com", selector: ".ad", label: "广告")

        XCTAssertTrue(rule.applies(toHost: "example.com"))
        XCTAssertTrue(rule.applies(toHost: "WWW.example.com"))
        XCTAssertFalse(rule.applies(toHost: "docs.example.com"))
        // 站点为空时绝不能命中，否则规则会泄漏到所有页面上。
        XCTAssertFalse(rule.applies(toHost: nil))
    }

    func testSelectorWithBracesIsRejected() {
        // 选择器里出现花括号说明它已经不是选择器，拼进样式表会把后面的规则整片带坏。
        XCTAssertFalse(BrowserElementHidingScript.isUsableSelector(".ad { color: red }"))
        XCTAssertFalse(BrowserElementHidingScript.isUsableSelector("}"))
        XCTAssertFalse(BrowserElementHidingScript.isUsableSelector(".a\n.b"))
        XCTAssertFalse(BrowserElementHidingScript.isUsableSelector("   "))
        XCTAssertTrue(BrowserElementHidingScript.isUsableSelector("#main > .promo:nth-of-type(2)"))
    }

    func testRulesJSONDropsUnusableRulesAndStaysValidJSON() throws {
        let rules = [
            HiddenElementRule(host: "example.com", selector: "#promo", label: "促销条"),
            HiddenElementRule(host: "example.com", selector: ".ad { }", label: "坏规则"),
            HiddenElementRule(host: "", selector: ".sidebar", label: "没有站点")
        ]

        let json = BrowserElementHidingScript.rulesJSON(rules)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        )

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?["selector"], "#promo")
        XCTAssertEqual(decoded.first?["host"], "example.com")
    }

    func testEmptyRulesProduceEmptyJSONArray() {
        XCTAssertEqual(BrowserElementHidingScript.rulesJSON([]), "[]")
    }

    /// 老版本存下来的偏好里没有隐藏元素这个字段，必须仍然能解出来——
    /// 否则用户的缩放、置顶、窗口位置会跟着一起丢。
    func testLegacyPreferenceWithoutHiddenElementsStillDecodes() throws {
        let legacy = Data(#"{"pageZoom":1.2,"isPinned":true,"isMobileUA":false}"#.utf8)

        let preference = try JSONDecoder().decode(StoredWebAppPreference.self, from: legacy)

        XCTAssertEqual(preference.pageZoom, 1.2)
        XCTAssertTrue(preference.isPinned)
        XCTAssertTrue(preference.resolvedHiddenElements.isEmpty)
        XCTAssertTrue(preference.resolvedBookmarks.isEmpty)
    }

    func testHiddenElementsSurviveEncodeDecodeRoundTrip() throws {
        var preference = StoredWebAppPreference()
        preference.hiddenElements = [
            HiddenElementRule(host: "example.com", selector: "#promo", label: "促销条")
        ]

        let data = try JSONEncoder().encode(preference)
        let restored = try JSONDecoder().decode(StoredWebAppPreference.self, from: data)

        XCTAssertEqual(restored.resolvedHiddenElements.count, 1)
        XCTAssertEqual(restored.resolvedHiddenElements.first?.selector, "#promo")
    }

    /// 老版本存下来的偏好里没有收藏这个字段，必须仍然能解出来。
    func testLegacyPreferenceWithoutBookmarksStillDecodes() throws {
        let legacy = Data(#"{"pageZoom":1.2,"isPinned":true,"isMobileUA":false}"#.utf8)

        let preference = try JSONDecoder().decode(StoredWebAppPreference.self, from: legacy)

        XCTAssertTrue(preference.resolvedBookmarks.isEmpty)
    }

    func testBookmarksSurviveEncodeDecodeRoundTrip() throws {
        var preference = StoredWebAppPreference()
        preference.bookmarks = [
            WebAppBookmark(title: "文档", urlString: "https://example.com/docs")
        ]

        let data = try JSONEncoder().encode(preference)
        let restored = try JSONDecoder().decode(StoredWebAppPreference.self, from: data)

        XCTAssertEqual(restored.resolvedBookmarks.count, 1)
        XCTAssertEqual(restored.resolvedBookmarks.first?.title, "文档")
        XCTAssertEqual(restored.resolvedBookmarks.first?.urlString, "https://example.com/docs")
    }
}
