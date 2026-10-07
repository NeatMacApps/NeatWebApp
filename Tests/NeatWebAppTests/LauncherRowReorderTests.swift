import CoreGraphics
import XCTest
@testable import NeatWebApp

final class LauncherRowReorderTests: XCTestCase {
    func testStaysInPlaceWithoutHorizontalMovement() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 2,
                translationX: 0,
                slotWidth: 40,
                itemCount: 5
            ),
            2
        )
    }

    func testMovesRightByWholeSlots() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 1,
                translationX: 120,
                slotWidth: 40,
                itemCount: 5
            ),
            4
        )
    }

    func testRoundsPartialMovementToNearestSlot() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 1,
                translationX: 65,
                slotWidth: 40,
                itemCount: 5
            ),
            3
        )
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 1,
                translationX: 55,
                slotWidth: 40,
                itemCount: 5
            ),
            2
        )
    }

    func testClampsToLeadingEdge() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 0,
                translationX: -80,
                slotWidth: 40,
                itemCount: 4
            ),
            0
        )
    }

    func testClampsToTrailingEdge() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 3,
                translationX: 200,
                slotWidth: 40,
                itemCount: 4
            ),
            3
        )
    }

    func testSingleItemNeverMoves() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 0,
                translationX: 80,
                slotWidth: 40,
                itemCount: 1
            ),
            0
        )
    }

    func testInvalidSlotWidthKeepsStartIndex() {
        XCTAssertEqual(
            LauncherRowReorder.targetIndex(
                startIndex: 2,
                translationX: 80,
                slotWidth: 0,
                itemCount: 5
            ),
            2
        )
    }

    func testOffsetTracksCursorAroundSlotShifts() {
        // 向右换了一个槽位后，视觉偏移应等于位移减去一个槽宽，图标贴住光标。
        XCTAssertEqual(
            LauncherRowReorder.offset(
                translationX: 90,
                targetIndex: 3,
                startIndex: 2,
                slotWidth: 40
            ),
            50,
            accuracy: 0.001
        )
        // 向左换位时，视觉偏移等于位移加上一个槽宽。
        XCTAssertEqual(
            LauncherRowReorder.offset(
                translationX: -50,
                targetIndex: 1,
                startIndex: 2,
                slotWidth: 40
            ),
            -10,
            accuracy: 0.001
        )
    }

    func testOffsetWithoutSlotShiftIsRawTranslation() {
        XCTAssertEqual(
            LauncherRowReorder.offset(
                translationX: 30,
                targetIndex: 2,
                startIndex: 2,
                slotWidth: 40
            ),
            30,
            accuracy: 0.001
        )
    }

    func testDisplacementShiftsOnlyItemsBetweenStartAndTarget() {
        // 从 1 拖到 3：2、3 向左让一格，0 与 4 不动。
        let rightward = (0..<5).map {
            LauncherRowReorder.displacement(index: $0, startIndex: 1, targetIndex: 3, slotWidth: 40)
        }
        XCTAssertEqual(rightward, [0, 0, -40, -40, 0])

        // 从 3 拖到 1：1、2 向右让一格。
        let leftward = (0..<5).map {
            LauncherRowReorder.displacement(index: $0, startIndex: 3, targetIndex: 1, slotWidth: 40)
        }
        XCTAssertEqual(leftward, [0, 40, 40, 0, 0])

        // 还没越过半格时谁都不动。
        let unchanged = (0..<5).map {
            LauncherRowReorder.displacement(index: $0, startIndex: 2, targetIndex: 2, slotWidth: 40)
        }
        XCTAssertEqual(unchanged, [0, 0, 0, 0, 0])
    }

    func testAutoScrollOnlyInsideEdgeZones() {
        func velocity(_ x: CGFloat) -> CGFloat {
            LauncherDragAutoScroll.velocity(
                pointerX: x,
                viewportMinX: 100,
                viewportMaxX: 300,
                edgeWidth: 40,
                maxSpeed: 200
            )
        }

        XCTAssertEqual(velocity(200), 0)
        XCTAssertEqual(velocity(140), 0)
        XCTAssertEqual(velocity(120), -100, accuracy: 0.001)
        XCTAssertEqual(velocity(280), 100, accuracy: 0.001)
        // 拖出图标行之外按最快速度滚。
        XCTAssertEqual(velocity(20), -200, accuracy: 0.001)
        XCTAssertEqual(velocity(500), 200, accuracy: 0.001)
    }

    func testIconHitShapeIsVisibleCircleOnly() {
        let frame = CGRect(x: 10, y: 20, width: 24, height: 24)
        XCTAssertTrue(LauncherIconHitShape.circle(in: frame, contains: CGPoint(x: 22, y: 32)))
        XCTAssertTrue(LauncherIconHitShape.circle(in: frame, contains: CGPoint(x: 33, y: 32)))
        // 方框的四角在圆外，属于抽屉黑底。
        XCTAssertFalse(LauncherIconHitShape.circle(in: frame, contains: CGPoint(x: 11, y: 21)))
        XCTAssertFalse(LauncherIconHitShape.circle(in: frame, contains: CGPoint(x: 33, y: 43)))
    }
}
