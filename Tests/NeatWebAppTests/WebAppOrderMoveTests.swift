import XCTest
@testable import NeatWebApp

final class WebAppOrderMoveTests: XCTestCase {
    private struct Item: Identifiable, Equatable {
        let id: String
    }

    private let items = ["a", "b", "c", "d"].map(Item.init)

    private func ids(_ items: [Item]) -> [String] {
        items.map(\.id)
    }

    func testMovesDownBeforeTarget() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["a"], before: "d")), ["b", "c", "a", "d"])
    }

    func testMovesUpBeforeTarget() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["d"], before: "a")), ["d", "a", "b", "c"])
    }

    func testMovesToEndWithoutTarget() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["b"], before: nil)), ["a", "c", "d", "b"])
    }

    func testDroppingBeforeItselfKeepsOrder() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["b"], before: "b")), ["a", "b", "c", "d"])
        XCTAssertEqual(ids(items.movingItems(withIDs: ["d"], before: "d")), ["a", "b", "c", "d"])
        XCTAssertEqual(ids(items.movingItems(withIDs: ["b"], before: "c")), ["a", "b", "c", "d"])
    }

    func testMultipleSourcesKeepRelativeOrder() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["d", "a"], before: "c")), ["b", "a", "d", "c"])
    }

    func testUnknownIDsAreIgnored() {
        XCTAssertEqual(ids(items.movingItems(withIDs: ["x"], before: "b")), ["a", "b", "c", "d"])
        XCTAssertEqual(ids(items.movingItems(withIDs: ["a"], before: "x")), ["b", "c", "d", "a"])
    }
}
