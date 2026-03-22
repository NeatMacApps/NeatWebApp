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
        XCTAssertGreaterThan(context.layout.iconBottomPadding, 0)
        XCTAssertEqual(context.layout.iconRowHeight, context.layout.iconSize + context.layout.iconBottomPadding, accuracy: 0.001)
        XCTAssertEqual(context.layout.panelBottomPadding, 0)
        XCTAssertEqual(context.panelSize.height, context.layout.barSize.height + context.layout.panelBottomPadding)
    }

    func testUsesEqualOuterAndInnerSpacingForVisibleApps() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)
        let layout = context.layout
        let expectedSpacing = (geometry.notchRect.width - (CGFloat(layout.visibleAppCount) * layout.iconSize)) / CGFloat(layout.visibleAppCount + 1)

        XCTAssertEqual(layout.iconSpacing, expectedSpacing, accuracy: 0.001)
    }

    func testLayoutCalculatesVisibleAppCountForSizing() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)

        // visibleAppCount is used for layout sizing (icon size / spacing), not for truncation
        XCTAssertEqual(context.layout.visibleAppCount, 5)
        // All apps are available for rendering (scrolling handles overflow)
        XCTAssertEqual(context.apps.count, WebAppDefinition.examples.count)
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
