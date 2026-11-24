import WebKit
import XCTest
@testable import NeatWebAppAppStore

#if !APP_STORE
#error("APP_STORE compilation condition must be set for NeatWebAppAppStoreTests")
#endif

@MainActor
final class AppStoreChannelTests: XCTestCase {
    func testUserScriptsContainNoElementHiding() {
        let controller = WKUserContentController()
        BrowserUserScripts.install(into: controller)

        let joined = controller.userScripts.map(\.source).joined(separator: "\n")
        XCTAssertTrue(joined.contains("__neatWebAppThemeObserverInstalled"))
        XCTAssertTrue(joined.contains("__neatWebAppPasskeyProbeInstalled"))
        XCTAssertFalse(joined.contains("neatElementHiding"))
        XCTAssertFalse(joined.contains("__neatWebAppElementHiding"))
        XCTAssertFalse(joined.contains("antonmedv/finder"))
    }

    func testInProcessCoordinatorManagesMultipleWindowsAndIsolatedClosing() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "NeatWebAppStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferencesStore = WebAppPreferencesStore(userDefaults: defaults, rootDirectoryURL: tempRoot)
        let dockReserveStore = SideDockReserveStore(rootDirectoryURL: tempRoot)
        var publishedStates: [[RuntimeState]] = []
        var activeAppIDs: [String?] = []

        let coordinator = InProcessWebAppRuntimeCoordinator(
            preferencesStore: preferencesStore,
            dockReserveStore: dockReserveStore,
            onActiveAppIDChange: { activeAppIDs.append($0) },
            onDiagnosticMessage: { _ in },
            onRuntimeStatesChange: { publishedStates.append($0) }
        )
        defer { coordinator.terminateAll() }

        let firstApp = WebAppDefinition(
            id: "first-app",
            name: "First App",
            homeURL: try XCTUnwrap(URL(string: "https://example.com/one")),
            accentColorName: "WebAppAccentBlue",
            shortDescription: ""
        )
        let secondApp = WebAppDefinition(
            id: "second-app",
            name: "Second App",
            homeURL: try XCTUnwrap(URL(string: "https://example.com/two")),
            accentColorName: "WebAppAccentGreen",
            shortDescription: ""
        )

        coordinator.open(firstApp, preferredGeometry: nil)
        coordinator.open(firstApp, preferredGeometry: nil)
        XCTAssertEqual(coordinator.openAppIDs, ["first-app"])
        XCTAssertEqual(coordinator.phase(for: "first-app"), .windowVisible)

        coordinator.open(secondApp, preferredGeometry: nil)
        XCTAssertEqual(coordinator.openAppIDs, ["first-app", "second-app"])
        XCTAssertEqual(publishedStates.last?.count, 2)

        coordinator.collapse(appID: firstApp.id)
        XCTAssertEqual(coordinator.phase(for: firstApp.id), .collapsedToFloatingIcon)
        XCTAssertEqual(coordinator.openAppIDs, ["first-app", "second-app"])

        coordinator.reloadDefinition(WebAppDefinition(
            id: firstApp.id,
            name: "First Renamed",
            homeURL: firstApp.homeURL,
            accentColorName: firstApp.accentColorName,
            shortDescription: ""
        ))

        let dummyController = WebAppWindowController(
            definition: firstApp,
            preferencesStore: preferencesStore,
            preferredGeometry: nil,
            eventSink: coordinator,
            dockReserveStore: dockReserveStore,
            restoredWindowFrame: nil,
            lockRestoredFrame: false
        )
        coordinator.webAppWindowDidRequestClose(dummyController)
        XCTAssertEqual(coordinator.openAppIDs, ["second-app"])

        coordinator.terminate(appID: secondApp.id)
        XCTAssertTrue(coordinator.openAppIDs.isEmpty)
        XCTAssertNil(activeAppIDs.last ?? nil)
    }

    func testPreferencesStoreAndFaviconStoreStayInAppStoreContainer() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppStoreIsolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suiteName = "NeatWebAppStoreIsolation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferencesStore = WebAppPreferencesStore(userDefaults: defaults, rootDirectoryURL: tempRoot)
        let loaded = preferencesStore.load(for: "nonexistent")
        XCTAssertEqual(loaded, StoredWebAppPreference())

        let faviconStore = WebAppFaviconStore()
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        faviconStore.saveDockSource(image, for: "appstore-test-icon")
        defer { faviconStore.delete(for: "appstore-test-icon") }

        let appSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let expectedPath = appSupport
            .appending(path: "com.caozc.NeatWebApp", directoryHint: .isDirectory)
            .appending(path: "DockSources", directoryHint: .isDirectory)
            .appending(path: "appstore-test-icon.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
    }

    func testBundleMetadataMatchesAppStoreChannel() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["DistributionChannel"] as? String, "app-store")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertTrue(info.keys.filter { $0.hasPrefix("SU") }.isEmpty)
    }
}
