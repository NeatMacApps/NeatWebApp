import XCTest
@testable import NeatWebAppRuntime

@MainActor
final class WebAppWindowAutoCollapseTests: XCTestCase {
    /// 被别的窗口盖住、切到别的桌面空间、别的应用进入全屏，系统都报告成同一件事：看不见。
    func testCollapsesWheneverTheWindowIsNotVisibleOnScreen() {
        XCTAssertTrue(makeDecision())
    }

    func testKeepsWindowWhenStillPartiallyVisible() {
        XCTAssertFalse(makeDecision(isOccluded: false))
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
        isOccluded: Bool = true
    ) -> Bool {
        WebAppWindowController.shouldCollapseWindowWhenOccluded(
            isPinned: isPinned,
            hasFloatingIconPanel: hasFloatingIconPanel,
            isAnimatingFloatingIconTransition: isAnimatingFloatingIconTransition,
            isWindowVisible: isWindowVisible,
            isKeyWindow: isKeyWindow,
            isMiniaturized: isMiniaturized,
            isOccluded: isOccluded
        )
    }
}
