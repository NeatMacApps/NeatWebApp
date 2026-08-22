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
