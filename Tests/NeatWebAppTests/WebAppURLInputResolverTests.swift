import XCTest
@testable import NeatWebApp

final class WebAppURLInputResolverTests: XCTestCase {
    func testAddsHTTPSchemeForBareHost() {
        let url = WebAppURLInputResolver.resolve("example.com")

        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testKeepsExplicitScheme() {
        let url = WebAppURLInputResolver.resolve("http://localhost:3000/path")

        XCTAssertEqual(url?.absoluteString, "http://localhost:3000/path")
    }

    func testTrimsWhitespace() {
        let url = WebAppURLInputResolver.resolve("  https://chatgpt.com  ")

        XCTAssertEqual(url?.absoluteString, "https://chatgpt.com")
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(WebAppURLInputResolver.resolve("   "))
    }
}
