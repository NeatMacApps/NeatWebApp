import CoreGraphics

/// 浏览器顶部让位带的共用尺寸。占位窗要画成空的真窗，尺寸必须跟真窗同一份。
enum BrowserChromeMetrics {
    static let bandHeight: CGFloat = 40
    static let windowMargin: CGFloat = 10
    static let buttonSize: CGFloat = 24
    static let buttonSpacing: CGFloat = 2
    static let iconFontSize: CGFloat = 11
    static let titleFontSize: CGFloat = 12
    /// 居中标题两侧的预留宽度：至少盖住左侧三按钮，避免和两侧控件重叠。
    /// 有下载胶囊时右侧更宽，需要更大的对称预留，保证标题视觉上仍在正中间。
    static let titleSideReserve: CGFloat = 100
    static let titleSideReserveWithDownload: CGFloat = 150

    static func titleSideReserve(hasDownload: Bool) -> CGFloat {
        hasDownload ? titleSideReserveWithDownload : titleSideReserve
    }

    /// 标题只有在中间空隙放得下时才展示，放不下直接隐藏，不做截断。
    static func titleFits(bandWidth: CGFloat, titleWidth: CGFloat, hasDownload: Bool) -> Bool {
        guard bandWidth > 0, titleWidth >= 0 else {
            return false
        }

        let available = bandWidth - (titleSideReserve(hasDownload: hasDownload) * 2)
        guard available > 0 else {
            return false
        }

        return titleWidth <= available
    }
}
