import AppKit
import XCTest
@testable import NeatWebApp

final class WebAppSwitchingHistoryTests: XCTestCase {
    func testNoRuntimeHasNoSwitcherTarget() {
        XCTAssertNil(WebAppSwitchingHistory().restorationTarget(in: []))
    }

    func testEveryLivePhaseCanBeRestored() {
        for phase: RuntimePhase in [.launching, .windowVisible, .collapsedToFloatingIcon, .hidden] {
            XCTAssertEqual(WebAppSwitchingHistory().restorationTarget(in: [state("a", phase)])?.appID, "a")
        }
        XCTAssertNil(WebAppSwitchingHistory().restorationTarget(in: [state("a", .terminating)]))
    }

    func testCollapseTimestampDoesNotReplaceFocusHistory() {
        var history = WebAppSwitchingHistory()
        history.recordFocus(appID: "a")
        history.recordFocus(appID: "b")
        let states = [state("a", .collapsedToFloatingIcon, time: 100), state("b", .hidden, time: 10)]
        history.retainRunningApps(in: states)
        XCTAssertEqual(history.restorationTarget(in: states)?.appID, "b")
    }

    func testTerminatedAppFallsBackToNextMostRecentlyFocusedSurvivor() {
        var history = WebAppSwitchingHistory()
        for appID in ["a", "b", "c", "b"] { history.recordFocus(appID: appID) }
        let states = [state("a", .windowVisible, time: 100), state("b", .terminating), state("c", .hidden)]
        history.retainRunningApps(in: states)
        XCTAssertEqual(history.restorationTarget(in: states)?.appID, "c")
    }

    func testRegistryTakeoverUsesNewestStateAndStableTieBreak() {
        let history = WebAppSwitchingHistory()
        XCTAssertEqual(history.restorationTarget(in: [state("a", .hidden), state("b", .hidden, time: 5)])?.appID, "b")
        XCTAssertEqual(history.restorationTarget(in: [state("b", .hidden), state("a", .hidden)])?.appID, "a")
    }

    func testExitedAppDoesNotRetainItsOldFocusRankWhenRelaunched() {
        var history = WebAppSwitchingHistory()
        history.recordFocus(appID: "a")
        history.retainRunningApps(in: [])
        XCTAssertEqual(history.restorationTarget(in: [state("a", .hidden), state("b", .hidden, time: 5)])?.appID, "b")
    }

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

    @MainActor
    func testDockReopenWithRunningWebAppsDoesNotOpenManagementWindow() {
        let delegate = AppDelegate()
        var managementOpened = false
        delegate.hasRunningWebApps = { true }
        delegate.installMainWindowPresenter { managementOpened = true }
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertFalse(managementOpened)
    }

    private func state(_ appID: String, _ phase: RuntimePhase, time: TimeInterval = 1) -> RuntimeState {
        RuntimeState(instanceID: UUID(), appID: appID, pid: 1, phase: phase, windowFrame: nil, floatingIconFrame: nil, lastUpdatedAt: Date(timeIntervalSince1970: time))
    }
}
