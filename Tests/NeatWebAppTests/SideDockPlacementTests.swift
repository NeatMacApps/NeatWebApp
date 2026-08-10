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

        // 拖到底就该贴住可用区域的下边缘，不再留死边距；顶部同理。
        XCTAssertEqual(bottomFrame.minY, visibleFrame.minY)
        XCTAssertEqual(topFrame.maxY, visibleFrame.maxY)
    }

    func testBottomEdgeStopsAboveTheSystemDock() {
        // visibleFrame 已经排除了底部系统程序坞，贴边贴的是它的上沿。
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 74, width: 1512, height: 883)

        let frame = SideDockPlacementResolver.panelFrame(
            edge: .right,
            verticalPosition: 0,
            visibleFrame: visibleFrame,
            panelSize: CGSize(width: 47, height: 240)
        )

        XCTAssertEqual(frame.minY, visibleFrame.minY)
        XCTAssertGreaterThan(frame.minY, screenFrame.minY)
    }

    func testEdgePositionsRoundTripThroughNormalizedValue() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panelHeight: CGFloat = 240

        for position in [CGFloat(0), 0.5, 1] {
            let frame = SideDockPlacementResolver.panelFrame(
                edge: .left,
                verticalPosition: position,
                visibleFrame: visibleFrame,
                panelSize: CGSize(width: 68, height: panelHeight)
            )

            XCTAssertEqual(
                SideDockPlacementResolver.normalizedVerticalPosition(
                    panelMidY: frame.midY,
                    visibleFrame: visibleFrame,
                    panelHeight: panelHeight
                ),
                position,
                accuracy: 0.0001
            )
        }
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
            SideDockPresentationContext.Layout.thickness
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
        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .bottom,
                startLocation: start,
                currentLocation: CGPoint(x: 100, y: 442)
            ),
            42
        )
        XCTAssertEqual(
            SideDockDragResolver.inwardDistance(
                edge: .bottom,
                startLocation: start,
                currentLocation: CGPoint(x: 100, y: 358)
            ),
            0
        )
    }

    func testAlongEdgeTravelUsesHorizontalAxisOnBottomEdge() {
        let start = CGPoint(x: 300, y: 80)

        XCTAssertEqual(
            SideDockDragResolver.alongEdgeTravel(
                edge: .bottom,
                startLocation: start,
                currentLocation: CGPoint(x: 420, y: 140)
            ),
            120
        )
        XCTAssertEqual(
            SideDockDragResolver.alongEdgeTravel(
                edge: .left,
                startLocation: start,
                currentLocation: CGPoint(x: 420, y: 140)
            ),
            60
        )
    }

    func testCloseGestureRequiresAnIconAndEnoughInwardTravel() {
        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: false,
                inwardDistance: SideDockDragResolver.closeThreshold + 20,
                alongEdgeTravel: 0
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.closeThreshold - 1,
                alongEdgeTravel: 0
            )
        )
        XCTAssertTrue(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.closeThreshold,
                alongEdgeTravel: 0
            )
        )
    }

    func testVerticalDragNeverClosesAnAppEvenWithSidewaysDrift() {
        let inwardDrift = SideDockDragResolver.closeThreshold + 20

        XCTAssertFalse(
            SideDockDragResolver.shouldClose(
                startedOnApp: true,
                inwardDistance: inwardDrift,
                alongEdgeTravel: inwardDrift + 1
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.repositionDeadZone + 5,
                alongEdgeTravel: 200
            )
        )
        XCTAssertEqual(
            SideDockDragResolver.closeProgress(
                inwardDistance: SideDockDragResolver.closeThreshold,
                alongEdgeTravel: 300
            ),
            0
        )
    }

    func testSidewaysDragKeepsClosingWhileVerticalTravelStaysSmall() {
        XCTAssertTrue(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: true,
                inwardDistance: SideDockDragResolver.repositionDeadZone,
                alongEdgeTravel: 4
            )
        )
        XCTAssertFalse(
            SideDockDragResolver.isClosingGesture(
                startedOnApp: false,
                inwardDistance: SideDockDragResolver.closeThreshold,
                alongEdgeTravel: 0
            )
        )
        XCTAssertEqual(
            SideDockDragResolver.closeProgress(
                inwardDistance: SideDockDragResolver.closeThreshold / 2,
                alongEdgeTravel: 10
            ),
            0.5
        )
    }

    func testBottomEdgeSticksToVisibleFrameBottom() {
        let visibleFrame = CGRect(x: 0, y: 74, width: 1512, height: 883)
        let frame = SideDockPlacementResolver.panelFrame(
            edge: .bottom,
            verticalPosition: 0.5,
            visibleFrame: visibleFrame,
            panelSize: CGSize(width: 240, height: 47)
        )

        XCTAssertEqual(frame.minY, visibleFrame.minY)
        XCTAssertEqual(frame.height, 47)
        XCTAssertGreaterThan(frame.minY, 0)
    }

    func testBottomEdgePositionIsClampedHorizontally() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panelSize = CGSize(width: 240, height: 47)

        let leftFrame = SideDockPlacementResolver.panelFrame(
            edge: .bottom,
            verticalPosition: -1,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )
        let rightFrame = SideDockPlacementResolver.panelFrame(
            edge: .bottom,
            verticalPosition: 2,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )

        XCTAssertEqual(leftFrame.minX, visibleFrame.minX)
        XCTAssertEqual(rightFrame.maxX, visibleFrame.maxX)
    }

    func testBottomPanelSizeIsTransposed() {
        let context = SideDockPresentationContext(
            apps: Array(WebAppDefinition.examples.prefix(3)),
            edge: .bottom,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 74, width: 1512, height: 883),
            verticalPosition: 0.5
        )

        let size = context.layout.panelSize
        XCTAssertEqual(size.height, SideDockPresentationContext.Layout.thickness)
        XCTAssertGreaterThan(size.width, size.height)
        XCTAssertEqual(
            size.width,
            CGFloat(3) * SideDockPresentationContext.Layout.iconSlotSize
                + CGFloat(2) * SideDockPresentationContext.Layout.iconSpacing
                + CGFloat(2) * SideDockPresentationContext.Layout.verticalPadding
                + CGFloat(2) * SideDockPresentationContext.Layout.edgeTransitionDepth
        )
    }

    func testBottomNormalizedPositionRoundTrips() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let panelWidth: CGFloat = 240

        for position in [CGFloat(0), 0.5, 1] {
            let frame = SideDockPlacementResolver.panelFrame(
                edge: .bottom,
                verticalPosition: position,
                visibleFrame: visibleFrame,
                panelSize: CGSize(width: panelWidth, height: 47)
            )

            XCTAssertEqual(
                SideDockPlacementResolver.normalizedPosition(
                    edge: .bottom,
                    panelMidX: frame.midX,
                    visibleFrame: visibleFrame,
                    panelWidth: panelWidth
                ),
                position,
                accuracy: 0.0001
            )
        }
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
