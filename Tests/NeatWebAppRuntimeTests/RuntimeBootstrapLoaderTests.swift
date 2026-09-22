import XCTest
@testable import NeatWebAppRuntime

final class RuntimeBootstrapLoaderTests: XCTestCase {
    func testHostProcessIdentifierParsesPositivePID() {
        XCTAssertEqual(
            RuntimeBootstrapLoader.processIdentifier(
                after: "--host-pid",
                in: ["NeatWebAppRuntime", "--host-pid", "60663"]
            ),
            60663
        )
    }

    func testHostProcessIdentifierRejectsMissingOrInvalidPID() {
        XCTAssertNil(RuntimeBootstrapLoader.processIdentifier(after: "--host-pid", in: []))
        XCTAssertNil(
            RuntimeBootstrapLoader.processIdentifier(
                after: "--host-pid",
                in: ["NeatWebAppRuntime", "--host-pid", "0"]
            )
        )
        XCTAssertNil(
            RuntimeBootstrapLoader.processIdentifier(
                after: "--host-pid",
                in: ["NeatWebAppRuntime", "--host-pid", "not-a-pid"]
            )
        )
    }
}
