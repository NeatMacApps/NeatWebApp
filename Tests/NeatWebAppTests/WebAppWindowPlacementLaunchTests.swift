import XCTest
@testable import NeatWebApp

@MainActor
final class WebAppWindowPlacementLaunchTests: XCTestCase {
    func testSavedCompactFrameIsNotInflatedToVisibleDesktop() {
        let screen = makeBuiltInScreen()
        let saved = CGRect(x: 971, y: 23, width: 354, height: 589)
        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: makePreference(frame: saved, displayID: screen.displayID),
            preferredGeometry: nil,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: screen.visibleFrame.size
        )

        XCTAssertEqual(frame.width, saved.width, accuracy: 0.5)
        XCTAssertEqual(frame.height, saved.height, accuracy: 0.5)
        XCTAssertFalse(
            WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: screen.visibleFrame)
        )
    }

    func testFillDesktopSavedFrameFallsBackToDefaultWindowSize() {
        let screen = makeBuiltInScreen()
        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: makePreference(frame: screen.visibleFrame, displayID: screen.displayID),
            preferredGeometry: nil,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        XCTAssertEqual(frame.size, WebAppWindowMetrics.defaultFrameSize)
        XCTAssertFalse(
            WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: screen.visibleFrame)
        )
    }

    func testDefaultMetricsAreNotTheVisibleDesktop() {
        let visible = makeBuiltInScreen().visibleFrame.size

        XCTAssertLessThan(WebAppWindowMetrics.defaultFrameSize.width, visible.width)
        XCTAssertLessThan(WebAppWindowMetrics.defaultFrameSize.height, visible.height)
        XCTAssertEqual(WebAppWindowMetrics.defaultFrameSize, WebAppWindowMetrics.defaultContentSize)
        XCTAssertFalse(
            WebAppWindowPlacementResolver.isFillVisibleSize(
                WebAppWindowMetrics.defaultFrameSize,
                visibleSize: visible
            )
        )
    }

    func testLaunchIsolationDisablesSystemFrameRestore() {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WebAppWindowMetrics.defaultContentSize),
            styleMask: WebAppWindowMetrics.styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        WebAppWindowMetrics.applyLaunchIsolation(to: window)

        XCTAssertFalse(window.isRestorable)
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertEqual(window.animationBehavior, .none)

        window.close()
    }

    private func makeBuiltInScreen() -> WebAppWindowPlacementScreen {
        WebAppWindowPlacementScreen(
            displayID: 1,
            localizedName: "Built-in Retina Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1446, height: 949),
            notchGeometry: nil
        )
    }

    private func makePreference(frame: CGRect, displayID: UInt32?) -> StoredWebAppPreference {
        StoredWebAppPreference(
            windowFrame: frame,
            windowPlacement: StoredWindowPlacement(
                frame: frame,
                display: StoredDisplayIdentity(
                    displayID: displayID,
                    localizedName: "Built-in Retina Display",
                    frame: CGRect(x: 0, y: 0, width: 1512, height: 982)
                )
            )
        )
    }
}
