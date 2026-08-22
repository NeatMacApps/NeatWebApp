import AppKit

/// 网页应用窗口的共用尺寸与样式。宿主占位窗和运行时真窗必须用同一套，
/// 否则点开瞬间的占位框会对不齐稍后出现的真窗口。
enum WebAppWindowMetrics {
    static let defaultContentSize = NSSize(width: 460, height: 900)
    static let minimumContentSize = NSSize(width: 390, height: 640)
    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView
    ]

    static var defaultFrameSize: CGSize {
        frameSize(forContentSize: defaultContentSize)
    }

    static var minimumFrameSize: CGSize {
        frameSize(forContentSize: minimumContentSize)
    }

    static func frameSize(forContentSize contentSize: NSSize) -> CGSize {
        // 本窗是 fullSizeContentView：内容铺满外框，外框就是内容尺寸。
        // 不要用 NSWindow.frameRect：它不认这条样式；更不要为了量尺寸去建一扇窗再关掉。
        contentSize
    }

    /// 禁止系统按「上次的窗口」或标签页组去改框：否则盖子和真窗会各走各的尺寸。
    static func applyLaunchIsolation(to window: NSWindow) {
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .none
    }
}
