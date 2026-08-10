import AppKit
import SwiftUI

@MainActor
final class SideDockOverlayController {
    private static let transitionDuration: TimeInterval = 0.22

    private weak var appModel: AppModel?
    private var panel: SideDockPanel?
    private var apps: [WebAppDefinition] = []
    private var edge: SideDockEdge = .right
    private var verticalPosition = SideDockPlacementResolver.defaultVerticalPosition
    private var preferredDisplayID: CGDirectDisplayID?
    private var isDragging = false
    private var dragOffsetFromPanelCenter: CGFloat?
    private var draggedApp: WebAppDefinition?
    private var latestInwardDistance: CGFloat = 0
    private var latestAlongEdgeTravel: CGFloat = 0
    private var suppressSelectionUntil = Date.distantPast

    func update(
        apps: [WebAppDefinition],
        edge: SideDockEdge,
        verticalPosition: CGFloat,
        preferredDisplayID: CGDirectDisplayID?,
        appModel: AppModel
    ) {
        self.apps = apps
        self.edge = edge
        self.verticalPosition = verticalPosition
        // 偏好里还没有记录过屏幕时保留本次会话已解析出的那块，
        // 否则每次刷新都会退回兜底逻辑重新挑屏幕，Dock 又会开始漂。
        self.preferredDisplayID = preferredDisplayID ?? self.preferredDisplayID
        self.appModel = appModel

        guard !apps.isEmpty else {
            hide()
            return
        }

        present(animated: panel?.isVisible == true)
    }

    func hide() {
        guard let panel, panel.isVisible else {
            return
        }

        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = Self.transitionDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func present(animated: Bool) {
        guard let context = presentationContext() else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = 1
        installRootView(in: panel, context: context)
        let nextFrame = context.panelFrame.integral

        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = Self.transitionDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(nextFrame, display: true)
            }
        } else {
            panel.setFrame(nextFrame, display: true)
        }

        panel.orderFrontRegardless()
    }

    private func installRootView(in panel: SideDockPanel, context: SideDockPresentationContext) {
        let currentBounds = panel.contentView?.bounds
            ?? CGRect(origin: .zero, size: panel.frame.size)
        let rootView = SideDockOverlayRootView(
            context: context,
            onSelectApp: { [weak self] app in
                self?.select(app)
            },
            onDragChange: { [weak self] update in
                self?.drag(update)
            },
            onDragEnd: { [weak self] in
                self?.finishDragging()
            }
        )
        .environment(appModel)

        let hostingView = SideDockHostingView(rootView: AnyView(rootView))
        hostingView.frame = currentBounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    private func select(_ app: WebAppDefinition) {
        guard Date() >= suppressSelectionUntil else {
            return
        }

        appModel?.expandCollapsedWebApp(app)
    }

    private func drag(_ update: SideDockDragUpdate) {
        guard let panel else {
            return
        }

        if !isDragging {
            isDragging = true
            (panel.contentView as? SideDockHostingView)?.isDragging = true
            let panelCenter = edge.isSide ? panel.frame.midY : panel.frame.midX
            let mouseCoordinate = edge.isSide ? update.mouseLocation.y : update.mouseLocation.x
            dragOffsetFromPanelCenter = mouseCoordinate - panelCenter
            draggedApp = update.app
        }

        latestInwardDistance = update.inwardDistance
        latestAlongEdgeTravel = update.alongEdgeTravel
        guard !SideDockDragResolver.isClosingGesture(
            startedOnApp: draggedApp != nil,
            inwardDistance: update.inwardDistance,
            alongEdgeTravel: update.alongEdgeTravel
        ) else {
            return
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(update.mouseLocation) })
            ?? panel.screen
            ?? NSScreen.screens.first else {
            return
        }

        preferredDisplayID = screen.displayID
        let offset = dragOffsetFromPanelCenter ?? 0
        if edge.isSide {
            verticalPosition = SideDockPlacementResolver.normalizedVerticalPosition(
                panelMidY: update.mouseLocation.y - offset,
                visibleFrame: screen.visibleFrame,
                panelHeight: panel.frame.height
            )
        } else {
            verticalPosition = SideDockPlacementResolver.normalizedPosition(
                edge: edge,
                panelMidX: update.mouseLocation.x - offset,
                visibleFrame: screen.visibleFrame,
                panelWidth: panel.frame.width
            )
        }

        if let context = presentationContext() {
            panel.setFrame(context.panelFrame.integral, display: true)
        }
    }

    private func finishDragging() {
        guard isDragging else {
            return
        }

        let appToClose = draggedApp
        let shouldClose = SideDockDragResolver.shouldClose(
            startedOnApp: appToClose != nil,
            inwardDistance: latestInwardDistance,
            alongEdgeTravel: latestAlongEdgeTravel
        )
        isDragging = false
        (panel?.contentView as? SideDockHostingView)?.isDragging = false
        dragOffsetFromPanelCenter = nil
        draggedApp = nil
        latestInwardDistance = 0
        latestAlongEdgeTravel = 0
        suppressSelectionUntil = Date().addingTimeInterval(0.2)

        if shouldClose, let appToClose {
            appModel?.closeCollapsedWebApp(appToClose)
            return
        }

        appModel?.updateSideDockPlacement(
            verticalPosition: verticalPosition,
            displayID: preferredDisplayID
        )
    }

    /// 侧边 Dock 必须钉死在一块屏幕上。
    /// **绝对不能用 `NSScreen.main` 兜底**：它指的是当前键盘焦点所在的屏幕，不是主显示器；
    /// 用它兜底会导致用户在另一块屏上点一下窗口，Dock 下次刷新就整块跳过去。
    private func resolvedScreen() -> NSScreen? {
        if let preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen
        }

        // 从没记住过屏幕，或者原来那块已经拔掉了：优先留在当前已经显示的那块，
        // 否则落到主显示器（菜单栏所在、屏幕列表第一块），并记下来避免下次再漂。
        guard let fallbackScreen = panel?.screen ?? NSScreen.screens.first else {
            return nil
        }

        preferredDisplayID = fallbackScreen.displayID
        return fallbackScreen
    }

    private func presentationContext() -> SideDockPresentationContext? {
        guard let screen = resolvedScreen() else {
            return nil
        }

        return SideDockPresentationContext(
            apps: apps,
            edge: edge,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            verticalPosition: verticalPosition
        )
    }

    private func makePanel() -> SideDockPanel {
        let panel = SideDockPanel(
            contentRect: CGRect(
                origin: .zero,
                size: CGSize(
                    width: SideDockPresentationContext.Layout.thickness,
                    height: SideDockPresentationContext.Layout.thickness
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        return panel
    }
}

/// 侧边 Dock 是非激活浮层，宿主进程多数时候不在前台。
/// 不接管首次点击的话，落在图标以外的空白玻璃上的按下事件只会被系统吞掉，整块 Dock 就拖不动。
private final class SideDockHostingView: NSHostingView<AnyView> {
    /// 拖动中显示抓手，其余时间显示箭头。
    var isDragging = false {
        didSet {
            updateCursor()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // 非激活面板不会自动重置光标：鼠标从终端等窗口移进来时
    // 会残留 I-beam / 十字等形状，这里强制面板区域始终是箭头或抓手。
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    private func updateCursor() {
        (isDragging ? NSCursor.closedHand : NSCursor.arrow).set()
    }
}

private final class SideDockPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    // 液态玻璃会跟随窗口的「活跃外观」变暗。侧边 Dock 是非激活面板，
    // 绝大多数时间既不是 key 也不是 main，若不强制声明活跃外观，
    // 玻璃会一直停在灰暗的收敛状态。
    @objc(_hasActiveAppearance)
    func hasActiveAppearanceForGlass() -> Bool {
        true
    }

    @objc(hasActiveAppearance)
    func hasPublicActiveAppearanceForGlass() -> Bool {
        true
    }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    func hasActiveAppearanceIgnoringKeyFocusForGlass() -> Bool {
        true
    }

    @objc(_hasActiveControls)
    func hasActiveControlsForGlass() -> Bool {
        true
    }

    @objc(_hasKeyAppearance)
    func hasKeyAppearanceForGlass() -> Bool {
        true
    }

    @objc(hasKeyAppearance)
    func hasPublicKeyAppearanceForGlass() -> Bool {
        true
    }

    @objc(_hasMainAppearance)
    func hasMainAppearanceForGlass() -> Bool {
        true
    }

    @objc(hasMainAppearance)
    func hasPublicMainAppearanceForGlass() -> Bool {
        true
    }
}
