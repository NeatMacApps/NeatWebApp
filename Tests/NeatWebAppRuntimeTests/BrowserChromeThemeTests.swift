import XCTest
@testable import NeatWebAppRuntime

final class BrowserChromeThemeTests: XCTestCase {
    func testDarkPageUsesLightForeground() {
        let theme = BrowserChromeTheme(
            pageColor: BrowserThemeColor(red: 0.1, green: 0.11, blue: 0.14)
        )

        XCTAssertGreaterThan(theme.foregroundColor.relativeLuminance, 0.9)
        // 深色页面的渐变起始色必须仍然是深色，否则浅色图标会掉进浅底里。
        XCTAssertLessThan(theme.chromeScrimColor.relativeLuminance, 0.5)
    }

    func testLightPageUsesDarkForeground() {
        let theme = BrowserChromeTheme(
            pageColor: BrowserThemeColor(red: 0.94, green: 0.95, blue: 0.97)
        )

        XCTAssertLessThan(theme.foregroundColor.relativeLuminance, 0.05)
        // 浅色页面的渐变起始色必须仍然是浅色，否则深色图标会掉进深底里。
        XCTAssertGreaterThan(theme.chromeScrimColor.relativeLuminance, 0.5)
    }

    func testGradientIsVisibleAgainstPageColor() {
        // 渐变起始色和页面色必须有可感知的差异，否则整条让位带看起来没有任何渐变。
        for pageColor in [
            BrowserThemeColor(red: 1, green: 1, blue: 1),
            BrowserThemeColor(red: 0.07, green: 0.08, blue: 0.09),
            BrowserThemeColor(red: 0, green: 0, blue: 0)
        ] {
            let theme = BrowserChromeTheme(pageColor: pageColor)
            let difference = abs(
                theme.chromeScrimColor.relativeLuminance - theme.pageColor.relativeLuminance
            )
            XCTAssertGreaterThan(difference, 0.01, "页面色 \(pageColor) 下渐变不可见")
        }
    }

    func testMissingPageColorFallsBackToWhiteNotDark() {
        // 网页没有显式背景时浏览器画的是白色；退回深色会让让位带变成一条黑条。
        XCTAssertGreaterThan(BrowserChromeTheme.fallback.pageColor.relativeLuminance, 0.9)
    }

    func testParsesThemeColorFromScriptMessage() {
        let color = BrowserThemeColor.fromScriptMessageBody([
            "red": 0.25,
            "green": 0.5,
            "blue": 0.75,
            "alpha": 0.6
        ])

        XCTAssertEqual(color, BrowserThemeColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.6))
    }
}
