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

    func testUsesFixedSpacingWhenTwoAppsFit() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: Array(WebAppDefinition.examples.prefix(2)))
        let layout = context.layout
        let expectedSpacing = max(min(geometry.notchRect.height * 0.16, 14), 8)

        XCTAssertEqual(layout.iconSpacing, expectedSpacing, accuracy: 0.001)
        XCTAssertEqual(layout.iconHorizontalPadding, expectedSpacing, accuracy: 0.001)
        XCTAssertFalse(layout.shouldScroll)
    }

    func testUsesFixedSpacingWhenFourAppsFit() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: Array(WebAppDefinition.examples.prefix(4)))
        let layout = context.layout
        let expectedSpacing = max(min(geometry.notchRect.height * 0.16, 14), 8)

        XCTAssertEqual(layout.iconSpacing, expectedSpacing, accuracy: 0.001)
        XCTAssertEqual(layout.iconHorizontalPadding, expectedSpacing, accuracy: 0.001)
        XCTAssertFalse(layout.shouldScroll)
    }

    func testUsesFixedSpacingWhenAppsOverflowVisibleCapacity() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)
        let layout = context.layout
        let expectedSpacing = max(min(geometry.notchRect.height * 0.16, 14), 8)

        XCTAssertTrue(layout.shouldScroll)
        XCTAssertEqual(layout.iconSpacing, expectedSpacing, accuracy: 0.001)
        XCTAssertEqual(layout.iconHorizontalPadding, expectedSpacing, accuracy: 0.001)
    }

    func testLayoutCalculatesVisibleAppCountForSizing() {
        let geometry = makeGeometry()
        let context = LauncherPresentationContext(geometry: geometry, apps: WebAppDefinition.examples)

        // visibleAppCount is used for layout sizing (icon size / spacing), not for truncation
        XCTAssertEqual(context.layout.visibleAppCount, 5)
        // All apps are available for rendering (scrolling handles overflow)
        XCTAssertEqual(context.apps.count, WebAppDefinition.examples.count)
    }

    func testEdgeFadeStateShowsOnlyTrailingFadeAtInitialPosition() {
        let state = LauncherEdgeFadeState(
            visibleRect: CGRect(x: 0, y: 0, width: 200, height: 40),
            contentWidth: 240,
            horizontalPadding: 8
        )

        XCTAssertFalse(state.showsLeadingFade)
        XCTAssertTrue(state.showsTrailingFade)
    }

    func testEdgeFadeStateShowsOnlyLeadingFadeAtTrailingEdge() {
        let state = LauncherEdgeFadeState(
            visibleRect: CGRect(x: 48, y: 0, width: 200, height: 40),
            contentWidth: 256,
            horizontalPadding: 8
        )

        XCTAssertTrue(state.showsLeadingFade)
        XCTAssertFalse(state.showsTrailingFade)
    }

    func testEdgeFadeStateDisablesBothFadesWhenContentFitsViewport() {
        let state = LauncherEdgeFadeState(
            visibleRect: CGRect(x: 0, y: 0, width: 200, height: 40),
            contentWidth: 120,
            horizontalPadding: 8
        )

        XCTAssertFalse(state.showsLeadingFade)
        XCTAssertFalse(state.showsTrailingFade)
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
