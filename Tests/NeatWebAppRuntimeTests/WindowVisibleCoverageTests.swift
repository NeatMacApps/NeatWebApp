import CoreGraphics
import XCTest
@testable import NeatWebAppRuntime

final class WindowVisibleCoverageTests: XCTestCase {
    func testMissingFromScreenListStaysOpenWhenSystemStillReportsVisible() {
        XCTAssertEqual(
            WindowVisibleCoverage.hiddenFractionWhenMissingFromScreenList(systemReportsVisible: true),
            0
        )
    }

    func testMissingFromScreenListCountsAsHiddenWhenSystemAlsoReportsInvisible() {
        XCTAssertEqual(
            WindowVisibleCoverage.hiddenFractionWhenMissingFromScreenList(systemReportsVisible: false),
            1
        )
    }

    func testMissingWindowCountsAsFullyHidden() {
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 99,
            windowsFrontToBack: [record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 1)
    }

    func testUncoveredWindowIsFullyVisible() {
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 1,
            windowsFrontToBack: [record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0)
    }

    func testEightyPercentCoveredReachesCollapseThreshold() {
        let front = record(id: 1, frame: CGRect(x: 0, y: 0, width: 80, height: 100))
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 2,
            windowsFrontToBack: [front, target],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0.8, accuracy: 0.001)
        XCTAssertTrue(WindowVisibleCoverage.shouldCollapse(hiddenFraction: hidden))
    }

    func testSeventyNinePercentCoveredStaysOpen() {
        let front = record(id: 1, frame: CGRect(x: 0, y: 0, width: 79, height: 100))
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 2,
            windowsFrontToBack: [front, target],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0.79, accuracy: 0.001)
        XCTAssertFalse(WindowVisibleCoverage.shouldCollapse(hiddenFraction: hidden))
    }

    func testOverlappingOccludersAreNotDoubleCounted() {
        let front1 = record(id: 1, frame: CGRect(x: 0, y: 0, width: 60, height: 100))
        let front2 = record(id: 2, frame: CGRect(x: 40, y: 0, width: 60, height: 100))
        let target = record(id: 3, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 3,
            windowsFrontToBack: [front1, front2, target],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 1, accuracy: 0.001)
    }

    func testWindowsBehindTheTargetDoNotCount() {
        let target = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let behind = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 1,
            windowsFrontToBack: [target, behind],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0)
    }

    func testTransparentWindowsDoNotOcclude() {
        let front = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), alpha: 0.2)
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 2,
            windowsFrontToBack: [front, target],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0)
    }

    func testHigherLayerOverlaysDoNotOcclude() {
        let overlay = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 25)
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 2,
            windowsFrontToBack: [overlay, target],
            screenBounds: []
        )
        XCTAssertEqual(hidden, 0)
        XCTAssertFalse(WindowVisibleCoverage.shouldCollapse(hiddenFraction: hidden))
    }

    func testEightyPercentOffScreenReachesCollapseThreshold() {
        let target = record(id: 1, frame: CGRect(x: 80, y: 0, width: 100, height: 100))
        let hidden = WindowVisibleCoverage.hiddenFraction(
            of: 1,
            windowsFrontToBack: [target],
            screenBounds: [CGRect(x: 0, y: 0, width: 100, height: 100)]
        )
        XCTAssertEqual(hidden, 0.8, accuracy: 0.001)
        XCTAssertTrue(WindowVisibleCoverage.shouldCollapse(hiddenFraction: hidden))
    }

    func testAppKitFrameConvertsToTopLeftOrigin() {
        let converted = WindowVisibleCoverage.cgBounds(
            fromAppKitFrame: CGRect(x: 0, y: 0, width: 100, height: 80),
            primaryDisplayHeight: 1000
        )
        XCTAssertEqual(converted, CGRect(x: 0, y: 920, width: 100, height: 80))
    }

    private func record(
        id: CGWindowID,
        frame: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1
    ) -> WindowVisibleCoverage.Record {
        WindowVisibleCoverage.Record(windowID: id, frame: frame, layer: layer, alpha: alpha)
    }
}
