import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class WebAppWindowController: NSWindowController, NSWindowDelegate, BrowserSessionCommandHandling {
    enum WindowMetrics {
        static let defaultContentSize = WebAppWindowMetrics.defaultContentSize
        static let minimumContentSize = WebAppWindowMetrics.minimumContentSize
        static let floatingIconDiameter: CGFloat = 52 * 0.8 * 0.9
        static let floatingIconShadowPadding: CGFloat = 10
        static let floatingIconTransitionDuration: TimeInterval = 0.3
        static let pinnedWindowLevel = NSWindow.Level.floating
        static let floatingIconLevel = NSWindow.Level(rawValue: pinnedWindowLevel.rawValue + 1)
        /// 用户刚点开或从刘海唤出后，窗口列表和焦点还没站稳，这段时间不自动收起。
        /// 这不是「被挡住再等两秒」的旧延时：过了这段仍按八成看不见立刻收。
        static let autoCollapseGraceAfterExplicitShow: TimeInterval = 1.2
    }

    let session: BrowserSession
    weak var eventSink: (any RuntimeWindowEventSink)?
    let preferredGeometry: ScreenNotchGeometry?
    let faviconStore = WebAppFaviconStore()
    var floatingIconPanel: FloatingWebAppIconPanel?
    var expandedWindowFrameBeforeCollapse: CGRect?
    var isAnimatingFloatingIconTransition = false
    var lastExternalFrontmostApplication: NSRunningApplication?
    var coverageWatchTask: Task<Void, Never>?
    /// 窗口拖动时 windowDidMove 高频触发：全量偏好编解码 + 文件协调锁不能每 tick 跑，
    /// 先记一笔、停稳再写；隐藏/关闭/缩放结束走立即落盘。
    var pendingFramePersistTask: Task<Void, Never>?
    var environmentObservers: [NSObjectProtocol] = []
    var suppressAutoCollapseUntil = Date.distantPast
    /// 置顶跟随鼠标聚焦的全局+本地 mouseMoved 监听。只在置顶时装上，
    /// 不置顶、隐藏、关闭时拆掉，避免常驻唤醒。
    var hoverFocusGlobalMonitor: Any?
    var hoverFocusLocalMonitor: Any?
    /// 宿主已经把占位窗摆到这个框上时，首次显示禁止再挪，否则会跳一下。
    var skipNextVisibilityCorrection = false
    /// 盖子还在时不要抢焦点、不要报「窗口已显示」，否则宿主会提前揭盖，底下还是空的。
    var isAwaitingHostCoverLift = false
    var hasOrderedFrontUnderCover = false
    var contentPaintedUnderCover = false
    /// 宿主已经定好的框。第一次上屏期间系统 / SwiftUI 改框都要套回去。
    var lockedLaunchFrame: CGRect?
    var shouldHoldLaunchFrame = false
    let dockReserveStore: SideDockReserveStore
    var dockReserve: SideDockScreenReserve?

    init(
        definition: WebAppDefinition,
        preferencesStore: WebAppPreferencesStore,
        preferredGeometry: ScreenNotchGeometry?,
        eventSink: (any RuntimeWindowEventSink)?,
        dockReserveStore: SideDockReserveStore = SideDockReserveStore(),
        restoredWindowFrame: CGRect? = nil,
        lockRestoredFrame: Bool = false
    ) {
        let preference = preferencesStore.load(for: definition.id)
        self.session = BrowserSession(
            definition: definition,
            preference: preference,
            preferencesStore: preferencesStore
        )
        self.eventSink = eventSink
        self.preferredGeometry = preferredGeometry
        self.dockReserveStore = dockReserveStore
        self.dockReserve = dockReserveStore.load()
        self.skipNextVisibilityCorrection = lockRestoredFrame && restoredWindowFrame != nil
        self.isAwaitingHostCoverLift = lockRestoredFrame && restoredWindowFrame != nil

        let window = WebAppBrowserWindow(
            contentRect: CGRect(origin: .zero, size: WindowMetrics.defaultContentSize),
            styleMask: WebAppWindowMetrics.styleMask,
            backing: .buffered,
            defer: false
        )
        window.dockReserve = dockReserve
        window.ignoresDockAvoidance = lockRestoredFrame && restoredWindowFrame != nil

        super.init(window: window)

        configureWindow(window, definition: definition, isPinned: preference.isPinned)
        applyInitialFrame(
            using: preference,
            restoredWindowFrame: restoredWindowFrame,
            to: window,
            preferredGeometry: preferredGeometry
        )
        if isAwaitingHostCoverLift {
            session.onFirstContentPaint = { [weak self] in
                self?.markCoveredContentPainted()
            }
        }
        wireSession(to: window)
        restoreLockedFrameIfNeeded(on: window)
        if preference.isPinned {
            startHoverFocusMonitoringIfNeeded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 公开 API

    func applyDockReserve(_ reserve: SideDockScreenReserve?) {
        dockReserve = reserve
        browserWindow?.dockReserve = reserve
        clampWindowToDockReserveIfNeeded()
    }

    /// 宿主改了目录里的定义后，同步窗口标题、当前会话，以及已收起时的侧边图标名称。
    func applyDefinition(_ definition: WebAppDefinition) {
        session.applyDefinition(definition)
        window?.title = definition.name

        guard let floatingIconPanel else {
            return
        }

        let iconImage = faviconStore.load(for: session.definition.id)
        floatingIconPanel.contentView = FloatingWebAppIconView(
            iconImage: iconImage,
            appName: session.definition.name
        ) { [weak self] in
            self?.expandFromFloatingIcon()
        }
    }

    func showAndFocus(preferredGeometry: ScreenNotchGeometry? = nil) {
        stopCoverageWatch()
        applyDockReserve(dockReserveStore.load())
        suppressAutoCollapseUntil = Date().addingTimeInterval(WindowMetrics.autoCollapseGraceAfterExplicitShow)
        startEnvironmentObserversIfNeeded()

        if floatingIconPanel != nil {
            expandFromFloatingIcon(shouldFocusWebView: true)
            return
        }

        rememberFrontmostExternalApplication()
        if skipNextVisibilityCorrection {
            skipNextVisibilityCorrection = false
        } else {
            ensureWindowFrameIsVisible(preferredGeometry: preferredGeometry ?? self.preferredGeometry)
        }

        // 系统默认会给新窗口做缩放弹出。占位盖还在上面时，这个动画会从盖子底下透出来。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window?.deminiaturize(nil)
            window?.orderFrontRegardless()
            if let window {
                restoreLockedFrameIfNeeded(on: window)
            }
            NSApp.activate(ignoringOtherApps: true)
            if !isAwaitingHostCoverLift {
                window?.makeKey()
            }
        }

        if isAwaitingHostCoverLift {
            hasOrderedFrontUnderCover = true
            scheduleCoveredFirstShowTimeout()
            finishCoveredFirstShowIfReady()
            return
        }

        releaseLaunchFrameHoldIfNeeded()
        session.focusWebView()
        startHoverFocusMonitoringIfNeeded()
        publishRuntimeUpdate(phase: .windowVisible, windowFrame: window?.frame, floatingIconFrame: nil)
    }

    func collapseWindow() {
        stopCoverageWatch()
        stopHoverFocusMonitoring()
        collapseToFloatingIcon()
    }

    func restoreCollapsedWindow(windowFrame: CGRect?, iconFrame _: CGRect?) {
        stopCoverageWatch()
        stopEnvironmentObservers()
        stopHoverFocusMonitoring()

        guard !isAnimatingFloatingIconTransition else {
            return
        }

        if let windowFrame {
            window?.setFrame(windowFrame, display: false)
            expandedWindowFrameBeforeCollapse = windowFrame
        } else if let window {
            expandedWindowFrameBeforeCollapse = window.frame
        }

        hideFloatingIcon()
        window?.orderOut(nil)
        publishRuntimeUpdate(
            phase: .collapsedToFloatingIcon,
            windowFrame: expandedWindowFrameBeforeCollapse,
            floatingIconFrame: nil
        )
    }

    func updatePinnedState(_ isPinned: Bool) {
        window?.level = isPinned ? WindowMetrics.pinnedWindowLevel : .normal
        if isPinned {
            stopCoverageWatch()
            startHoverFocusMonitoringIfNeeded()
        } else {
            stopHoverFocusMonitoring()
        }
    }

    /// 置顶后鼠标进入窗口即抢回 key 焦点并聚焦网页，便于并排多应用快速切换输入。
    /// 跟随图钉默认开，无独立开关、无悬停延迟；拖拽/缩放、盖子未揭、
    /// 有模态或鼠标按住时不抢。
    func startHoverFocusMonitoringIfNeeded() {
        guard session.isPinned,
            hoverFocusGlobalMonitor == nil,
            hoverFocusLocalMonitor == nil
        else {
            return
        }

        hoverFocusGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleHoverFocusTick()
            }
        }
        hoverFocusLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleHoverFocusTick()
            }
            return event
        }
    }

    func stopHoverFocusMonitoring() {
        if let hoverFocusGlobalMonitor {
            NSEvent.removeMonitor(hoverFocusGlobalMonitor)
        }
        if let hoverFocusLocalMonitor {
            NSEvent.removeMonitor(hoverFocusLocalMonitor)
        }
        hoverFocusGlobalMonitor = nil
        hoverFocusLocalMonitor = nil
    }

    func handleHoverFocusTick() {
        guard session.isPinned,
            let window,
            window.isVisible,
            !window.isMiniaturized,
            !window.isKeyWindow,
            window.attachedSheet == nil,
            NSApp.modalWindow == nil,
            NSEvent.pressedMouseButtons == 0,
            !isAwaitingHostCoverLift,
            !isAnimatingFloatingIconTransition,
            floatingIconPanel == nil
        else {
            return
        }

        guard window.frame.contains(NSEvent.mouseLocation) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        session.focusWebView()
    }

    func hideWindow() {
        stopCoverageWatch()
        stopEnvironmentObservers()
        stopHoverFocusMonitoring()
        persistWindowFrame()
        hideFloatingIcon()
        window?.orderOut(nil)
        publishRuntimeUpdate(phase: .hidden, windowFrame: window?.frame, floatingIconFrame: nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        if shouldHoldLaunchFrame {
            restoreLockedFrameIfNeeded(on: window)
            return
        }

        schedulePersistWindowFrame()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // 只有显示器断开、整扇窗掉到所有屏幕之外时才找回；
        // 普通拖到屏幕边缘（还压着当前屏）不碰，免得刚拖出去就被拽回来。
        guard let window else {
            return
        }

        let stillOnSomeScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
        guard !stillOnSomeScreen else {
            return
        }

        ensureWindowFrameIsVisible(preferredGeometry: preferredGeometry)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        flushPendingFramePersist()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if shouldHoldLaunchFrame, let lockedLaunchFrame {
            return lockedLaunchFrame.size
        }

        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        restoreLockedFrameIfNeeded(on: window)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard !shouldHoldLaunchFrame else {
            return lockedLaunchFrame ?? newFrame
        }

        return WebAppWindowPlacementResolver.clamp(newFrame, into: placementScreens())
    }

    func windowDidBecomeKey(_ notification: Notification) {
        stopCoverageWatch()
        session.focusWebView()
        guard !isAwaitingHostCoverLift else {
            return
        }

        eventSink?.webAppWindowDidFocus(appID: session.definition.id, windowFrame: window?.frame)
    }

    func windowDidResignKey(_ notification: Notification) {
        startCoverageWatch()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        evaluateAutoCollapse()
        if window?.isKeyWindow == false {
            startCoverageWatch()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestCloseWindow()
        return false
    }

    // MARK: - BrowserSessionCommandHandling

    func browserSessionDidRequestClose(_ session: BrowserSession) {
        requestCloseWindow()
    }

    func browserSessionDidRequestCollapse(_ session: BrowserSession) {
        collapseToFloatingIcon()
    }

    // MARK: - 盖子下首次显示

    func markCoveredContentPainted() {
        contentPaintedUnderCover = true
        finishCoveredFirstShowIfReady()
    }

    private func scheduleCoveredFirstShowTimeout() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.markCoveredContentPainted()
        }
    }

    private func finishCoveredFirstShowIfReady() {
        guard isAwaitingHostCoverLift, hasOrderedFrontUnderCover, contentPaintedUnderCover else {
            return
        }

        isAwaitingHostCoverLift = false
        releaseLaunchFrameHoldIfNeeded()
        publishRuntimeUpdate(phase: .windowVisible, windowFrame: window?.frame, floatingIconFrame: nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        session.focusWebView()
    }

    // MARK: - 关闭与装配

    func requestCloseWindow() {
        guard let eventSink else {
            hideWindow()
            return
        }

        stopCoverageWatch()
        stopHoverFocusMonitoring()
        persistWindowFrame()
        hideFloatingIcon()
        eventSink.webAppWindowDidRequestClose(self)
    }

    private func configureWindow(_ window: NSWindow, definition: WebAppDefinition, isPinned: Bool) {
        window.delegate = self
        window.title = definition.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = BrowserChromeTheme.fallback.pageColor.nsColor
        window.level = isPinned ? WindowMetrics.pinnedWindowLevel : .normal
        window.contentMinSize = WindowMetrics.minimumContentSize
        window.toolbar = nil
        WebAppWindowMetrics.applyLaunchIsolation(to: window)

        // 悬浮圆点在所有桌面空间都点得到，窗口必须跟着来找用户；
        // 否则从别的桌面点圆点会把用户硬拽回窗口原来所在的桌面空间。
        window.collectionBehavior.insert(.moveToActiveSpace)

        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }
    }

    private func wireSession(to window: NSWindow) {
        let rootView = BrowserContainerView(session: session)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.updateConstraintsIfNeeded()
        restoreLockedFrameIfNeeded(on: window)

        session.onChromeThemeChange = { [weak self] theme in
            self?.window?.backgroundColor = theme.pageColor.nsColor
        }
        session.onPinnedChange = { [weak self] isPinned in
            self?.updatePinnedState(isPinned)
        }
        session.commandHandler = self

        window.backgroundColor = session.chromeTheme.pageColor.nsColor
    }

    func publishRuntimeUpdate(
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    ) {
        eventSink?.webAppWindowDidUpdate(
            appID: session.definition.id,
            phase: phase,
            windowFrame: windowFrame,
            floatingIconFrame: floatingIconFrame
        )
    }

    var browserWindow: WebAppBrowserWindow? {
        window as? WebAppBrowserWindow
    }
}
