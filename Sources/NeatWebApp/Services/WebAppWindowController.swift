import AppKit
import QuartzCore
import SwiftUI

@MainActor
protocol RuntimeWindowEventSink: AnyObject {
    func webAppWindowDidRequestClose(_ controller: WebAppWindowController)

    func webAppWindowDidUpdate(
        appID: String,
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    )

    func webAppWindowDidFocus(appID: String, windowFrame: CGRect?)
}

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
    private weak var eventSink: (any RuntimeWindowEventSink)?
    private let preferredGeometry: ScreenNotchGeometry?
    private let faviconStore = WebAppFaviconStore()
    private var floatingIconPanel: FloatingWebAppIconPanel?
    private var expandedWindowFrameBeforeCollapse: CGRect?
    private var isAnimatingFloatingIconTransition = false
    private var lastExternalFrontmostApplication: NSRunningApplication?
    private var coverageWatchTask: Task<Void, Never>?
    private var environmentObservers: [NSObjectProtocol] = []
    private var suppressAutoCollapseUntil = Date.distantPast
    /// 宿主已经把占位窗摆到这个框上时，首次显示禁止再挪，否则会跳一下。
    private var skipNextVisibilityCorrection = false
    /// 盖子还在时不要抢焦点、不要报「窗口已显示」，否则宿主会提前揭盖，底下还是空的。
    private var isAwaitingHostCoverLift = false
    private var hasOrderedFrontUnderCover = false
    private var contentPaintedUnderCover = false
    /// 宿主已经定好的框。第一次上屏期间系统 / SwiftUI 改框都要套回去。
    private var lockedLaunchFrame: CGRect?
    private var shouldHoldLaunchFrame = false
    private let dockReserveStore: SideDockReserveStore
    private var dockReserve: SideDockScreenReserve?

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        publishRuntimeUpdate(phase: .windowVisible, windowFrame: window?.frame, floatingIconFrame: nil)
    }

    private func markCoveredContentPainted() {
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

    func collapseWindow() {
        stopCoverageWatch()
        collapseToFloatingIcon()
    }

    func restoreCollapsedWindow(windowFrame: CGRect?, iconFrame _: CGRect?) {
        stopCoverageWatch()
        stopEnvironmentObservers()

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
        }
    }

    func windowDidMove(_ notification: Notification) {
        if shouldHoldLaunchFrame {
            restoreLockedFrameIfNeeded(on: window)
            return
        }

        persistWindowFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistWindowFrame()
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

    func hideWindow() {
        stopCoverageWatch()
        stopEnvironmentObservers()
        persistWindowFrame()
        hideFloatingIcon()
        window?.orderOut(nil)
        publishRuntimeUpdate(phase: .hidden, windowFrame: window?.frame, floatingIconFrame: nil)
    }

    func browserSessionDidRequestClose(_ session: BrowserSession) {
        requestCloseWindow()
    }

    func browserSessionDidRequestCollapse(_ session: BrowserSession) {
        collapseToFloatingIcon()
    }

    private func requestCloseWindow() {
        guard let eventSink else {
            hideWindow()
            return
        }

        stopCoverageWatch()
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

    private func collapseToFloatingIcon() {
        stopCoverageWatch()

        guard let window, !isAnimatingFloatingIconTransition else {
            return
        }

        persistWindowFrame()
        expandedWindowFrameBeforeCollapse = window.frame
        let shouldAnimateTransition = shouldAnimateFloatingIconTransition()
        hideFloatingIcon()

        guard shouldAnimateTransition else {
            window.orderOut(nil)
            window.alphaValue = 1
            publishRuntimeUpdate(
                phase: .collapsedToFloatingIcon,
                windowFrame: expandedWindowFrameBeforeCollapse,
                floatingIconFrame: nil
            )
            reactivateLastExternalApplicationIfPossible()
            return
        }

        isAnimatingFloatingIconTransition = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowMetrics.floatingIconTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self else {
                    return
                }

                if let window {
                    window.orderOut(nil)
                    window.alphaValue = 1
                }
                self.isAnimatingFloatingIconTransition = false
                self.publishRuntimeUpdate(
                    phase: .collapsedToFloatingIcon,
                    windowFrame: self.expandedWindowFrameBeforeCollapse,
                    floatingIconFrame: nil
                )
                self.reactivateLastExternalApplicationIfPossible()
            }
        }
    }

    @discardableResult
    private func showFloatingIcon(frame: CGRect) -> FloatingWebAppIconPanel {
        let panel = floatingIconPanel ?? makeFloatingIconPanel()
        floatingIconPanel = panel
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        return panel
    }

    private func expandFromFloatingIcon(shouldFocusWebView: Bool = true) {
        guard let window, !isAnimatingFloatingIconTransition else {
            hideFloatingIcon()
            return
        }

        let panel = floatingIconPanel
        let iconFrame = panel?.frame

        guard let iconFrame else {
            if shouldFocusWebView {
                showAndFocus()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        rememberFrontmostExternalApplication()
        let iconTopLeft = floatingIconVisualTopLeft(from: iconFrame)
        var restoredFrame = frameAlignedToTopLeft(
            size: expandedWindowFrameBeforeCollapse?.size ?? window.frame.size,
            topLeft: iconTopLeft
        )
        restoredFrame = clampToVisibleFrame(restoredFrame, around: iconTopLeft)
        window.setFrame(restoredFrame, display: false)
        window.alphaValue = 1

        isAnimatingFloatingIconTransition = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowMetrics.floatingIconTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else {
                    return
                }

                self.hideFloatingIcon()
                NSApp.activate(ignoringOtherApps: true)
                window.deminiaturize(nil)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                window.alphaValue = 1
                self.persistWindowFrame()
                self.isAnimatingFloatingIconTransition = false
                self.publishRuntimeUpdate(phase: .windowVisible, windowFrame: window.frame, floatingIconFrame: nil)
                if shouldFocusWebView {
                    self.session.focusWebView()
                }
            }
        }
    }

    private func hideFloatingIcon() {
        floatingIconPanel?.orderOut(nil)
        floatingIconPanel = nil
    }

    private func floatingIconFrame(alignedToTopLeft topLeft: CGPoint) -> CGRect {
        let panelSize = CGSize(
            width: WindowMetrics.floatingIconDiameter + (WindowMetrics.floatingIconShadowPadding * 2),
            height: WindowMetrics.floatingIconDiameter + (WindowMetrics.floatingIconShadowPadding * 2)
        )
        let proposedFrame = CGRect(
            x: topLeft.x - WindowMetrics.floatingIconShadowPadding,
            y: topLeft.y - panelSize.height + WindowMetrics.floatingIconShadowPadding,
            width: panelSize.width,
            height: panelSize.height
        )

        return FloatingIconSnapResolver.resolvePanelFrame(
            proposedFrame: proposedFrame,
            anchorPoint: topLeft,
            availableScreens: NSScreen.screens.map { WebAppWindowPlacementScreen(screen: $0) },
            fallbackScreen: NSScreen.main.map { WebAppWindowPlacementScreen(screen: $0) },
            shadowPadding: WindowMetrics.floatingIconShadowPadding
        )
    }

    private func shouldAnimateFloatingIconTransition() -> Bool {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return NSApp.isActive
        }

        return frontmostApplication.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func floatingIconVisualTopLeft(from panelFrame: CGRect) -> CGPoint {
        CGPoint(
            x: panelFrame.minX + WindowMetrics.floatingIconShadowPadding,
            y: panelFrame.maxY - WindowMetrics.floatingIconShadowPadding
        )
    }

    private func frameAlignedToTopLeft(size: CGSize, topLeft: CGPoint) -> CGRect {
        CGRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func clampToVisibleFrame(_ frame: CGRect, around anchorPoint: CGPoint) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main else {
            return frame
        }

        let usableFrame = SideDockWindowAvoidance.usableFrame(
            visibleFrame: screen.visibleFrame,
            reserve: dockReserve,
            screenDisplayID: screen.displayID
        )
        return SideDockWindowAvoidance.clamp(frame, into: usableFrame)
    }

    private func makeFloatingIconPanel() -> FloatingWebAppIconPanel {
        let diameter = WindowMetrics.floatingIconDiameter + (WindowMetrics.floatingIconShadowPadding * 2)
        let panel = FloatingWebAppIconPanel(
            contentRect: CGRect(x: 0, y: 0, width: diameter, height: diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = WindowMetrics.floatingIconLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let iconImage = faviconStore.load(for: session.definition.id)
        panel.contentView = FloatingWebAppIconView(
            iconImage: iconImage,
            appName: session.definition.name
        ) { [weak self] in
            self?.expandFromFloatingIcon()
        }
        return panel
    }

    private func rememberFrontmostExternalApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return
        }

        guard frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        lastExternalFrontmostApplication = frontmostApplication
    }

    private func reactivateLastExternalApplicationIfPossible() {
        guard let application = lastExternalFrontmostApplication, !application.isTerminated else {
            return
        }

        lastExternalFrontmostApplication = nil
        application.activate(options: [])
    }

    private func persistWindowFrame() {
        guard let window, !shouldHoldLaunchFrame, !window.isZoomed else {
            return
        }

        if let screen = window.screen {
            let usableFrame = SideDockWindowAvoidance.usableFrame(
                visibleFrame: screen.visibleFrame,
                reserve: dockReserve,
                screenDisplayID: screen.displayID
            )
            if WebAppWindowPlacementResolver.isFillVisibleFrame(window.frame, visibleFrame: screen.visibleFrame)
                || WebAppWindowPlacementResolver.isFillVisibleFrame(window.frame, visibleFrame: usableFrame) {
                return
            }
        }

        session.persistWindowFrame(window.frame, on: window.screen)
    }

    private func publishRuntimeUpdate(
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

    private func startEnvironmentObserversIfNeeded() {
        guard environmentObservers.isEmpty else {
            return
        }

        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            environmentObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.evaluateAutoCollapse()
                        if self?.window?.isKeyWindow == false {
                            self?.startCoverageWatch()
                        }
                    }
                }
            )
        }
    }

    private func stopEnvironmentObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in environmentObservers {
            center.removeObserver(observer)
        }
        environmentObservers.removeAll()
    }

    private func startCoverageWatch() {
        startEnvironmentObserversIfNeeded()
        evaluateAutoCollapse()

        guard coverageWatchTask == nil,
              window?.isVisible == true,
              window?.isKeyWindow == false,
              !session.isPinned,
              floatingIconPanel == nil,
              !isAnimatingFloatingIconTransition else {
            return
        }

        coverageWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else {
                    return
                }
                self.evaluateAutoCollapse()
            }
        }
    }

    private func stopCoverageWatch() {
        coverageWatchTask?.cancel()
        coverageWatchTask = nil
    }

    private func evaluateAutoCollapse() {
        collapseIfStillEligible()
    }

    /// 判定当下仍满足收起条件才动手，避免刚失去焦点或切桌面的瞬间状态已经又变回去。
    private func collapseIfStillEligible() {
        guard isEligibleForAutoCollapse else {
            return
        }

        // 刷新“收起后该把焦点还给谁”，否则会把焦点抢给一个早已不在前台的旧应用。
        rememberFrontmostExternalApplication()
        collapseToFloatingIcon()
    }

    private var isEligibleForAutoCollapse: Bool {
        guard let window, Date() >= suppressAutoCollapseUntil else {
            return false
        }

        return Self.shouldCollapseWindowWhenOccluded(
            isPinned: session.isPinned,
            hasFloatingIconPanel: floatingIconPanel != nil,
            isAnimatingFloatingIconTransition: isAnimatingFloatingIconTransition,
            isWindowVisible: window.isVisible,
            isKeyWindow: window.isKeyWindow,
            isMiniaturized: window.isMiniaturized,
            hiddenFraction: WindowVisibleCoverage.hiddenFraction(of: window)
        )
    }

    /// 看不见的面积达到八成就立刻收起：被别的普通窗口盖住、大部分拖出屏幕、切到别的桌面、别的应用全屏都算。
    /// 唯二排除的是最小化到程序坞（用户主动放进坞里的）和窗口本就没有显示出来（已经收起或已隐藏）。
    static func shouldCollapseWindowWhenOccluded(
        isPinned: Bool,
        hasFloatingIconPanel: Bool,
        isAnimatingFloatingIconTransition: Bool,
        isWindowVisible: Bool,
        isKeyWindow: Bool,
        isMiniaturized: Bool,
        hiddenFraction: CGFloat
    ) -> Bool {
        !isPinned &&
        !hasFloatingIconPanel &&
        !isAnimatingFloatingIconTransition &&
        isWindowVisible &&
        !isKeyWindow &&
        !isMiniaturized &&
        WindowVisibleCoverage.shouldCollapse(hiddenFraction: hiddenFraction)
    }

    private func applyInitialFrame(
        using preference: StoredWebAppPreference,
        restoredWindowFrame: CGRect?,
        to window: NSWindow,
        preferredGeometry: ScreenNotchGeometry?
    ) {
        if let restoredWindowFrame,
           !isFillFrame(restoredWindowFrame, among: placementScreens()) {
            lockLaunchFrame(restoredWindowFrame, on: window)
            return
        }

        let availableScreens = placementScreens()
        let fallbackDisplayID = NSScreen.main?.displayID

        let frame = WebAppWindowPlacementResolver.resolveFrame(
            preference: preference,
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        lockLaunchFrame(frame, on: window)
    }

    private func ensureWindowFrameIsVisible(preferredGeometry: ScreenNotchGeometry?) {
        guard let window, !shouldHoldLaunchFrame else {
            return
        }

        let availableScreens = placementScreens()
        guard !WebAppWindowPlacementResolver.isFrameVisible(window.frame, across: availableScreens) else {
            clampWindowToDockReserveIfNeeded()
            return
        }

        let transientPreference = StoredWebAppPreference(
            pageZoom: session.pageZoom,
            isPinned: session.isPinned,
            windowFrame: window.frame,
            windowPlacement: StoredWindowPlacement(frame: window.frame, display: nil)
        )
        let nextFrame = WebAppWindowPlacementResolver.resolveFrame(
            preference: transientPreference,
            preferredGeometry: preferredGeometry ?? self.preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: NSScreen.main?.displayID,
            defaultFrameSize: WebAppWindowMetrics.defaultFrameSize,
            minimumFrameSize: WebAppWindowMetrics.minimumFrameSize
        )

        window.setFrame(nextFrame, display: false)
    }

    private func lockLaunchFrame(_ frame: CGRect, on window: NSWindow) {
        lockedLaunchFrame = frame
        shouldHoldLaunchFrame = true
        browserWindow?.ignoresDockAvoidance = true
        window.setFrame(frame, display: false)
    }

    private func restoreLockedFrameIfNeeded(on window: NSWindow?) {
        guard shouldHoldLaunchFrame, let window, let lockedLaunchFrame else {
            return
        }

        if abs(window.frame.width - lockedLaunchFrame.width) > 0.5 ||
            abs(window.frame.height - lockedLaunchFrame.height) > 0.5 ||
            abs(window.frame.minX - lockedLaunchFrame.minX) > 0.5 ||
            abs(window.frame.minY - lockedLaunchFrame.minY) > 0.5 {
            window.setFrame(lockedLaunchFrame, display: false)
        }
    }

    private func releaseLaunchFrameHoldIfNeeded() {
        restoreLockedFrameIfNeeded(on: window)
        guard shouldHoldLaunchFrame else {
            return
        }

        shouldHoldLaunchFrame = false
        browserWindow?.ignoresDockAvoidance = false
        clampWindowToDockReserveIfNeeded()
        persistWindowFrame()
    }

    private func isFillFrame(_ frame: CGRect, among screens: [WebAppWindowPlacementScreen]) -> Bool {
        screens.contains {
            WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: $0.visibleFrame)
                || WebAppWindowPlacementResolver.isFillVisibleFrame(frame, visibleFrame: $0.usableFrame)
        }
    }

    private func placementScreens() -> [WebAppWindowPlacementScreen] {
        NSScreen.screens.map { WebAppWindowPlacementScreen(screen: $0, dockReserve: dockReserve) }
    }

    private func clampWindowToDockReserveIfNeeded() {
        guard let window, !shouldHoldLaunchFrame else {
            return
        }

        let clamped = WebAppWindowPlacementResolver.clamp(window.frame, into: placementScreens())
        guard abs(clamped.minX - window.frame.minX) > 0.5
            || abs(clamped.minY - window.frame.minY) > 0.5
            || abs(clamped.width - window.frame.width) > 0.5
            || abs(clamped.height - window.frame.height) > 0.5 else {
            return
        }

        window.setFrame(clamped, display: window.isVisible)
        persistWindowFrame()
    }

    private var browserWindow: WebAppBrowserWindow? {
        window as? WebAppBrowserWindow
    }
}

/// 拖动和系统放大都走 `constrainFrameRect`，在系统可用桌面之上再避开侧边 Dock。
private final class WebAppBrowserWindow: NSWindow {
    var dockReserve: SideDockScreenReserve?
    var ignoresDockAvoidance = false

    override func constrainFrameRect(_ frameRect: CGRect, to screen: NSScreen?) -> CGRect {
        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard !ignoresDockAvoidance else {
            return constrained
        }

        let targetScreen = screen ?? self.screen
        let usableFrame = SideDockWindowAvoidance.usableFrame(
            visibleFrame: targetScreen?.visibleFrame ?? constrained,
            reserve: dockReserve,
            screenDisplayID: targetScreen?.displayID
        )
        return SideDockWindowAvoidance.clamp(constrained, into: usableFrame)
    }
}

private extension CGRect {
    var topLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
}
