import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class WebAppWindowAutoCollapseTests: XCTestCase {
    /// 被别的窗口盖住八成、切到别的桌面、别的应用进入全屏，都视为足够看不见。
    func testCollapsesWheneverTheWindowIsMostlyHidden() {
        XCTAssertTrue(makeDecision())
    }

    func testCollapsesWhenExactlyEightyPercentHidden() {
        XCTAssertTrue(makeDecision(hiddenFraction: 0.8))
    }

    func testKeepsWindowWhenSeventyNinePercentHidden() {
        XCTAssertFalse(makeDecision(hiddenFraction: 0.79))
    }

    func testKeepsWindowWhenStillMostlyVisible() {
        XCTAssertFalse(makeDecision(hiddenFraction: 0.5))
    }

    /// 最小化到程序坞是用户主动放进坞里的，不该再变成悬浮圆点。
    func testKeepsWindowWhenMiniaturized() {
        XCTAssertFalse(makeDecision(isMiniaturized: true))
    }

    /// 窗口本就没显示出来（已经收起或已隐藏），不能再收起一次。
    func testKeepsWindowWhenItIsNotOnScreenAtAll() {
        XCTAssertFalse(makeDecision(isWindowVisible: false))
    }

    func testNeverCollapsesTheWindowTheUserIsWorkingIn() {
        XCTAssertFalse(makeDecision(isKeyWindow: true))
    }

    func testKeepsPinnedWindow() {
        XCTAssertFalse(makeDecision(isPinned: true))
    }

    func testKeepsWindowThatIsAlreadyCollapsed() {
        XCTAssertFalse(makeDecision(hasFloatingIconPanel: true))
    }

    func testKeepsWindowWhileCollapseAnimationIsRunning() {
        XCTAssertFalse(makeDecision(isAnimatingFloatingIconTransition: true))
    }

    private func makeDecision(
        isPinned: Bool = false,
        hasFloatingIconPanel: Bool = false,
        isAnimatingFloatingIconTransition: Bool = false,
        isWindowVisible: Bool = true,
        isKeyWindow: Bool = false,
        isMiniaturized: Bool = false,
        hiddenFraction: CGFloat = 1
    ) -> Bool {
        WebAppWindowController.shouldCollapseWindowWhenOccluded(
            isPinned: isPinned,
            hasFloatingIconPanel: hasFloatingIconPanel,
            isAnimatingFloatingIconTransition: isAnimatingFloatingIconTransition,
            isWindowVisible: isWindowVisible,
            isKeyWindow: isKeyWindow,
            isMiniaturized: isMiniaturized,
            hiddenFraction: hiddenFraction
        )
    }
}
