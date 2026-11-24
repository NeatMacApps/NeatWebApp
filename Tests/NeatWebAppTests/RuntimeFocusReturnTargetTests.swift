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

    func testDockPreferencesRoundTripAndDefaultTrueForLegacyPayloads() throws {
        let bootstrap = RuntimeBootstrap(
            instanceID: UUID(),
            appID: "a",
            definition: WebAppDefinition(id: "a", name: "A", homeURL: URL(fileURLWithPath: "/tmp/a"), accentColorName: "blue", shortDescription: ""),
            launchReason: .openFromLauncher,
            preferredDisplayID: nil,
            runtimeBuildIdentifier: "test-runtime",
            restoredPhase: nil,
            restoredWindowFrame: nil,
            restoredFloatingIconFrame: nil,
            createdAt: .now,
            hostVersion: "test",
            showInSystemDock: false,
            isFloatingDockEnabled: false
        )
        let decodedBootstrap = try JSONDecoder().decode(RuntimeBootstrap.self, from: JSONEncoder().encode(bootstrap))
        XCTAssertEqual(decodedBootstrap.showInSystemDock, false)
        XCTAssertEqual(decodedBootstrap.isFloatingDockEnabled, false)
        XCTAssertFalse(decodedBootstrap.resolvedShowInSystemDock)
        XCTAssertFalse(decodedBootstrap.resolvedIsFloatingDockEnabled)

        var legacyBootstrap = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bootstrap)) as? [String: Any])
        legacyBootstrap.removeValue(forKey: "showInSystemDock")
        legacyBootstrap.removeValue(forKey: "isFloatingDockEnabled")
        let decodedLegacy = try JSONDecoder().decode(RuntimeBootstrap.self, from: JSONSerialization.data(withJSONObject: legacyBootstrap))
        XCTAssertTrue(decodedLegacy.resolvedShowInSystemDock)
        XCTAssertTrue(decodedLegacy.resolvedIsFloatingDockEnabled)

        let command = RuntimeCommand(
            instanceID: UUID(),
            appID: "a",
            sequence: 2,
            command: .updateDockPreferences,
            definition: nil,
            showInSystemDock: false,
            isFloatingDockEnabled: true
        )
        let decodedCommand = try JSONDecoder().decode(RuntimeCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(decodedCommand.command, .updateDockPreferences)
        XCTAssertEqual(decodedCommand.showInSystemDock, false)
        XCTAssertEqual(decodedCommand.isFloatingDockEnabled, true)
    }

}
