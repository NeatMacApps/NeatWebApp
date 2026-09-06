import AppKit
import Foundation

extension AppModel {
    // MARK: - Launcher / Notch

    func refreshScreenState() {
        detectedNotchScreens = NSScreen.screens.compactMap { screen in
            if let hardwareGeometry = ScreenNotchGeometry(screen: screen) {
                return hardwareGeometry
            }

            guard isVirtualNotchEnabled else {
                return nil
            }

            return ScreenNotchGeometry.virtual(screen: screen)
        }

        // 屏幕参数变化在启动瞬间也会触发，这里只清理已经消失的热区，
        // 否则会顺手取消掉刚排上的悬停等待，指针停着不动就再也等不到展开。
        if let pendingActivationGeometryID,
           !detectedNotchScreens.contains(where: { $0.id == pendingActivationGeometryID }) {
            cancelPendingActivation()
        }

        if let launcherGeometry = launcherContext?.geometry,
           !detectedNotchScreens.contains(where: { $0.id == launcherGeometry.id }) {
            hideLauncher(immediately: true)
        }

        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)
        syncSideDockOverlay()
        diagnosticsMessage = screenDiagnosticsMessage
    }

    func toggleNotchDebugOverlay() {
        isNotchDebugOverlayVisible.toggle()
        notchDebugOverlayController.update(with: detectedNotchScreens, isVisible: isNotchDebugOverlayVisible)
    }

    func revealLauncherManually() {
        refreshScreenState()

        guard let geometry = mainScreenPreferredGeometry else {
            diagnosticsMessage = "Manual reveal found no usable notch zone. Enable the virtual notch in Settings to use non-notched displays."
            return
        }

        showLauncher(for: geometry)
    }

    func setVirtualNotchEnabled(_ isEnabled: Bool) {
        guard isVirtualNotchEnabled != isEnabled else {
            return
        }

        isVirtualNotchEnabled = isEnabled
        saveAppPreferences()

        // 关掉虚拟刘海时，正挂在虚拟热区上的启动器必须立刻撤掉，否则会留在菜单栏上。
        if !isEnabled, launcherContext?.geometry.isVirtual == true {
            hideLauncher(immediately: true)
        }

        refreshScreenState()
    }

    func dismissLauncherVoluntarily() {
        isTemporarilySuppressed = true
        cancelPendingActivation()
        hideLauncher(afterDelay: .zero)
    }

    /// 临时：事件日志，验证合成拖拽是否送达本应用。
    private func debugMouseLog(_ message: String) {
        let url = URL(fileURLWithPath: "/tmp/neatwebapp_mouse.log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        try? handle.seekToEnd()
        if let data = "[\(Date().timeIntervalSince1970)] \(message)\n".data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
        try? handle.close()
    }

    func hideLauncher(immediately: Bool = false) {
        if immediately {
            hideLauncherTask?.cancel()
            hideLauncherTask = nil

            guard isLauncherVisible || overlayController.frame != nil else {
                launcherContext = nil
                return
            }

            isLauncherVisible = false
            overlayController.hide()
            launcherContext = nil
            return
        }

        hideLauncher(afterDelay: Self.launcherHideDelay)
    }

    func hideLauncher(afterDelay delay: Duration) {
        guard hideLauncherTask == nil else {
            return
        }

        guard isLauncherVisible || overlayController.frame != nil else {
            launcherContext = nil
            return
        }

        hideLauncherTask = Task {
            defer {
                hideLauncherTask = nil
            }

            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }

            isLauncherVisible = false

            do {
                try await Task.sleep(for: Self.launcherTransitionDuration)
            } catch {
                return
            }

            overlayController.hide()
            launcherContext = nil
        }
    }

    func handleMouseEvent(_ mouseLocation: CGPoint, _ eventType: NSEvent.EventType) {
        let isClick = (eventType == .leftMouseDown || eventType == .rightMouseDown)
        debugMouseLog("\(eventType.rawValue) @ (\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))")

        let geometryForActivation = detectedNotchScreens.first(where: { $0.containsActivationPoint(mouseLocation) })
        let activationContains = geometryForActivation != nil

        if isTemporarilySuppressed {
            if !activationContains {
                isTemporarilySuppressed = false
            } else {
                return
            }
        }

        if let frame = overlayController.frame, frame.contains(mouseLocation) {
            return
        }

        if isClick,
           isLauncherVisible,
           let geometry = launcherContext?.geometry,
           geometry.containsLauncherRetentionPoint(mouseLocation) {
            dismissLauncherVoluntarily()
            return
        }

        if isLauncherVisible,
           let geometry = launcherContext?.geometry,
           geometry.containsLauncherRetentionPoint(mouseLocation) {
            showLauncher(for: geometry)
            return
        }

        if let geometry = geometryForActivation {
            requestLauncher(for: geometry, isClick: isClick)
            return
        }

        cancelPendingActivation()
        hideLauncher()
    }

    /// 指针移入热区后先等一段时间，到期再看是否还在区内才展开。
    /// 已经展开时不再等。点进硬件刘海视为明确意图，立即展开；
    /// 虚拟热区上的点击一律让给菜单栏，不在这里抢焦点。
    private func requestLauncher(for geometry: ScreenNotchGeometry, isClick: Bool) {
        if isLauncherVisible {
            cancelPendingActivation()
            showLauncher(for: geometry)
            return
        }

        if isClick {
            guard !geometry.isVirtual else {
                cancelPendingActivation()
                return
            }

            cancelPendingActivation()
            showLauncher(for: geometry)
            return
        }

        guard pendingActivationGeometryID != geometry.id else {
            return
        }

        cancelPendingActivation()
        pendingActivationGeometryID = geometry.id
        pendingActivationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: geometry.hoverIntentDelay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.pendingActivationTask = nil
            self.pendingActivationGeometryID = nil

            guard geometry.containsActivationPoint(NSEvent.mouseLocation) else {
                return
            }

            self.showLauncher(for: geometry)
        }
    }

    func cancelPendingActivation() {
        pendingActivationTask?.cancel()
        pendingActivationTask = nil
        pendingActivationGeometryID = nil
    }

    func showLauncher(for geometry: ScreenNotchGeometry) {
        hideLauncherTask?.cancel()
        hideLauncherTask = nil
        cancelPendingActivation()

        if isLauncherVisible, launcherContext?.geometry == geometry {
            return
        }

        let context = LauncherPresentationContext(geometry: geometry, apps: apps)
        launcherContext = context
        isLauncherVisible = true
        overlayController.present(context: context, appModel: self)
    }

    var screenDiagnosticsMessage: String {
        let hardwareCount = detectedNotchScreens.count(where: { !$0.isVirtual })
        let virtualCount = detectedNotchScreens.count(where: \.isVirtual)

        switch (hardwareCount, virtualCount) {
        case (0, 0):
            return isVirtualNotchEnabled
            ? "No usable notch zone was detected on any display."
            : "No notched display was detected. Enable the virtual notch in Settings to reveal the launcher on non-notched displays."
        case (let hardware, 0):
            return "Detected \(hardware) notched display(s). Hover the notch area to reveal the launcher."
        case (0, let virtual):
            return "No hardware notch was detected. \(virtual) display(s) use a virtual notch zone: rest the pointer on the top center of the screen to reveal the launcher."
        case (let hardware, let virtual):
            return "Detected \(hardware) notched display(s) and \(virtual) display(s) with a virtual notch zone at the top center."
        }
    }

    var mainScreenPreferredGeometry: ScreenNotchGeometry? {
        guard let mainScreen = NSScreen.main else {
            return detectedNotchScreens.first
        }

        return detectedNotchScreens.first(where: { $0.screenFrame == mainScreen.frame })
        ?? detectedNotchScreens.first
    }
}
