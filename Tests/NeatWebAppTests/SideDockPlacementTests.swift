import CoreGraphics
import Foundation
import XCTest
@testable import NeatWebApp

final class SideDockPlacementTests: XCTestCase {
    func testRecommendedDefaultEdgeAvoidsRightSystemDock() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1446, height: 949)

        XCTAssertEqual(
            SideDockPlacementResolver.recommendedDefaultEdge(
                screenFrame: screenFrame,
                visibleFrame: visibleFrame
            ),
            .left
        )
    }

    func testRightEdgeUsesVisibleFrameInsteadOfPhysicalScreenEdge() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1446, height: 949)
        let frame = SideDockPlacementResolver.panelFrame(
            edge: .right,
            verticalPosition: 0.5,
            visibleFrame: visibleFrame,
            panelSize: CGSize(width: 68, height: 240)
        )

        XCTAssertEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(frame.width, 68)
    }

    func testVerticalPositionIsClampedInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panelSize = CGSize(width: 68, height: 240)

        let bottomFrame = SideDockPlacementResolver.panelFrame(
            edge: .left,
            verticalPosition: -2,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )
        let topFrame = SideDockPlacementResolver.panelFrame(
            edge: .left,
            verticalPosition: 3,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )

        XCTAssertEqual(bottomFrame.minY, visibleFrame.minY + 16)
        XCTAssertEqual(topFrame.maxY, visibleFrame.maxY - 16)
    }

    func testNormalizedPositionRoundTripsPanelFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panelSize = CGSize(width: 68, height: 240)
        let frame = SideDockPlacementResolver.panelFrame(
            edge: .right,
            verticalPosition: 0.63,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )

        XCTAssertEqual(
            SideDockPlacementResolver.normalizedVerticalPosition(
                panelMidY: frame.midY,
                visibleFrame: visibleFrame,
                panelHeight: frame.height
            ),
            0.63,
            accuracy: 0.0001
        )
    }

    func testSingleIconVisualMarginsAreEqual() {
        let horizontalMargin = (
            SideDockPresentationContext.Layout.width
                - SideDockPresentationContext.Layout.iconSize
        ) / 2
        let bottomMargin = SideDockPresentationContext.Layout.verticalPadding
            + (
                SideDockPresentationContext.Layout.iconSlotSize
                    - SideDockPresentationContext.Layout.iconSize
            ) / 2

        XCTAssertEqual(horizontalMargin, bottomMargin)
    }

    func testInwardDistanceFollowsTheAttachedEdge() {
        let start = CGPoint(x: 100, y: 400)

        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .left,
                startLocation: start,
                currentLocation: CGPoint(x: 142, y: 400)
            ),
            42
        )
        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .left,
                startLocation: start,
                currentLocation: CGPoint(x: 58, y: 400)
            ),
            0
        )
        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .right,
                startLocation: start,
                currentLocation: CGPoint(x: 58, y: 400)
            ),
            42
        )
        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .right,
                startLocation: start,
                currentLocation: CGPoint(x: 142, y: 400)
            ),
            0
        )
    }

    func testCloseGestureRequiresAnIconAndEnoughInwardTravel() {
        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: false,
                inwardDistance: SideDockDragResolver.closeThreshold + 20,
                verticalTravel: 0
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.closeThreshold - 1,
                verticalTravel: 0
            )
        )
        XCTAssertTrue(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.closeThreshold,
                verticalTravel: 0
            )
        )
    }

    func testVerticalDragNeverClosesAnAppEvenWithSidewaysDrift() {
        let inwardDrift = SideDockDragResolver.closeThreshold + 20

        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: inwardDrift,
                verticalTravel: inwardDrift + 1
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.repositionDeadZone + 5,
                verticalTravel: 200
            )
        )
        XCTAssertEqual(
            SideDockDragResolver.closeProgress(
                inwardDistance: SideDockDragResolver.closeThreshold,
                verticalTravel: 300
            ),
            0
        )
    }

    func testSidewaysDragKeepsClosingWhileVerticalTravelStaysSmall() {
        XCTAssertTrue(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.repositionDeadZone,
                verticalTravel: 4
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: false,
                inwardDistance: SideDockDragResolver.closeThreshold,
                verticalTravel: 0
            )
        )
        XCTAssertEqual(
            SideDockDragResolver.closeProgress(
                inwardDistance: SideDockDragResolver.closeThreshold / 2,
                verticalTravel: 10
            ),
            0.5
        )
    }
}

final class AppPreferencesStoreTests: XCTestCase {
    func testMissingPreferenceUsesRecommendedDefaultEdge() {
        withStore { store in
            let preferences = store.load(defaultEdge: .left)

            XCTAssertEqual(preferences.sideDockEdge, .left)
            XCTAssertEqual(
                preferences.sideDockVerticalPosition,
                SideDockPlacementResolver.defaultVerticalPosition
            )
            XCTAssertNil(preferences.sideDockDisplayID)
            XCTAssertEqual(
                preferences.isVirtualNotchEnabled,
                AppPreferencesStore.defaultVirtualNotchEnabled
            )
        }
    }

    func testPreferencesRoundTrip() {
        withStore { store in
            let expected = AppPreferences(
                sideDockEdge: .right,
                sideDockVerticalPosition: 0.31,
                sideDockDisplayID: 7,
                isVirtualNotchEnabled: false
            )

            store.save(expected)

            XCTAssertEqual(store.load(defaultEdge: .left), expected)
        }
    }

    func testInvalidStoredEdgeFallsBackAndPositionIsClamped() {
        let suiteName = "SideDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("center", forKey: "sideDock.edge")
        defaults.set(5.0, forKey: "sideDock.verticalPosition")

        let preferences = AppPreferencesStore(defaults: defaults).load(defaultEdge: .left)

        XCTAssertEqual(preferences.sideDockEdge, .left)
        XCTAssertEqual(preferences.sideDockVerticalPosition, 1)
    }

    private func withStore(_ body: (AppPreferencesStore) -> Void) {
        let suiteName = "SideDockPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        body(AppPreferencesStore(defaults: defaults))
    }
}
