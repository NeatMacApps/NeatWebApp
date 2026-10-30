import XCTest
@testable import NeatWebAppRuntime

final class BrowserChromeTitleTests: XCTestCase {
    func testWideWindowFitsTitle() {
        XCTAssertTrue(BrowserChromeMetrics.titleFits(bandWidth: 800, titleWidth: 120, hasDownload: false))
    }

    func testNarrowWindowHidesTitle() {
        XCTAssertFalse(BrowserChromeMetrics.titleFits(bandWidth: 240, titleWidth: 120, hasDownload: false))
    }

    func testDownloadReserveHidesEarlier() {
        // 同一宽度下，有下载胶囊时两侧预留更大，标题更容易放不下。
        XCTAssertTrue(BrowserChromeMetrics.titleFits(bandWidth: 360, titleWidth: 100, hasDownload: false))
        XCTAssertFalse(BrowserChromeMetrics.titleFits(bandWidth: 360, titleWidth: 100, hasDownload: true))
    }
}
