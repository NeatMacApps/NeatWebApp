import AppKit

/// 刘海区域的来源：真实硬件刘海，或无刘海屏幕上由应用自己画出来的虚拟热区。
enum ScreenNotchKind: String, Sendable {
    case hardware
    case virtual
}

struct ScreenNotchGeometry: Identifiable, Equatable, Sendable {
    private static let launcherRetentionHorizontalPaddingRatio: CGFloat = 0.22
    private static let launcherRetentionTopPaddingRatio: CGFloat = 0.08
    private static let launcherRetentionBottomPaddingWidthRatio: CGFloat = 0.72
    private static let launcherRetentionBottomPaddingHeightRatio: CGFloat = 1.6
    private static let launcherRetentionHeightScale: CGFloat = 0.6
    private static let virtualNotchWidthRatio: CGFloat = 0.18
    private static let virtualNotchMinimumWidth: CGFloat = 180
    private static let virtualNotchMaximumWidth: CGFloat = 320
    private static let virtualNotchMaximumWidthRatio: CGFloat = 0.6
    private static let virtualNotchFallbackHeight: CGFloat = 26
    private static let virtualNotchMaximumHeight: CGFloat = 38

    let displayID: UInt32?
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect
    let localizedName: String
    let kind: ScreenNotchKind

    var id: String {
        "\(kind.rawValue)-\(localizedName)-\(Int(screenFrame.origin.x))-\(Int(screenFrame.origin.y))-\(Int(screenFrame.width))x\(Int(screenFrame.height))"
    }

    var isVirtual: Bool {
        kind == .virtual
    }

    /// 指针移入热区后要等这么久，到期时仍在区内才展开启动器。
    /// 硬件 100ms：挡住路过误开，又不会觉得钝。虚拟约 260ms：热区压在菜单栏上，必须更久。
    var hoverIntentDelay: Duration {
        isVirtual ? .milliseconds(260) : .milliseconds(100)
    }

    init?(
        screen: NSScreen
    ) {
        self.init(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero,
            localizedName: screen.localizedName
        )

        guard hasNotch else {
            return nil
        }
    }

    init(
        displayID: UInt32? = nil,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: CGRect,
        auxiliaryTopRightArea: CGRect,
        localizedName: String,
        kind: ScreenNotchKind = .hardware
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.localizedName = localizedName
        self.kind = kind
    }

    /// 无硬件刘海的屏幕用顶部居中的虚拟刘海兜底。
    /// 这里刻意复用与硬件刘海完全相同的字段来描述虚拟区域，
    /// 让热区判定、启动器布局和调试叠层都不需要再区分两种来源。
    /// 屏幕本身带刘海时返回 `nil`，避免同一块屏幕出现两个热区。
    static func virtual(screen: NSScreen) -> ScreenNotchGeometry? {
        guard ScreenNotchGeometry(screen: screen) == nil else {
            return nil
        }

        return virtual(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            localizedName: screen.localizedName
        )
    }

    static func virtual(
        displayID: UInt32?,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        localizedName: String
    ) -> ScreenNotchGeometry? {
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return nil
        }

        // 高度对齐菜单栏：虚拟刘海展开时正好盖住菜单栏中段，不会额外压到窗口内容。
        // 菜单栏自动隐藏、或这块屏幕根本没有菜单栏时差值为 0，退回一个仍然好点中的兜底高度。
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let height = menuBarHeight > 0
        ? min(menuBarHeight, virtualNotchMaximumHeight)
        : virtualNotchFallbackHeight
        let maximumWidth = min(virtualNotchMaximumWidth, screenFrame.width * virtualNotchMaximumWidthRatio)
        let width = min(
            max(screenFrame.width * virtualNotchWidthRatio, min(virtualNotchMinimumWidth, maximumWidth)),
            maximumWidth
        )

        guard width > 0, height > 0 else {
            return nil
        }

        let topStripMinY = screenFrame.maxY - height
        let notchMinX = (screenFrame.midX - (width / 2)).rounded()
        let notchMaxX = notchMinX + width

        return ScreenNotchGeometry(
            displayID: displayID,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            safeAreaInsets: NSEdgeInsets(top: height, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(
                x: screenFrame.minX,
                y: topStripMinY,
                width: notchMinX - screenFrame.minX,
                height: height
            ),
            auxiliaryTopRightArea: CGRect(
                x: notchMaxX,
                y: topStripMinY,
                width: screenFrame.maxX - notchMaxX,
                height: height
            ),
            localizedName: localizedName,
            kind: .virtual
        )
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0 &&
        !auxiliaryTopLeftArea.isEmpty &&
        !auxiliaryTopRightArea.isEmpty &&
        auxiliaryTopLeftArea.maxX < auxiliaryTopRightArea.minX
    }

    var notchRect: CGRect {
        let topStrip = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - safeAreaInsets.top,
            width: screenFrame.width,
            height: safeAreaInsets.top
        )

        return CGRect(
            x: auxiliaryTopLeftArea.maxX,
            y: topStrip.minY,
            width: max(auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX, 0),
            height: topStrip.height
        )
    }

    var activationRect: CGRect {
        notchRect
    }

    func containsActivationPoint(_ point: CGPoint) -> Bool {
        contains(point, in: activationRect)
    }

    func containsStickyActivationPoint(_ point: CGPoint) -> Bool {
        containsActivationPoint(point)
    }

    var launcherRetentionRect: CGRect {
        let launcherFrame = estimatedLauncherFrame
        let horizontalPadding = max(
            launcherFrame.width * Self.launcherRetentionHorizontalPaddingRatio,
            28
        )
        let topPadding = max(
            launcherFrame.height * Self.launcherRetentionTopPaddingRatio,
            8
        )
        let bottomPadding = max(
            launcherFrame.width * Self.launcherRetentionBottomPaddingWidthRatio,
            launcherFrame.height * Self.launcherRetentionBottomPaddingHeightRatio
        )
        let rect = CGRect(
            x: launcherFrame.minX - horizontalPadding,
            y: launcherFrame.minY - bottomPadding,
            width: launcherFrame.width + (horizontalPadding * 2),
            height: launcherFrame.height + topPadding + bottomPadding
        )

        return verticallyScaledPreservingTopEdge(
            rect,
            by: Self.launcherRetentionHeightScale
        )
    }

    func containsLauncherRetentionPoint(_ point: CGPoint) -> Bool {
        contains(point, in: launcherRetentionRect)
    }

    private var estimatedLauncherFrame: CGRect {
        let notchHeight = notchRect.height
        let iconSize = min(max(notchHeight * 0.54, 28), 40)
        let iconBottomPadding = max(min(notchHeight * 0.15, 12), 8)
        let launcherHeight = notchHeight + iconSize + iconBottomPadding

        return CGRect(
            x: notchRect.minX,
            y: screenFrame.maxY - launcherHeight,
            width: notchRect.width,
            height: launcherHeight
        )
    }

    private func verticallyScaledPreservingTopEdge(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        guard scale > 0, scale < 1 else {
            return rect
        }

        let scaledHeight = rect.height * scale
        return CGRect(
            x: rect.minX,
            y: rect.maxY - scaledHeight,
            width: rect.width,
            height: scaledHeight
        )
    }

    private func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX &&
        point.x <= rect.maxX &&
        point.y >= rect.minY &&
        point.y <= rect.maxY
    }

    static func == (lhs: ScreenNotchGeometry, rhs: ScreenNotchGeometry) -> Bool {
        lhs.screenFrame == rhs.screenFrame &&
        lhs.visibleFrame == rhs.visibleFrame &&
        lhs.displayID == rhs.displayID &&
        lhs.safeAreaInsets.top == rhs.safeAreaInsets.top &&
        lhs.safeAreaInsets.left == rhs.safeAreaInsets.left &&
        lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom &&
        lhs.safeAreaInsets.right == rhs.safeAreaInsets.right &&
        lhs.auxiliaryTopLeftArea == rhs.auxiliaryTopLeftArea &&
        lhs.auxiliaryTopRightArea == rhs.auxiliaryTopRightArea &&
        lhs.localizedName == rhs.localizedName &&
        lhs.kind == rhs.kind
    }
}
