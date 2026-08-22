import CoreGraphics

/// 浏览器顶部让位带的共用尺寸。占位窗要画成空的真窗，尺寸必须跟真窗同一份。
enum BrowserChromeMetrics {
    static let bandHeight: CGFloat = 40
    static let windowMargin: CGFloat = 10
    static let buttonSize: CGFloat = 24
    static let buttonSpacing: CGFloat = 2
    static let iconFontSize: CGFloat = 11
}
