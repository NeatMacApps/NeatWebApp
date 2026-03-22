import AppKit
import XCTest
@testable import NeatWebApp

final class ScreenNotchGeometryTests: XCTestCase {
    func testComputesNotchRectFromAuxiliaryAreas() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )

        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 620, y: 908, width: 272, height: 74))
        XCTAssertEqual(geometry.activationRect, CGRect(x: 612, y: 900, width: 288, height: 82))
    }

    func testRejectsNonNotchedDisplays() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 25, width: 1728, height: 1092),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero,
            localizedName: "Studio Display"
        )

        XCTAssertFalse(geometry.hasNotch)
    }

    func testPlacementDefaultsToBelowPreferredNotch() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )
        let screen = WebAppWindowPlacementScreen(
            displayID: 1,
            localizedName: geometry.localizedName,
            frame: geometry.screenFrame,
            visibleFrame: geometry.visibleFrame,
            notchGeometry: geometry
        )

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: StoredWebAppPreference(),
            preferredGeometry: geometry,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: CGSize(width: 460, height: 928),
            minimumFrameSize: CGSize(width: 390, height: 668)
        )

        XCTAssertEqual(frame.width, 460)
        XCTAssertEqual(frame.height, 896)
        XCTAssertEqual(frame.midX, geometry.notchRect.midX)
        XCTAssertEqual(frame.maxY, geometry.notchRect.minY - 12, accuracy: 0.001)
    }

    func testPlacementRestoresSavedFrameOnMatchingDisplayAndClampsToVisibleFrame() {
        let screen = WebAppWindowPlacementScreen(
            displayID: 9,
            localizedName: "Studio Display",
            frame: CGRect(x: 1600, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 1600, y: 25, width: 1728, height: 1092),
            notchGeometry: nil
        )
        let preference = StoredWebAppPreference(
            pageZoom: 0.8,
            isPinned: false,
            windowFrame: CGRect(x: 3100, y: 50, width: 600, height: 900),
            windowPlacement: StoredWindowPlacement(
                frame: CGRect(x: 3100, y: 50, width: 600, height: 900),
                display: StoredDisplayIdentity(
                    displayID: 9,
                    localizedName: "Studio Display",
                    frame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
                )
            )
        )

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: nil,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: CGSize(width: 460, height: 928),
            minimumFrameSize: CGSize(width: 390, height: 668)
        )

        XCTAssertEqual(frame.width, 600)
        XCTAssertEqual(frame.height, 900)
        XCTAssertEqual(frame.maxX, screen.visibleFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 50)
    }

    func testPlacementKeepsWindowSizeButFallsBackToPreferredNotchWhenSavedDisplayIsMissing() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )
        let screen = WebAppWindowPlacementScreen(
            displayID: 1,
            localizedName: geometry.localizedName,
            frame: geometry.screenFrame,
            visibleFrame: geometry.visibleFrame,
            notchGeometry: geometry
        )
        let preference = StoredWebAppPreference(
            pageZoom: 0.8,
            isPinned: false,
            windowFrame: CGRect(x: 1800, y: 140, width: 720, height: 760),
            windowPlacement: StoredWindowPlacement(
                frame: CGRect(x: 1800, y: 140, width: 720, height: 760),
                display: StoredDisplayIdentity(
                    displayID: 99,
                    localizedName: "Missing Display",
                    frame: CGRect(x: 1512, y: 0, width: 1728, height: 1117)
                )
            )
        )

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: geometry,
            availableScreens: [screen],
            fallbackDisplayID: screen.displayID,
            defaultFrameSize: CGSize(width: 460, height: 928),
            minimumFrameSize: CGSize(width: 390, height: 668)
        )

        XCTAssertEqual(frame.width, 720)
        XCTAssertEqual(frame.height, 760)
        XCTAssertEqual(frame.midX, geometry.notchRect.midX)
        XCTAssertEqual(frame.maxY, geometry.notchRect.minY - 12, accuracy: 0.001)
    }
}
