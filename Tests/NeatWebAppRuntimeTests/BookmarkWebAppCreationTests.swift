import WebKit
import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class BookmarkWebAppCreationTests: XCTestCase {
    func testRenamePreservesIdentityURLDateAndOtherBookmarks() throws {
        let (session, store) = try fixture()
        session.currentURL = try XCTUnwrap(URL(string: "https://example.com/private?view=one"))
        session.pageTitle = "Original"
        session.toggleCurrentPageBookmark()
        let original = try XCTUnwrap(session.bookmarks.first)
        let other = WebAppBookmark(title: "Other", urlString: "https://other.example/")
        session.currentURL = try XCTUnwrap(other.url)
        session.pageTitle = other.title
        session.toggleCurrentPageBookmark()

        XCTAssertFalse(session.renameBookmark(id: original.id, title: " \n "))
        XCTAssertFalse(session.renameBookmark(id: UUID(), title: "Unknown"))
        XCTAssertTrue(session.renameBookmark(id: original.id, title: "  Renamed 文档  "))
        let renamed = try XCTUnwrap(session.bookmarks.last)
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.urlString, original.urlString)
        XCTAssertEqual(renamed.createdAt, original.createdAt)
        XCTAssertEqual(renamed.title, "Renamed 文档")
        XCTAssertEqual(session.bookmarks.first?.title, other.title)
        XCTAssertEqual(store.load(for: session.definition.id).resolvedBookmarks, session.bookmarks)
        XCTAssertTrue(store.load(for: "unrelated").resolvedBookmarks.isEmpty)
    }

    func testCreateCopiesCookiesBeforeRegistrationAndKeepsStoresIndependent() async throws {
        let (session, _) = try fixture()
        let url = try XCTUnwrap(URL(string: "https://example.com/private?view=one"))
        session.currentURL = url
        session.pageTitle = "Renamed Workspace"
        session.toggleCurrentPageBookmark()
        let bookmark = try XCTUnwrap(session.bookmarks.first)
        let persistent = try cookie(name: "login", value: "fixture-only", persistent: true)
        let transient = try cookie(name: "session", value: "fixture-session", persistent: false)
        await session.websiteDataStore.httpCookieStore.setCookie(persistent)
        await session.websiteDataStore.httpCookieStore.setCookie(transient)
        var registered: WebAppDefinition?
        var copied: WKWebsiteDataStore?
        session.registerBookmarkWebApp = { definition in
            registered = definition
            let destination = WKWebsiteDataStore(forIdentifier: BrowserSession.websiteDataStoreIdentifier(for: definition.id))
            copied = destination
            let cookies = await destination.httpCookieStore.allCookies()
            XCTAssertEqual(cookies.count, 2)
            XCTAssertTrue(cookies.contains { $0.name == "login" && $0.isHTTPOnly && $0.isSecure })
            XCTAssertTrue(cookies.contains { $0.name == "session" && $0.isSessionOnly })
            XCTAssertTrue(session.isCreatingBookmarkWebApp)
            return true
        }

        await session.createWebApp(from: bookmark)

        let definition = try XCTUnwrap(registered)
        let destination = try XCTUnwrap(copied)
        XCTAssertNotEqual(definition.id, session.definition.id)
        XCTAssertEqual(definition.name, bookmark.title)
        XCTAssertEqual(definition.homeURL, url)
        XCTAssertNotEqual(destination.identifier, session.websiteDataStore.identifier)
        XCTAssertEqual(session.bookmarks, [bookmark])
        XCTAssertTrue(session.createdBookmarkIDs.contains(bookmark.id))
        XCTAssertFalse(session.isCreatingBookmarkWebApp)
        await destination.httpCookieStore.deleteCookie(persistent)
        let sourceCookies = await session.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertEqual(sourceCookies.count, 2)
        let destinationCookies = await destination.httpCookieStore.allCookies()
        XCTAssertEqual(destinationCookies.count, 1)
        await clear(destination)
        await clear(session.websiteDataStore)
    }

    func testFailedAcknowledgementRetriesSameAppWithoutRecopyingCookies() async throws {
        let (session, _) = try fixture()
        session.toggleCurrentPageBookmark()
        let bookmark = try XCTUnwrap(session.bookmarks.first)
        var requests: [WebAppDefinition] = []
        session.registerBookmarkWebApp = { definition in
            requests.append(definition)
            return requests.count > 1
        }

        await session.createWebApp(from: bookmark)
        XCTAssertTrue(session.createdBookmarkIDs.isEmpty)
        XCTAssertNotNil(session.bookmarkCreationNotice)
        let extra = try cookie(name: "later", value: "not-in-snapshot", persistent: false)
        await session.websiteDataStore.httpCookieStore.setCookie(extra)
        await session.createWebApp(from: bookmark)
        await session.createWebApp(from: bookmark)

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first, requests.last)
        let definition = try XCTUnwrap(requests.first)
        let destination = WKWebsiteDataStore(forIdentifier: BrowserSession.websiteDataStoreIdentifier(for: definition.id))
        let cookies = await destination.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.isEmpty)
        await clear(session.websiteDataStore)
        await clear(destination)
    }

    func testRepeatedCreateWhileRegistrationIsPendingDoesNotSubmitTwice() async throws {
        let (session, _) = try fixture()
        session.toggleCurrentPageBookmark()
        let bookmark = try XCTUnwrap(session.bookmarks.first)
        var requests: [WebAppDefinition] = []
        session.registerBookmarkWebApp = { definition in
            requests.append(definition)
            await session.createWebApp(from: bookmark)
            return true
        }
        await session.createWebApp(from: bookmark)
        XCTAssertEqual(requests.count, 1)
        let destination = try XCTUnwrap(requests.first)
        await clear(WKWebsiteDataStore(forIdentifier: BrowserSession.websiteDataStoreIdentifier(for: destination.id)))
        await clear(session.websiteDataStore)
    }

    func testClientStopResolvesAnOutstandingRequest() async throws {
        let bus = RuntimeCommandBus()
        let instanceID = UUID()
        let client = RuntimeBookmarkClient(instanceID: instanceID, sourceAppID: "fixture", commandBus: bus)
        let observer = bus.observeBookmarkRequests { request in
            if request.instanceID == instanceID { client.stop() }
        }
        defer { bus.removeObserver(observer) }
        let result = await client.register(try definition())
        XCTAssertFalse(result)
    }

    func testClientAcknowledgesTimesOutAndStops() async throws {
        let bus = RuntimeCommandBus()
        let instanceID = UUID()
        let client = RuntimeBookmarkClient(instanceID: instanceID, sourceAppID: "fixture", commandBus: bus, timeout: .milliseconds(100))
        let definition = try definition()
        let observer = bus.observeBookmarkRequests { request in
            guard request.instanceID == instanceID else { return }
            bus.send(RuntimeBookmarkResult(
                instanceID: instanceID, destinationAppID: request.definition.id, succeeded: true
            ))
        }
        let acknowledged = await client.register(definition)
        XCTAssertTrue(acknowledged)
        bus.removeObserver(observer)
        let timedOut = await client.register(definition)
        XCTAssertFalse(timedOut)
        client.stop()
        let stopped = await client.register(definition)
        XCTAssertFalse(stopped)
    }

    private func fixture() throws -> (BrowserSession, WebAppPreferencesStore) {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appending(path: id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: id))
        let store = WebAppPreferencesStore(userDefaults: defaults, rootDirectoryURL: root)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: id)
        }
        let session = BrowserSession(definition: try definition(), preference: StoredWebAppPreference(), preferencesStore: store)
        return (session, store)
    }

    private func definition() throws -> WebAppDefinition {
        WebAppDefinition(
            id: UUID().uuidString, name: "Fixture",
            homeURL: try XCTUnwrap(URL(string: "https://example.com/private?view=one")),
            accentColorName: "WebAppAccentBlue", shortDescription: ""
        )
    }

    private func cookie(name: String, value: String, persistent: Bool) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: "example.com", .path: "/",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]
        if persistent { properties[.expires] = Date(timeIntervalSince1970: 2_000_000_000) }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    private func clear(_ store: WKWebsiteDataStore) async {
        for cookie in await store.httpCookieStore.allCookies() {
            await store.httpCookieStore.deleteCookie(cookie)
        }
        if let id = store.identifier {
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }
}
