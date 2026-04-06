import AppKit

struct ScreenNotchGeometry: Identifiable, Equatable, Sendable {
    private static let launcherRetentionHorizontalPaddingRatio: CGFloat = 0.22
    private static let launcherRetentionTopPaddingRatio: CGFloat = 0.08
    private static let launcherRetentionBottomPaddingWidthRatio: CGFloat = 0.72
    private static let launcherRetentionBottomPaddingHeightRatio: CGFloat = 1.6
    private static let launcherRetentionHeightScale: CGFloat = 0.6

    let displayID: UInt32?
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect
    let localizedName: String

    var id: String {
        "\(localizedName)-\(Int(screenFrame.origin.x))-\(Int(screenFrame.origin.y))-\(Int(screenFrame.width))x\(Int(screenFrame.height))"
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
        localizedName: String
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.localizedName = localizedName
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
        lhs.localizedName == rhs.localizedName
    }
}
