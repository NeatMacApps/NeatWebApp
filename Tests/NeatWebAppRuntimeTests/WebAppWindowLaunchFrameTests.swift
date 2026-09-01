import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class WebAppWindowLaunchFrameTests: XCTestCase {
    func testHostProvidedFrameSurvivesAttachingThePage() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppLaunchFrame-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppLaunchFrame-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: tempRoot
        )
        let intended = CGRect(x: 180, y: 90, width: 420, height: 680)
        let controller = WebAppWindowController(
            definition: WebAppDefinition(
                id: "gemini-launch-frame",
                name: "Gemini",
                homeURL: URL(string: "https://gemini.google.com/app")!,
                accentColorName: "WebAppAccentBlue",
                shortDescription: "gemini.google.com"
            ),
            preferencesStore: store,
            preferredGeometry: nil,
            eventSink: nil,
            restoredWindowFrame: intended,
            lockRestoredFrame: true
        )
        addTeardownBlock {
            controller.window?.orderOut(nil)
            controller.window?.close()
        }

        XCTAssertEqual(controller.window?.frame.width ?? 0, intended.width, accuracy: 1)
        XCTAssertEqual(controller.window?.frame.height ?? 0, intended.height, accuracy: 1)

        controller.showAndFocus()

        XCTAssertEqual(controller.window?.frame.width ?? 0, intended.width, accuracy: 1)
        XCTAssertEqual(controller.window?.frame.height ?? 0, intended.height, accuracy: 1)
        XCTAssertEqual(controller.window?.frame.minX ?? 0, intended.minX, accuracy: 1)
        XCTAssertEqual(controller.window?.frame.minY ?? 0, intended.minY, accuracy: 1)
    }

    func testFillDesktopBootstrapDoesNotKeepAFullScreenWindow() {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppFillFrame-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let defaults = UserDefaults(suiteName: "NeatWebAppFillFrame-\(UUID().uuidString)")!
        let store = WebAppPreferencesStore(
            userDefaults: defaults,
            rootDirectoryURL: tempRoot
        )
        guard let visibleFrame = NSScreen.screens.first?.visibleFrame else {
            XCTFail("需要至少一块屏幕")
            return
        }

        let controller = WebAppWindowController(
            definition: WebAppDefinition(
                id: "gemini-fill-frame",
                name: "Gemini",
                homeURL: URL(string: "https://gemini.google.com/app")!,
                accentColorName: "WebAppAccentBlue",
                shortDescription: "gemini.google.com"
            ),
            preferencesStore: store,
            preferredGeometry: nil,
            eventSink: nil,
            restoredWindowFrame: visibleFrame,
            lockRestoredFrame: true
        )
        addTeardownBlock {
            controller.window?.orderOut(nil)
            controller.window?.close()
        }

        let frame = controller.window?.frame ?? .zero
        XCTAssertFalse(
            WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: visibleFrame)
        )
        XCTAssertEqual(frame.width, WebAppWindowMetrics.defaultFrameSize.width, accuracy: 1)
        XCTAssertLessThan(frame.height, visibleFrame.height)
    }
}

final class SideDockWindowAvoidanceTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1446, height: 949)
    private let thickness: CGFloat = 47

    func testRightEdgeInsetsTheFullStrip() {
        let usable = SideDockWindowAvoidance.usableFrame(
            visibleFrame: visibleFrame,
            reserve: SideDockScreenReserve(edge: .right, displayID: 1, thickness: thickness),
            screenDisplayID: 1
        )

        XCTAssertEqual(usable.minX, visibleFrame.minX)
        XCTAssertEqual(usable.maxX, visibleFrame.maxX - thickness)
        XCTAssertEqual(usable.height, visibleFrame.height)
    }

    func testLeftEdgeInsetsTheFullStrip() {
        let usable = SideDockWindowAvoidance.usableFrame(
            visibleFrame: visibleFrame,
            reserve: SideDockScreenReserve(edge: .left, displayID: 1, thickness: thickness),
            screenDisplayID: 1
        )

        XCTAssertEqual(usable.minX, visibleFrame.minX + thickness)
        XCTAssertEqual(usable.width, visibleFrame.width - thickness)
    }

    func testBottomEdgeInsetsTheFullStrip() {
        let usable = SideDockWindowAvoidance.usableFrame(
            visibleFrame: visibleFrame,
            reserve: SideDockScreenReserve(edge: .bottom, displayID: 1, thickness: thickness),
            screenDisplayID: 1
        )

        XCTAssertEqual(usable.minY, visibleFrame.minY + thickness)
        XCTAssertEqual(usable.height, visibleFrame.height - thickness)
        XCTAssertEqual(usable.width, visibleFrame.width)
    }

    func testOtherDisplayKeepsTheOriginalVisibleFrame() {
        let usable = SideDockWindowAvoidance.usableFrame(
            visibleFrame: visibleFrame,
            reserve: SideDockScreenReserve(edge: .right, displayID: 1, thickness: thickness),
            screenDisplayID: 2
        )

        XCTAssertEqual(usable, visibleFrame)
    }

    func testHiddenDockDoesNotInset() {
        let usable = SideDockWindowAvoidance.usableFrame(
            visibleFrame: visibleFrame,
            reserve: nil,
            screenDisplayID: 1
        )

        XCTAssertEqual(usable, visibleFrame)
    }

    func testClampMovesAWindowOffTheDockStrip() {
        let usable = CGRect(x: 0, y: 0, width: 1399, height: 949)
        let overlapping = CGRect(x: 1046, y: 80, width: 400, height: 700)
        let clamped = SideDockWindowAvoidance.clamp(overlapping, into: usable)

        XCTAssertEqual(clamped.maxX, usable.maxX)
        XCTAssertEqual(clamped.width, overlapping.width)
        XCTAssertEqual(clamped.height, overlapping.height)
    }

    func testReserveStoreRoundTripsAndClears() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeatWebAppDockReserve-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = SideDockReserveStore(rootDirectoryURL: tempRoot)
        XCTAssertNil(store.load())

        let reserve = SideDockScreenReserve(edge: .right, displayID: 12, thickness: 47)
        store.save(reserve)
        XCTAssertEqual(store.load(), reserve)

        store.save(nil)
        XCTAssertNil(store.load())
    }
}
