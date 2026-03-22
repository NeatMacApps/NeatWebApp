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
}
