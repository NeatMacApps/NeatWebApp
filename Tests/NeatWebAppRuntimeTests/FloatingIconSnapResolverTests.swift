import XCTest
@testable import NeatWebAppRuntime

final class FloatingIconSnapResolverTests: XCTestCase {
    func testAlwaysSnapsVisualIconToTopEdge() {
        let screen = makeScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860)
        )
        let proposedFrame = CGRect(x: 48, y: 240, width: 62, height: 62)

        let snappedFrame = FloatingIconSnapResolver.resolvePanelFrame(
            proposedFrame: proposedFrame,
            anchorPoint: CGPoint(x: proposedFrame.minX, y: proposedFrame.maxY),
            availableScreens: [screen],
            fallbackScreen: nil,
            shadowPadding: 10
        )

        XCTAssertEqual(snappedFrame.insetBy(dx: 10, dy: 10).maxY, screen.visibleFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(snappedFrame.insetBy(dx: 10, dy: 10).minX, proposedFrame.insetBy(dx: 10, dy: 10).minX, accuracy: 0.001)
    }

    func testClampsHorizontalPositionWhileSnappingToTopEdge() {
        let screen = makeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940)
        )
        let proposedFrame = CGRect(x: 1490, y: 320, width: 62, height: 62)

        let snappedFrame = FloatingIconSnapResolver.resolvePanelFrame(
            proposedFrame: proposedFrame,
            anchorPoint: CGPoint(x: proposedFrame.minX, y: proposedFrame.maxY),
            availableScreens: [screen],
            fallbackScreen: nil,
            shadowPadding: 10
        )

        XCTAssertEqual(snappedFrame.insetBy(dx: 10, dy: 10).maxY, screen.visibleFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(snappedFrame.insetBy(dx: 10, dy: 10).maxX, screen.visibleFrame.maxX, accuracy: 0.001)
    }

    func testUsesMatchedDisplayVisibleFrameForTopEdgeSnap() {
        let leftScreen = makeScreen(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            localizedName: "Built-in Display"
        )
        let rightScreen = makeScreen(
            displayID: 2,
            frame: CGRect(x: 1512, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1728, height: 1075),
            localizedName: "Studio Display"
        )
        let proposedFrame = CGRect(x: 3150, y: 420, width: 62, height: 62)

        let snappedFrame = FloatingIconSnapResolver.resolvePanelFrame(
            proposedFrame: proposedFrame,
            anchorPoint: CGPoint(x: proposedFrame.minX, y: proposedFrame.maxY),
            availableScreens: [leftScreen, rightScreen],
            fallbackScreen: leftScreen,
            shadowPadding: 10
        )

        XCTAssertEqual(snappedFrame.insetBy(dx: 10, dy: 10).maxY, rightScreen.visibleFrame.maxY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(snappedFrame.insetBy(dx: 10, dy: 10).minX, rightScreen.visibleFrame.minX)
        XCTAssertLessThanOrEqual(snappedFrame.insetBy(dx: 10, dy: 10).maxX, rightScreen.visibleFrame.maxX)
    }

    private func makeScreen(
        displayID: UInt32? = nil,
        frame: CGRect,
        visibleFrame: CGRect,
        localizedName: String = "Test Display"
    ) -> WebAppWindowPlacementScreen {
        WebAppWindowPlacementScreen(
            displayID: displayID,
            localizedName: localizedName,
            frame: frame,
            visibleFrame: visibleFrame,
            notchGeometry: nil
        )
    }
}
