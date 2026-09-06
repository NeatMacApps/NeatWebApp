import AppKit

@MainActor
extension WebAppWindowController {
    // MARK: - 自动收起与遮挡监视

    func startEnvironmentObserversIfNeeded() {
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

    func stopEnvironmentObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in environmentObservers {
            center.removeObserver(observer)
        }
        environmentObservers.removeAll()
    }

    func startCoverageWatch() {
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

    func stopCoverageWatch() {
        coverageWatchTask?.cancel()
        coverageWatchTask = nil
    }

    func evaluateAutoCollapse() {
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
}
