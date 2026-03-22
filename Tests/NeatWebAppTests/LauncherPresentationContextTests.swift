import AppKit
import XCTest
@testable import NeatWebApp

final class LauncherPresentationContextTests: XCTestCase {
    func testMatchesBarWidthToNotchRect() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)

        XCTAssertEqual(context.layout.barSize.width, geometry.notchRect.width)
        XCTAssertEqual(context.panelSize.width, geometry.notchRect.width)
        XCTAssertEqual(context.panelFrame.minX, geometry.notchRect.minX)
    }

    func testLeavesNotchAreaEmptyAndAlignsPanelToScreenTop() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)

        XCTAssertEqual(context.layout.topInsetHeight, geometry.notchRect.height)
        XCTAssertEqual(context.panelFrame.maxY, geometry.screenFrame.maxY)
        XCTAssertEqual(context.layout.iconSize, (geometry.notchRect.width / 6) - 8, accuracy: 0.001)
        XCTAssertEqual(context.panelSize.height, context.layout.barSize.height + context.layout.panelBottomPadding)
    }

    private func makeGeometry() -> ScreenNotchGeometry {
        ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )
    }
}
