import WebKit
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
        XCTAssertTrue(BrowserElementHidingScript.isUsableSelector(#":is([class^="FeedbackBar_feedback-bar_"],[class*=" FeedbackBar_feedback-bar_"])"#))
        XCTAssertTrue(BrowserElementHidingScript.isUsableSelector(#"div:has(> a[href="/download"])"#))
        XCTAssertTrue(BrowserElementHidingScript.isUsableSelector(#"button[aria-label="放大"]"#))
    }

    func testRulesJSONDropsUnusableRulesAndStaysValidJSON() throws {
        let rules = [
            HiddenElementRule(host: "example.com", selector: "#promo", label: "促销条"),
            HiddenElementRule(host: "example.com", selector: ":is([class^=\"FeedbackBar_feedback-bar_\"],[class*=\" FeedbackBar_feedback-bar_\"])", label: "反馈条"),
            HiddenElementRule(host: "example.com", selector: "div:has(> a[href=\"/download\"])", label: "下载条"),
            HiddenElementRule(host: "example.com", selector: "button[aria-label=\"放大\"]", label: "放大"),
            HiddenElementRule(host: "example.com", selector: ".ad { }", label: "坏规则"),
            HiddenElementRule(host: "", selector: ".sidebar", label: "没有站点")
        ]

        let json = BrowserElementHidingScript.rulesJSON(rules)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        )

        XCTAssertEqual(decoded.count, 4)
        XCTAssertEqual(decoded.map { $0["selector"] }, [
            "#promo",
            ":is([class^=\"FeedbackBar_feedback-bar_\"],[class*=\" FeedbackBar_feedback-bar_\"])",
            "div:has(> a[href=\"/download\"])",
            "button[aria-label=\"放大\"]"
        ])
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

    @MainActor
    func testGeekTimeCSSModulesSurviveSiblingShiftsAndHashRotation() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div id="app">
            <div class="light">
              <div class="main">
                <div class="article-body">Article Body</div>
                <div class="PreviewImg_main_20ld2 PreviewImg_on_hVX44">Preview</div>
                <div data-probe="target-feedback" class="FeedbackBar_feedback-bar_kyjNx">Feedback</div>
                <div class="ArticleMobilePreview_audioPlayer_wpvvv">Audio</div>
              </div>
            </div>
          </div>
        </body>
        </html>
        """
        let webView = try await loadInjectedWebView(html: html)
        let selector = try await generateSelector(in: webView, query: "[data-probe=\"target-feedback\"]")

        XCTAssertTrue(selector.contains("FeedbackBar_feedback-bar_"), "Expected hash-free CSS module prefix, got: \(selector)")
        XCTAssertFalse(selector.contains("kyjNx"), "Selector must strip CSS module hash: \(selector)")
        XCTAssertFalse(selector.contains(":nth-of-type"), "Selector must avoid volatile nth-of-type: \(selector)")
        XCTAssertFalse(selector.contains(".light"), "Selector must ignore theme class: \(selector)")

        let previewSelector = try await generateSelector(in: webView, query: ".PreviewImg_main_20ld2")
        XCTAssertTrue(previewSelector.contains("PreviewImg_main_"), "Expected PreviewImg_main_ prefix, got: \(previewSelector)")
        XCTAssertFalse(previewSelector.contains("PreviewImg_on_"), "Selector must ignore state CSS module class PreviewImg_on_: \(previewSelector)")

        // Simulate next GeekTime article / deploy: prepend conditional v-if siblings, rotate hash, flip light->dark
        let mutationJS = """
        (() => {
            const themeWrap = document.querySelector('.light');
            themeWrap.className = 'dark';
            const main = document.querySelector('.main');
            const promo1 = document.createElement('div');
            promo1.textContent = 'Conditional Banner 1';
            const promo2 = document.createElement('div');
            promo2.textContent = 'Conditional Banner 2';
            main.insertBefore(promo1, main.firstChild);
            main.insertBefore(promo2, main.firstChild);
            const target = document.querySelector('[data-probe="target-feedback"]');
            target.className = 'FeedbackBar_feedback-bar_9xAb2';
            const matches = Array.from(document.querySelectorAll(\(jsLiteral(selector))));
            return matches.length === 1 && matches[0].dataset.probe === 'target-feedback';
        })()
        """
        let stillMatchesTarget = try await evaluateBool(mutationJS, in: webView)
        XCTAssertTrue(stillMatchesTarget)
    }

    @MainActor
    func testAnonymousWrapperUsesHasFingerprintWithoutPositionalIndex() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div id="app">
            <div class="main">
              <div>Header</div>
              <div>Article Content</div>
              <div>Sidebar Card</div>
              <div data-probe="target-wrapper"><div class="OpenApp_banner_3xK9a">打开APP</div></div>
            </div>
          </div>
        </body>
        </html>
        """
        let webView = try await loadInjectedWebView(html: html)
        let selector = try await generateSelector(in: webView, query: "[data-probe=\"target-wrapper\"]")

        XCTAssertTrue(selector.contains(":has("), "Expected :has() fingerprint for anonymous wrapper, got: \(selector)")
        XCTAssertTrue(selector.contains("OpenApp_banner_"), "Expected child CSS module prefix in :has(), got: \(selector)")
        XCTAssertFalse(selector.contains(":nth-of-type"), "Selector must not rely on :nth-of-type: \(selector)")

        let mutationJS = """
        (() => {
            const main = document.querySelector('.main');
            const extra = document.createElement('div');
            extra.textContent = 'Dynamic Notice';
            main.insertBefore(extra, main.firstChild);
            const matches = Array.from(document.querySelectorAll(\(jsLiteral(selector))));
            return matches.length === 1 && matches[0].dataset.probe === 'target-wrapper';
        })()
        """
        let stillMatchesWrapper = try await evaluateBool(mutationJS, in: webView)
        XCTAssertTrue(stillMatchesWrapper)
    }

    @MainActor
    func testZoomEarthUsesLocalizedAriaLabelAndTitleIgnoringLayerStateClass() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div class="layer-satellite">
            <button data-probe="btn-search" aria-label="搜索">搜索</button>
            <button data-probe="btn-zoom" title="放大">+</button>
            <button data-probe="btn-settings" aria-label="设置">设置</button>
          </div>
        </body>
        </html>
        """
        let webView = try await loadInjectedWebView(html: html)
        let selector = try await generateSelector(in: webView, query: "[data-probe=\"btn-search\"]")

        XCTAssertTrue(selector.contains(#"[aria-label="搜索"]"#), "Expected aria-label selector, got: \(selector)")
        XCTAssertFalse(selector.contains("layer-satellite"), "Selector must not depend on layer-* state class: \(selector)")
        XCTAssertFalse(selector.contains(":nth-of-type"), "Selector must not depend on button index: \(selector)")

        let mutationJS = """
        (() => {
            const container = document.querySelector('.layer-satellite');
            container.className = 'layer-radar';
            const searchBtn = document.querySelector('[data-probe="btn-search"]');
            const settingsBtn = document.querySelector('[data-probe="btn-settings"]');
            container.insertBefore(settingsBtn, searchBtn);
            const matches = Array.from(document.querySelectorAll(\(jsLiteral(selector))));
            return matches.length === 1 && matches[0].dataset.probe === 'btn-search';
        })()
        """
        let stillMatchesSearch = try await evaluateBool(mutationJS, in: webView)
        XCTAssertTrue(stillMatchesSearch)
    }

    @MainActor
    func testGenericControlsClassIsScopedToSpecificComponentAncestor() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div class="ShareCard_root_Ab12c">
            <div data-probe="target-controls" class="controls">分享赚 ¥18</div>
          </div>
        </body>
        </html>
        """
        let webView = try await loadInjectedWebView(html: html)
        let selector = try await generateSelector(in: webView, query: "[data-probe=\"target-controls\"]")

        XCTAssertNotEqual(selector, ".controls", "Must never emit bare generic .controls selector")
        XCTAssertTrue(selector.contains("ShareCard_root_"), "Expected ShareCard_root_ ancestor scope, got: \(selector)")

        let mutationJS = """
        (() => {
            const player = document.createElement('div');
            player.className = 'video-player';
            const playerControls = document.createElement('div');
            playerControls.className = 'controls';
            playerControls.textContent = 'Play';
            player.appendChild(playerControls);
            document.body.appendChild(player);
            const matches = Array.from(document.querySelectorAll(\(jsLiteral(selector))));
            return matches.length === 1 && matches[0].dataset.probe === 'target-controls';
        })()
        """
        let onlyMatchesTarget = try await evaluateBool(mutationJS, in: webView)
        XCTAssertTrue(onlyMatchesTarget)
    }

    @MainActor
    func testUnidentifiableBarePositionalElementIsRejectedInsteadOfFragileNthRule() async throws {
        let html = """
        <!doctype html>
        <html>
        <body>
          <div id="article-content-container">
            <div><div>First</div></div>
            <div><div data-probe="bare-target">Second</div></div>
          </div>
        </body>
        </html>
        """
        let webView = try await loadInjectedWebView(html: html)
        let selector = try await generateSelector(in: webView, query: "[data-probe=\"bare-target\"]")
        XCTAssertEqual(selector, "", "Expected empty selector refusal for unidentifiable bare positional element, got: \(selector)")
    }

    @MainActor
    private func loadInjectedWebView(html: String) async throws -> WKWebView {
        let controller = WKUserContentController()
        controller.addUserScript(BrowserElementHidingScript.makeUserScript(rules: []))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController = controller
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        let delegate = TestNavigationDelegate()
        webView.navigationDelegate = delegate
        try await delegate.load(html: html, in: webView)
        return webView
    }

    @MainActor
    private func generateSelector(in webView: WKWebView, query: String) async throws -> String {
        let script = """
        (() => {
            const el = document.querySelector(\(jsLiteral(query)));
            return el ? (window.__neatWebAppElementHiding?.generateSelector(el) || '') : '';
        })()
        """
        let result = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(result as? String)
    }

    @MainActor
    private func evaluateBool(_ script: String, in webView: WKWebView) async throws -> Bool {
        let result = try await webView.evaluateJavaScript(script)
        return (result as? Bool) ?? ((result as? NSNumber)?.boolValue ?? false)
    }

    private func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let raw = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(raw.dropFirst().dropLast())
    }
}

@MainActor
private final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://time.geekbang.org/column/article/123"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
