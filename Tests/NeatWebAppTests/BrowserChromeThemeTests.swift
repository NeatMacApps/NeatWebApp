import XCTest
@testable import NeatWebApp

final class BrowserChromeThemeTests: XCTestCase {
    func testDarkPageUsesLightForeground() {
        let theme = BrowserChromeTheme(
            pageColor: BrowserThemeColor(red: 0.1, green: 0.11, blue: 0.14)
        )

        XCTAssertGreaterThan(theme.foregroundColor.relativeLuminance, 0.9)
        XCTAssertGreaterThan(theme.barTopColor.relativeLuminance, theme.pageColor.relativeLuminance)
    }

    func testLightPageUsesDarkForeground() {
        let theme = BrowserChromeTheme(
            pageColor: BrowserThemeColor(red: 0.94, green: 0.95, blue: 0.97)
        )

        XCTAssertLessThan(theme.foregroundColor.relativeLuminance, 0.05)
        XCTAssertLessThan(theme.barBottomColor.relativeLuminance, theme.pageColor.relativeLuminance)
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
