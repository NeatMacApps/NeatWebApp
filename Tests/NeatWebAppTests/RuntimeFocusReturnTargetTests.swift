import AppKit
import XCTest
@testable import NeatWebApp

final class RuntimeFocusReturnTargetTests: XCTestCase {
    func testOldCommandsDecodeWithoutFocusReturnIdentity() throws {
        let command = RuntimeCommand(instanceID: UUID(), appID: "a", sequence: 1, command: .focusWindow, definition: nil)
        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RuntimeCommand.self, from: encoded)
        XCTAssertNil(decoded.focusReturnTarget)
    }

    func testFocusReturnIdentityRoundTripsInCommandsAndBootstraps() throws {
        let target = RuntimeFocusReturnTarget(processID: 123, launchDate: Date(timeIntervalSince1970: 10), bundleIdentifier: "example.editor")
        let command = RuntimeCommand(instanceID: UUID(), appID: "a", sequence: 1, command: .focusWindow, definition: nil, focusReturnTarget: target)
        XCTAssertEqual(try JSONDecoder().decode(RuntimeCommand.self, from: JSONEncoder().encode(command)).focusReturnTarget, target)
        let bootstrap = RuntimeBootstrap(
            instanceID: UUID(), appID: "a",
            definition: WebAppDefinition(id: "a", name: "A", homeURL: URL(fileURLWithPath: "/tmp/a"), accentColorName: "blue", shortDescription: ""),
            launchReason: .openFromLauncher, preferredDisplayID: nil, runtimeBuildIdentifier: "test-runtime",
            restoredPhase: nil, restoredWindowFrame: nil, restoredFloatingIconFrame: nil,
            createdAt: .now, hostVersion: "test", focusReturnTarget: target
        )
        XCTAssertEqual(try JSONDecoder().decode(RuntimeBootstrap.self, from: JSONEncoder().encode(bootstrap)).focusReturnTarget, target)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bootstrap)) as? [String: Any])
        legacy.removeValue(forKey: "focusReturnTarget")
        XCTAssertNil(try JSONDecoder().decode(RuntimeBootstrap.self, from: JSONSerialization.data(withJSONObject: legacy)).focusReturnTarget)
    }

}
