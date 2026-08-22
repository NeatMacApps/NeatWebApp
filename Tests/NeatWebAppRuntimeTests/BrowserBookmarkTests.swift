import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class BrowserBookmarkTests: XCTestCase {
    func testCanonicalURLDropsFragmentAndTrailingSlash() {
        let page = URL(string: "https://example.com/docs/#intro")!
        let slash = URL(string: "https://Example.com/docs/")!

        XCTAssertEqual(
            WebAppBookmark.canonicalURLString(page),
            "https://example.com/docs"
        )
        XCTAssertEqual(
            WebAppBookmark.canonicalURLString(slash),
            "https://example.com/docs"
        )
    }

    func testCanonicalURLKeepsQueryAndRootPath() {
        let withQuery = URL(string: "https://example.com/search?q=neat")!
        let root = URL(string: "https://example.com/")!

        XCTAssertEqual(
            WebAppBookmark.canonicalURLString(withQuery),
            "https://example.com/search?q=neat"
        )
        XCTAssertEqual(
            WebAppBookmark.canonicalURLString(root),
            "https://example.com/"
        )
    }

    func testCanonicalURLRejectsNonWebSchemes() {
        XCTAssertNil(WebAppBookmark.canonicalURLString(URL(string: "about:blank")!))
        XCTAssertNil(WebAppBookmark.canonicalURLString(URL(string: "file:///tmp/page.html")!))
    }

    func testBookmarkMatchesCanonicalVariantsOnly() {
        let bookmark = WebAppBookmark(
            title: "文档",
            urlString: "https://example.com/docs"
        )

        XCTAssertTrue(bookmark.matches(URL(string: "https://example.com/docs/#intro")!))
        XCTAssertTrue(bookmark.matches(URL(string: "https://example.com/docs/")!))
        XCTAssertFalse(bookmark.matches(URL(string: "https://example.com/other")!))
        XCTAssertFalse(bookmark.matches(URL(string: "http://example.com/docs")!))
    }

    func testToggleCurrentPageBookmarkStaysOnThisWebApp() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppBookmarkSession-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppBookmarkSession-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: tempRoot
        )
        let claude = WebAppDefinition.examples.first { $0.id == "claude" }!
        let session = BrowserSession(
            definition: claude,
            preference: StoredWebAppPreference(),
            preferencesStore: store
        )
        session.currentURL = URL(string: "https://claude.ai/new")!
        session.pageTitle = "新对话"

        session.toggleCurrentPageBookmark()

        XCTAssertTrue(session.isCurrentPageBookmarked)
        XCTAssertEqual(store.load(for: "claude").resolvedBookmarks.map(\.urlString), [
            "https://claude.ai/new"
        ])
        XCTAssertTrue(store.load(for: "chatgpt").resolvedBookmarks.isEmpty)

        session.toggleCurrentPageBookmark()

        XCTAssertFalse(session.isCurrentPageBookmarked)
        XCTAssertTrue(store.load(for: "claude").resolvedBookmarks.isEmpty)
    }
}
