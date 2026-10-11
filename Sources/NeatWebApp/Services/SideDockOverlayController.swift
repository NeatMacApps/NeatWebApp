import AppKit
import MacKitGlass
import Observation
import SwiftUI

@MainActor
@Observable
final class SideDockOverlayState {
    var context: SideDockPresentationContext
    var isDragging = false

    init(context: SideDockPresentationContext) {
        self.context = context
    }
}

@MainActor
final class SideDockOverlayController {
    private static let transitionDuration: TimeInterval = 0.22

    private weak var appModel: AppModel?
    private var panel: SideDockPanel?
    private var overlayState: SideDockOverlayState?
    private var dockHostingView: SideDockHostingView?
    private var apps: [WebAppDefinition] = []
    private var edge: SideDockEdge = .right
    private var verticalPosition = SideDockPlacementResolver.defaultVerticalPosition
    private var floatingPosition: CGPoint?
    private var preferredDisplayID: CGDirectDisplayID?
    private var isDragging = false
    private var dragCompletionTask: Task<Void, Never>?
    private var hideGeneration = 0
    private var suppressSelectionUntil = Date.distantPast

    func update(
        apps: [WebAppDefinition],
        edge: SideDockEdge,
        verticalPosition: CGFloat,
        floatingPosition: CGPoint?,
        preferredDisplayID: CGDirectDisplayID?,
        appModel: AppModel
    ) {
        self.apps = apps
        self.appModel = appModel
        guard !isDragging else { return }
        self.edge = edge
        self.verticalPosition = verticalPosition
        self.floatingPosition = floatingPosition
        self.preferredDisplayID = preferredDisplayID ?? self.preferredDisplayID
        guard !apps.isEmpty else {
            hide()
            return
        }
        present(animated: panel?.isVisible == true)
    }

    func hide() {
        hideGeneration += 1
        let generation = hideGeneration
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = Self.transitionDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                // A newer show must not be hidden by an older fade completion.
                guard let self, self.hideGeneration == generation else { return }
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        }
    }

    private func present(animated: Bool) {
        guard let context = presentationContext() else {
            hide()
            return
        }
        hideGeneration += 1
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = 1
        installRootView(in: panel, context: context)
        let nextFrame = context.panelFrame.integral
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
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
        if let overlayState {
            overlayState.context = context
            return
        }
        let overlayState = SideDockOverlayState(context: context)
        self.overlayState = overlayState
        let rootView = SideDockOverlayRootView(
            state: overlayState,
            onSelectApp: { [weak self] app in self?.select(app) }
        )
        .environment(appModel)
        let hostingView = SideDockHostingView(rootView: AnyView(rootView))
        hostingView.frame = CGRect(origin: .zero, size: context.layout.panelSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.clearHostingBackground()
        dockHostingView = hostingView
        panel.contentView = hostingView
    }

    private func select(_ app: WebAppDefinition) {
        guard !isDragging, Date() >= suppressSelectionUntil else { return }
        appModel?.expandCollapsedWebApp(app)
    }

    private func beginNativeDragging() {
        isDragging = true
        overlayState?.isDragging = true
        dockHostingView?.isDragging = true
        dragCompletionTask?.cancel()
        // AppKit hands tracking to Window Server, which may consume the mouse-up event.
        dragCompletionTask = Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
            }
            self?.finishNativeDragging()
        }
    }

    private func finishNativeDragging() {
        guard isDragging, let panel else { return }
        isDragging = false
        panel.isNativeDragging = false
        overlayState?.isDragging = false
        dockHostingView?.isDragging = false
        suppressSelectionUntil = Date().addingTimeInterval(0.2)
        // Resolve by the actual dragged panel, never by keyboard focus.
        let screen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(panel.frame, lhs.visibleFrame) < intersectionArea(panel.frame, rhs.visibleFrame)
        } ?? panel.screen
        guard let screen else { return }
        preferredDisplayID = screen.displayID
        floatingPosition = SideDockPlacementResolver.normalizedPosition(
            panelFrame: panel.frame, visibleFrame: screen.visibleFrame
        )
        if let floatingPosition {
            appModel?.updateSideDockPlacement(
                floatingPosition: floatingPosition, displayID: preferredDisplayID
            )
        }
    }

    private func intersectionArea(_ frame: CGRect, _ visibleFrame: CGRect) -> CGFloat {
        let intersection = frame.intersection(visibleFrame)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func resolvedScreen() -> NSScreen? {
        if let preferredDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen
        }
        guard let screen = panel?.screen ?? NSScreen.screens.first else { return nil }
        preferredDisplayID = screen.displayID
        return screen
    }

    private func presentationContext() -> SideDockPresentationContext? {
        guard let screen = resolvedScreen() else { return nil }
        return SideDockPresentationContext(
            apps: apps,
            edge: edge,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            verticalPosition: verticalPosition,
            floatingPosition: floatingPosition
        )
    }

    private func makePanel() -> SideDockPanel {
        let panel = SideDockPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 47, height: 47)),
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
        panel.onBeginDragging = { [weak self] in self?.beginNativeDragging() }
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

    override var isOpaque: Bool {
        false
    }

    override func layout() {
        super.layout()
        clearHostingBackground()
        applyClearLiquidGlassIfAvailable()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearHostingBackground()
        applyClearLiquidGlassIfAvailable()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        applyClearLiquidGlassIfAvailable()
    }

    /// macOS 26 的 `NSHostingView` 会按窗口背景画出一层不透明浅色矩形，
    /// 只清 CALayer 不够，玻璃再通透也会被这块底板托成浅色方块。
    func clearHostingBackground() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        setValue(NSColor.clear, forKey: "backgroundColor")
        safeAreaRegions = []
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

    private func applyClearLiquidGlassIfAvailable() {
        guard #available(macOS 26.0, *) else {
            return
        }

        ClearLiquidGlass.apply(in: self)
    }
}

private final class SideDockPanel: NSPanel {
    var onBeginDragging: (() -> Void)?
    var isNativeDragging = false
    private var mouseDownEvent: NSEvent?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownEvent = event
        case .leftMouseDragged:
            if let start = mouseDownEvent,
               hypot(event.locationInWindow.x - start.locationInWindow.x,
                     event.locationInWindow.y - start.locationInWindow.y) >= 8 {
                mouseDownEvent = nil
                isNativeDragging = true
                onBeginDragging?()
                performDrag(with: start)
                return
            }
        case .leftMouseUp:
            mouseDownEvent = nil
            if isNativeDragging { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool {
        false
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
