import Foundation
import XCTest
@testable import NeatWebApp

final class WebAppFaviconLoaderTests: XCTestCase {
    func testInvalidHighRankedImageFallsThroughToValidHTMLIcon() async throws {
        let data = await load(path: "/html")
        XCTAssertEqual(try XCTUnwrap(data), try XCTUnwrap(FaviconFixtureProtocol.pngData))
    }

    func testManifestRelativeIconIsResolvedAgainstManifestURL() async throws {
        let data = await load(path: "/manifest-page")
        XCTAssertEqual(try XCTUnwrap(data), try XCTUnwrap(FaviconFixtureProtocol.pngData))
    }

    func testNonImageResponseDoesNotEndCandidateSearch() async throws {
        let data = await load(path: "/wrong-type")
        XCTAssertEqual(try XCTUnwrap(data), try XCTUnwrap(FaviconFixtureProtocol.pngData))
    }

    func testAllUnavailableCandidatesReturnNil() async {
        let data = await load(path: "/missing")
        XCTAssertNil(data)
    }

    @MainActor
    func testCancelledRequestDoesNotReturnAnImage() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "https://icons.example/html"))
        let task = Task { await WebAppFaviconLoader.loadFaviconData(for: url, session: session) }
        task.cancel()
        let data = await task.value
        XCTAssertNil(data)
    }

    private func load(path: String) async -> Data? {
        guard let url = URL(string: "https://icons.example\(path)") else {
            XCTFail("Invalid fixture URL")
            return nil
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        return await WebAppFaviconLoader.loadFaviconData(for: url, session: session)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// No mutable shared state: each callback uses only its request and immutable fixtures.
/// URLProtocol's inherited Sendable contract requires the explicit restatement.
private final class FaviconFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let status: Int
        let mime: String
        let data: Data
        switch url.path {
        case "/html":
            status = 200
            mime = "text/html"
            data = Data("<link rel='apple-touch-icon' sizes='1024x1024' href='/broken.png'><link href='/assets/good.png' sizes='64x64' rel='icon'>".utf8)
        case "/manifest-page":
            status = 200
            mime = "text/html"
            data = Data("<link rel='manifest' href='/manifests/site.json'>".utf8)
        case "/manifests/site.json":
            status = 200
            mime = "application/manifest+json"
            data = Data("{\"icons\":[{\"src\":\"../assets/good.png\",\"sizes\":\"512x512\",\"type\":\"image/png\",\"purpose\":\"maskable any\"}]}".utf8)
        case "/wrong-type":
            status = 200
            mime = "text/html"
            data = Data("<link rel='icon' sizes='1024x1024' href='/not-image.png'><link rel='icon' sizes='64x64' href='/assets/good.png'>".utf8)
        case "/broken.png":
            status = 200
            mime = "image/png"
            data = Data("not a decodable PNG".utf8)
        case "/not-image.png":
            status = 200
            mime = "text/html"
            data = Data("<html>sign in</html>".utf8)
        case "/assets/good.png":
            status = 200
            mime = "image/png"
            guard let png = Self.pngData else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
                return
            }
            data = png
        default:
            status = 404
            mime = "text/html"
            data = Data("Not Found".utf8)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
