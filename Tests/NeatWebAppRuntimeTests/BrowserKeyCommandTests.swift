import AppKit
import XCTest
@testable import NeatWebAppRuntime

final class BrowserKeyCommandTests: XCTestCase {
    func testZoomShortcuts() {
        XCTAssertEqual(resolve("=", [.command]), .zoomIn)
        XCTAssertEqual(resolve("+", [.command, .shift]), .zoomIn)
        XCTAssertEqual(resolve("-", [.command]), .zoomOut)
        XCTAssertEqual(resolve("_", [.command, .shift]), .zoomOut)
        XCTAssertEqual(resolve("0", [.command]), .resetZoom)
    }

    func testNumericKeypadZoomKeysAreRecognized() {
        XCTAssertEqual(resolve("+", [.command, .numericPad]), .zoomIn)
        XCTAssertEqual(resolve("-", [.command, .numericPad]), .zoomOut)
    }

    func testReloadShortcuts() {
        XCTAssertEqual(resolve("r", [.command]), .reload)
        XCTAssertEqual(resolve("r", [.command, .shift]), .reloadIgnoringCache)
    }

    func testCapsLockDoesNotTurnReloadIntoHardReload() {
        XCTAssertEqual(resolve("R", [.command]), .reload)
    }

    func testHistoryShortcuts() {
        XCTAssertEqual(resolve("[", [.command]), .goBack)
        XCTAssertEqual(resolve("]", [.command]), .goForward)
    }

    func testCommandArrowKeysStayWithTheWebPage() {
        // 网页输入框里 Command ←/→ 是跳到行首/行尾，不能被前进后退抢走。
        XCTAssertNil(resolve(functionKey(NSLeftArrowFunctionKey), [.command]))
        XCTAssertNil(resolve(functionKey(NSRightArrowFunctionKey), [.command]))
    }

    func testHomeRequiresShiftSoCommandHStaysSystemHide() {
        XCTAssertEqual(resolve("h", [.command, .shift]), .goHome)
        XCTAssertNil(resolve("h", [.command]))
    }

    func testPrintAndCollapseShortcuts() {
        XCTAssertEqual(resolve("p", [.command]), .printPage)
        XCTAssertEqual(resolve("w", [.command]), .collapseWindow)
    }

    func testIgnoresEventsWithoutCommandOrWithExtraModifiers() {
        XCTAssertNil(resolve("=", []))
        XCTAssertNil(resolve("r", []))
        XCTAssertNil(resolve("-", [.control]))
        XCTAssertNil(resolve("0", [.command, .option]))
        XCTAssertNil(resolve("r", [.command, .control]))
    }

    func testIgnoresUnrelatedKeys() {
        XCTAssertNil(resolve("k", [.command]))
        XCTAssertNil(resolve("t", [.command]))
        XCTAssertNil(resolve(nil, [.command]))
    }

    private func functionKey(_ rawValue: Int) -> String {
        guard let scalar = UnicodeScalar(UInt32(rawValue)) else {
            return ""
        }

        return String(scalar)
    }

    private func resolve(
        _ charactersIgnoringModifiers: String?,
        _ modifierFlags: NSEvent.ModifierFlags
    ) -> BrowserKeyCommand? {
        BrowserKeyCommand.resolve(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        )
    }
}
