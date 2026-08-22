import AppKit

@MainActor
protocol LaunchPlaceholderPresenting: AnyObject {
    func showPlaceholder(for definition: WebAppDefinition, frame: CGRect)
    func orderPlaceholderFront(appID: String)
    func dismissPlaceholder(appID: String)
    func dismissAllPlaceholders()
}

/// 独立进程还没起来时，用一扇和真窗同框的白窗把空白盖住。
/// 这不是第二套界面：没有自己的顶栏、图标或过渡动画。真窗就位后直接揭掉。
@MainActor
final class LaunchPlaceholderController: LaunchPlaceholderPresenting {
    private var windows: [String: NSWindow] = [:]
    private var intendedFrames: [String: CGRect] = [:]
    private var pendingDismissals: [String: Task<Void, Never>] = [:]

    func showPlaceholder(for definition: WebAppDefinition, frame: CGRect) {
        pendingDismissals[definition.id]?.cancel()
        pendingDismissals[definition.id] = nil
        intendedFrames[definition.id] = frame

        if let existing = windows[definition.id] {
            existing.setFrame(frame, display: true)
            present(existing, intendedFrame: frame)
            return
        }

        let window = makeWindow(for: definition, frame: frame)
        windows[definition.id] = window
        present(window, intendedFrame: frame)
    }

    func orderPlaceholderFront(appID: String) {
        guard let window = windows[appID] else {
            return
        }

        pendingDismissals[appID]?.cancel()
        pendingDismissals[appID] = nil
        present(window, intendedFrame: intendedFrames[appID] ?? window.frame)
    }

    func dismissPlaceholder(appID: String) {
        pendingDismissals[appID]?.cancel()
        pendingDismissals[appID] = nil
        guard let window = windows[appID] else {
            return
        }

        tearDown(appID: appID, window: window)
    }

    func dismissAllPlaceholders() {
        let appIDs = Array(windows.keys)
        for appID in appIDs {
            pendingDismissals[appID]?.cancel()
            pendingDismissals[appID] = nil
            if let window = windows[appID] {
                tearDown(appID: appID, window: window)
            }
        }
    }

    private func present(_ window: NSWindow, intendedFrame: CGRect) {
        // 常驻菜单栏应用不抢前台的话，新窗口会画在别的应用下面，看起来就像没弹出来。
        // 占位窗用更高层级，不会被「八成看不见就收进侧边栏」当成挡住真窗。
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        // 系统可能在第一次上屏时按「铺满可用桌面」改框，必须立刻套回宿主算好的那一框。
        window.setFrame(intendedFrame, display: true)
    }

    private func tearDown(appID: String, window: NSWindow) {
        windows.removeValue(forKey: appID)
        intendedFrames.removeValue(forKey: appID)
        pendingDismissals[appID] = nil
        window.orderOut(nil)
    }

    private func makeWindow(
        for definition: WebAppDefinition,
        frame: CGRect
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: WebAppWindowMetrics.defaultContentSize),
            styleMask: WebAppWindowMetrics.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = definition.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = .white
        window.isOpaque = true
        window.toolbar = nil
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.contentMinSize = WebAppWindowMetrics.minimumContentSize
        WebAppWindowMetrics.applyLaunchIsolation(to: window)
        window.setFrame(frame, display: false)

        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }

        let contentView = NSView(frame: .zero)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = contentView
        return window
    }
}
