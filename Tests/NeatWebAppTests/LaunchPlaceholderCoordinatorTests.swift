import AppKit
import XCTest
@testable import NeatWebApp

@MainActor
final class LaunchPlaceholderCoordinatorTests: XCTestCase {
    private var claude: WebAppDefinition {
        WebAppDefinition.examples.first { $0.id == "claude" }!
    }

    func testOpenNewWebAppShowsPlaceholderImmediately() {
        let fixture = makeFixture()

        fixture.coordinator.open(claude, preferredGeometry: nil)

        XCTAssertEqual(fixture.placeholder.shownAppIDs, [claude.id])
        XCTAssertEqual(fixture.launcher.launchedAppIDs, [claude.id])
        XCTAssertEqual(fixture.placeholder.shownFrames.count, 1)
        XCTAssertGreaterThan(fixture.placeholder.shownFrames[0].width, 0)
        XCTAssertGreaterThan(fixture.placeholder.shownFrames[0].height, 0)
        XCTAssertEqual(fixture.launcher.lastBootstrap?.restoredWindowFrame, fixture.placeholder.shownFrames[0])
    }

    func testPlaceholderFrameIsPassedThroughToRuntimeBootstrap() {
        let fixture = makeFixture()
        let savedFrame = CGRect(x: 180, y: 90, width: 649, height: 751)
        fixture.preferencesStore.save(
            StoredWebAppPreference(
                windowFrame: savedFrame,
                windowPlacement: StoredWindowPlacement(frame: savedFrame, display: nil)
            ),
            for: claude.id
        )

        fixture.coordinator.open(claude, preferredGeometry: nil)

        XCTAssertEqual(fixture.placeholder.shownFrames.first, fixture.launcher.lastBootstrap?.restoredWindowFrame)
        XCTAssertEqual(fixture.placeholder.shownFrames.first?.size, savedFrame.size)
    }

    func testWindowShownDismissesPlaceholder() async {
        let fixture = makeFixture()
        fixture.coordinator.open(claude, preferredGeometry: nil)

        fixture.commandBus.send(
            RuntimeEvent(
                instanceID: fixture.launcher.lastInstanceID!,
                appID: claude.id,
                sequence: 1,
                event: .windowShown,
                phase: .windowVisible,
                windowFrame: CGRect(x: 10, y: 20, width: 460, height: 900),
                floatingIconFrame: nil,
                lastUpdatedAt: Date()
            )
        )

        let dismissed = await waitUntil {
            fixture.placeholder.dismissedAppIDs.contains(self.claude.id)
        }
        XCTAssertTrue(dismissed)
    }

    func testLaunchErrorDismissesPlaceholder() async {
        let fixture = makeFixture()
        fixture.launcher.shouldFailLaunch = true

        fixture.coordinator.open(claude, preferredGeometry: nil)
        fixture.launcher.emitErrorIfNeeded()

        let dismissed = await waitUntil {
            fixture.placeholder.dismissedAppIDs.contains(self.claude.id)
        }
        XCTAssertTrue(dismissed)
    }

    func testExpandingCollapsedRuntimeDoesNotShowPlaceholder() throws {
        let fixture = makeFixture()
        let instanceID = UUID()
        try fixture.registryStore.saveState(
            RuntimeState(
                instanceID: instanceID,
                appID: claude.id,
                pid: ProcessInfo.processInfo.processIdentifier,
                phase: .collapsedToFloatingIcon,
                windowFrame: CGRect(x: 20, y: 40, width: 460, height: 900),
                floatingIconFrame: nil,
                lastUpdatedAt: Date()
            )
        )

        fixture.coordinator.refreshRegistry()
        fixture.coordinator.open(claude, preferredGeometry: nil)

        XCTAssertTrue(fixture.placeholder.shownAppIDs.isEmpty)
        XCTAssertTrue(fixture.launcher.launchedAppIDs.isEmpty)
    }

    func testOpenWhileLaunchingBringsPlaceholderForward() {
        let fixture = makeFixture()
        fixture.coordinator.open(claude, preferredGeometry: nil)
        fixture.coordinator.open(claude, preferredGeometry: nil)

        XCTAssertEqual(fixture.placeholder.shownAppIDs, [claude.id])
        XCTAssertEqual(fixture.placeholder.orderedFrontAppIDs, [claude.id])
        XCTAssertEqual(fixture.launcher.launchCount, 1)
    }

    func testPlaceholderFrameUsesSharedWindowMetrics() {
        let preference = StoredWebAppPreference()
        let screen = WebAppWindowPlacementScreen(
            displayID: 1,
            localizedName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            notchGeometry: nil
        )
        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: nil,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        XCTAssertEqual(frame.size, WebAppWindowMetrics.defaultFrameSize)
        XCTAssertEqual(BrowserChromeMetrics.bandHeight, 40)
        XCTAssertEqual(
            WebAppWindowMetrics.defaultFrameSize,
            WebAppWindowMetrics.frameSize(forContentSize: WebAppWindowMetrics.defaultContentSize)
        )
        XCTAssertGreaterThan(WebAppWindowMetrics.defaultFrameSize.width, 0)
        XCTAssertGreaterThan(WebAppWindowMetrics.defaultFrameSize.height, 0)
    }

    private func makeFixture() -> Fixture {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppPlaceholderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let registryStore = RuntimeRegistryStore(rootDirectoryURL: tempRoot)
        let launcher = FakeRuntimeLauncher()
        let placeholder = FakeLaunchPlaceholderPresenter()
        let commandBus = RuntimeCommandBus()
        let defaults = UserDefaults(suiteName: "NeatWebAppPlaceholderTests-\(UUID().uuidString)")!
        let preferencesStore = WebAppPreferencesStore(userDefaults: defaults)
        let coordinator = WebAppRuntimeCoordinator(
            registryStore: registryStore,
            launcher: launcher,
            commandBus: commandBus,
            placeholderPresenter: placeholder,
            preferencesStore: preferencesStore,
            runtimeHealthPolicy: RuntimeHealthPolicy(
                checkInterval: .seconds(60),
                minimumRuntimeAge: 60,
                consecutiveViolationLimit: 0,
                cpuPercentLimit: 100,
                residentMemoryLimitBytes: RuntimeHealthPolicy.gibibyte,
                physicalFootprintLimitBytes: RuntimeHealthPolicy.gibibyte
            ),
            onActiveAppIDChange: { _ in },
            onDiagnosticMessage: { _ in }
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        return Fixture(
            coordinator: coordinator,
            launcher: launcher,
            placeholder: placeholder,
            registryStore: registryStore,
            commandBus: commandBus,
            preferencesStore: preferencesStore
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class FakeRuntimeLauncher: RuntimeLaunching {
    var launchedAppIDs: [String] = []
    var lastInstanceID: UUID?
    var lastBootstrap: RuntimeBootstrap?
    var launchCount = 0
    var shouldFailLaunch = false
    private var pendingError: (@MainActor (String) -> Void)?

    func launch(
        _ bootstrap: RuntimeBootstrap,
        onError: @escaping @MainActor (String) -> Void
    ) throws {
        launchCount += 1
        launchedAppIDs.append(bootstrap.appID)
        lastInstanceID = bootstrap.instanceID
        lastBootstrap = bootstrap
        if shouldFailLaunch {
            pendingError = onError
        }
    }

    func emitErrorIfNeeded() {
        pendingError?("启动失败")
        pendingError = nil
    }

    func currentRuntimeBuildIdentifier() throws -> String {
        "test-runtime"
    }
}

@MainActor
private final class FakeLaunchPlaceholderPresenter: LaunchPlaceholderPresenting {
    var shownAppIDs: [String] = []
    var shownFrames: [CGRect] = []
    var orderedFrontAppIDs: [String] = []
    var dismissedAppIDs: [String] = []

    func showPlaceholder(for definition: WebAppDefinition, frame: CGRect) {
        shownAppIDs.append(definition.id)
        shownFrames.append(frame)
    }

    func orderPlaceholderFront(appID: String) {
        orderedFrontAppIDs.append(appID)
    }

    func dismissPlaceholder(appID: String) {
        dismissedAppIDs.append(appID)
    }

    func dismissAllPlaceholders() {
        dismissedAppIDs.append(contentsOf: shownAppIDs)
    }
}

private struct Fixture {
    let coordinator: WebAppRuntimeCoordinator
    let launcher: FakeRuntimeLauncher
    let placeholder: FakeLaunchPlaceholderPresenter
    let registryStore: RuntimeRegistryStore
    let commandBus: RuntimeCommandBus
    let preferencesStore: WebAppPreferencesStore
}
