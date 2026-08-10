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
}
