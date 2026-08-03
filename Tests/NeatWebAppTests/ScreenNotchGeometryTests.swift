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
        XCTAssertEqual(geometry.activationRect, geometry.notchRect)

        let retentionRect = geometry.launcherRetentionRect
        XCTAssertEqual(retentionRect.midX, geometry.notchRect.midX, accuracy: 0.001)
        XCTAssertLessThan(retentionRect.width, geometry.activationRect.width * 1.5)
        XCTAssertGreaterThan(retentionRect.height, geometry.activationRect.height * 2)
        XCTAssertLessThan(retentionRect.height, geometry.activationRect.height * 3)
        XCTAssertLessThan(retentionRect.minY, geometry.activationRect.minY - 100)
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

    func testVirtualNotchIsCenteredUnderMenuBarOnNonNotchedDisplay() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 25, width: 1728, height: 1067)

        guard let geometry = ScreenNotchGeometry.virtual(
            displayID: 9,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            localizedName: "Studio Display"
        ) else {
            return XCTFail("A non-notched display should still produce a virtual notch geometry.")
        }

        XCTAssertTrue(geometry.isVirtual)
        XCTAssertTrue(geometry.hasNotch)
        XCTAssertEqual(geometry.notchRect.height, 25, accuracy: 0.001)
        XCTAssertEqual(geometry.notchRect.maxY, screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(geometry.notchRect.midX, screenFrame.midX, accuracy: 1)
        XCTAssertEqual(geometry.notchRect.width, 1728 * 0.18, accuracy: 1)
        XCTAssertTrue(geometry.containsActivationPoint(CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 1)))
        XCTAssertFalse(geometry.containsActivationPoint(CGPoint(x: screenFrame.minX + 10, y: screenFrame.maxY - 1)))
        XCTAssertFalse(geometry.containsActivationPoint(CGPoint(x: screenFrame.midX, y: visibleFrame.maxY - 1)))
    }

    func testVirtualNotchClampsWidthAndHeightOnExtremeDisplays() {
        guard let wideGeometry = ScreenNotchGeometry.virtual(
            displayID: 2,
            screenFrame: CGRect(x: 0, y: 0, width: 5120, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 5120, height: 2160),
            localizedName: "Ultra Wide"
        ) else {
            return XCTFail("A wide display should still produce a virtual notch geometry.")
        }

        // 菜单栏自动隐藏时高度差为 0，热区仍要保留可命中的最小高度。
        XCTAssertEqual(wideGeometry.notchRect.height, 26, accuracy: 0.001)
        XCTAssertEqual(wideGeometry.notchRect.width, 320, accuracy: 0.001)

        guard let narrowGeometry = ScreenNotchGeometry.virtual(
            displayID: 3,
            screenFrame: CGRect(x: 0, y: 0, width: 240, height: 400),
            visibleFrame: CGRect(x: 0, y: 0, width: 240, height: 320),
            localizedName: "Tiny Display"
        ) else {
            return XCTFail("A narrow display should still produce a virtual notch geometry.")
        }

        XCTAssertEqual(narrowGeometry.notchRect.width, 144, accuracy: 0.001)
        XCTAssertTrue(narrowGeometry.hasNotch)
    }

    func testVirtualNotchLayoutStaysUsableForLauncherIcons() {
        guard let geometry = ScreenNotchGeometry.virtual(
            displayID: 9,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 25, width: 1728, height: 1067),
            localizedName: "Studio Display"
        ) else {
            return XCTFail("A non-notched display should still produce a virtual notch geometry.")
        }

        let layout = LauncherPresentationContext(
            geometry: geometry,
            apps: WebAppDefinition.examples
        ).layout

        XCTAssertEqual(layout.barSize.width, geometry.notchRect.width, accuracy: 0.001)
        XCTAssertGreaterThan(layout.barSize.height, geometry.notchRect.height)
        XCTAssertGreaterThanOrEqual(layout.iconSize, 24)
        XCTAssertGreaterThanOrEqual(layout.visibleAppCount, 1)
    }

    func testActivationMatchesNotchBoundsExactly() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )

        XCTAssertTrue(geometry.containsActivationPoint(CGPoint(x: geometry.notchRect.midX, y: geometry.screenFrame.maxY)))
        XCTAssertFalse(geometry.containsActivationPoint(CGPoint(x: geometry.notchRect.midX, y: geometry.screenFrame.maxY + 1)))
        XCTAssertFalse(geometry.containsActivationPoint(CGPoint(x: geometry.notchRect.minX - 1, y: geometry.notchRect.midY)))
    }

    func testStickyActivationAlsoMatchesNotchBoundsExactly() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )

        XCTAssertTrue(geometry.containsStickyActivationPoint(CGPoint(x: geometry.notchRect.midX, y: geometry.notchRect.midY)))
        XCTAssertFalse(geometry.containsStickyActivationPoint(CGPoint(x: geometry.notchRect.midX, y: geometry.screenFrame.maxY + 1)))
    }

    func testLauncherRetentionKeepsPointerBelowLauncherInside() {
        let geometry = ScreenNotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 940),
            safeAreaInsets: NSEdgeInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 620, height: 74),
            auxiliaryTopRightArea: CGRect(x: 892, y: 908, width: 620, height: 74),
            localizedName: "Built-in Display"
        )

        XCTAssertTrue(geometry.containsLauncherRetentionPoint(CGPoint(x: geometry.notchRect.midX, y: 820)))
        XCTAssertTrue(geometry.containsLauncherRetentionPoint(CGPoint(x: 570, y: geometry.activationRect.midY)))
        XCTAssertFalse(geometry.containsLauncherRetentionPoint(CGPoint(x: geometry.notchRect.midX, y: 780)))
        XCTAssertFalse(geometry.containsLauncherRetentionPoint(CGPoint(x: 555, y: geometry.activationRect.midY)))
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
        XCTAssertEqual(frame.height, 828)
        XCTAssertEqual(frame.midX, geometry.notchRect.midX)
        XCTAssertEqual(frame.maxY, geometry.notchRect.minY - 80, accuracy: 0.001)
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
        XCTAssertEqual(frame.maxY, geometry.notchRect.minY - 80, accuracy: 0.001)
    }
}
