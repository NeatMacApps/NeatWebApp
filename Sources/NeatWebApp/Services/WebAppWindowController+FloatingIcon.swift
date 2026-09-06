import AppKit
import QuartzCore

@MainActor
extension WebAppWindowController {
    // MARK: - 悬浮图标收起 / 展开

    func collapseToFloatingIcon() {
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
    func showFloatingIcon(frame: CGRect) -> FloatingWebAppIconPanel {
        let panel = floatingIconPanel ?? makeFloatingIconPanel()
        floatingIconPanel = panel
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        return panel
    }

    func expandFromFloatingIcon(shouldFocusWebView: Bool = true) {
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

    func hideFloatingIcon() {
        floatingIconPanel?.orderOut(nil)
        floatingIconPanel = nil
    }

    func floatingIconFrame(alignedToTopLeft topLeft: CGPoint) -> CGRect {
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

    func rememberFrontmostExternalApplication() {
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
}

private extension CGRect {
    var topLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }
}
