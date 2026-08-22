import AppKit

struct WebAppWindowPlacementScreen: Equatable, Sendable {
    let displayID: UInt32?
    let localizedName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let notchGeometry: ScreenNotchGeometry?

    init(
        displayID: UInt32?,
        localizedName: String,
        frame: CGRect,
        visibleFrame: CGRect,
        notchGeometry: ScreenNotchGeometry?
    ) {
        self.displayID = displayID
        self.localizedName = localizedName
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.notchGeometry = notchGeometry
    }

    init(screen: NSScreen) {
        self.init(
            displayID: screen.displayID,
            localizedName: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            notchGeometry: ScreenNotchGeometry(screen: screen)
        )
    }
}

enum WebAppWindowPlacementResolver {
    private static let notchSpacing: CGFloat = 80
    private static let fallbackTopMargin: CGFloat = 84

    static func resolveFrame(
        preference: StoredWebAppPreference,
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?,
        defaultFrameSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGRect {
        let preferredScreen = resolvePreferredScreen(
            preferredGeometry: preferredGeometry,
            availableScreens: availableScreens,
            fallbackDisplayID: fallbackDisplayID
        )
        let preferredNotch = resolvePreferredNotch(
            preferredGeometry: preferredGeometry,
            preferredScreen: preferredScreen
        )

        if let storedPlacement = preference.resolvedWindowPlacement,
           let matchedScreen = resolveStoredScreen(for: storedPlacement, availableScreens: availableScreens),
           !isFillVisibleFrame(storedPlacement.frame, visibleFrame: matchedScreen.visibleFrame) {
            // 用户拖过的尺寸只许缩小以塞进屏幕，不许被「最小窗口」抬成整块可用桌面。
            let size = fittedSize(storedPlacement.frame.size, within: matchedScreen.visibleFrame.size)
            let frame = CGRect(origin: storedPlacement.frame.origin, size: size)
            return clamp(frame, into: matchedScreen.visibleFrame)
        }

        let fallbackScreen = preferredScreen ?? availableScreens.first
        let safeDefaultSize = sanitizedDefaultSize(
            defaultFrameSize,
            visibleSize: fallbackScreen?.visibleFrame.size
        )
        let requestedSize = usableStoredSize(
            preference.resolvedWindowPlacement?.frame.size,
            visibleSize: fallbackScreen?.visibleFrame.size
        ) ?? safeDefaultSize
        let placementBounds = fallbackPlacementBounds(
            preferredNotch: preferredNotch ?? fallbackScreen?.notchGeometry,
            visibleFrame: fallbackScreen?.visibleFrame
        )
        let size = clampedSize(
            requestedSize,
            within: placementBounds?.size ?? fallbackScreen?.visibleFrame.size ?? safeDefaultSize,
            minimumFrameSize: sanitizedMinimumSize(
                minimumFrameSize,
                visibleSize: placementBounds?.size ?? fallbackScreen?.visibleFrame.size
            )
        )

        guard let fallbackScreen else {
            return CGRect(origin: .zero, size: size)
        }

        return fallbackFrame(
            size: size,
            preferredNotch: preferredNotch ?? fallbackScreen.notchGeometry,
            visibleFrame: fallbackScreen.visibleFrame,
            placementBounds: placementBounds ?? fallbackScreen.visibleFrame
        )
    }

    /// 铺满当前可用桌面的框不是用户选的窗口大小，而是缩放 / 系统贴边的结果。
    static func isFillVisibleFrame(_ frame: CGRect, visibleFrame: CGRect, tolerance: CGFloat = 8) -> Bool {
        isFillVisibleSize(frame.size, visibleSize: visibleFrame.size, tolerance: tolerance) &&
            abs(frame.minX - visibleFrame.minX) <= tolerance &&
            abs(frame.minY - visibleFrame.minY) <= tolerance
    }

    static func isFillVisibleSize(_ size: CGSize, visibleSize: CGSize, tolerance: CGFloat = 8) -> Bool {
        abs(size.width - visibleSize.width) <= tolerance &&
            abs(size.height - visibleSize.height) <= tolerance
    }

    static func isFrameVisible(_ frame: CGRect, across screens: [WebAppWindowPlacementScreen]) -> Bool {
        screens.contains { $0.visibleFrame.contains(frame) }
    }

    private static func resolveStoredScreen(
        for placement: StoredWindowPlacement,
        availableScreens: [WebAppWindowPlacementScreen]
    ) -> WebAppWindowPlacementScreen? {
        guard let storedDisplay = placement.display else {
            return nil
        }

        return availableScreens.first(where: { screen in
            if let storedDisplayID = storedDisplay.displayID,
               let screenDisplayID = screen.displayID,
               storedDisplayID == screenDisplayID {
                return true
            }

            // 显示器名字会随系统语言变，不能当主键；编号对不上时用物理尺寸兜底。
            return storedDisplay.frame.size == screen.frame.size
        })
    }

    private static func usableStoredSize(_ size: CGSize?, visibleSize: CGSize?) -> CGSize? {
        guard let size else {
            return nil
        }

        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return nil
        }

        return size
    }

    private static func sanitizedDefaultSize(_ size: CGSize, visibleSize: CGSize?) -> CGSize {
        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return WebAppWindowMetrics.defaultContentSize
        }

        return size
    }

    private static func sanitizedMinimumSize(_ size: CGSize, visibleSize: CGSize?) -> CGSize {
        if let visibleSize, isFillVisibleSize(size, visibleSize: visibleSize) {
            return WebAppWindowMetrics.minimumContentSize
        }

        return size
    }

    private static func fittedSize(_ size: CGSize, within availableSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 1), availableSize.width),
            height: min(max(size.height, 1), availableSize.height)
        )
    }

    private static func resolvePreferredScreen(
        preferredGeometry: ScreenNotchGeometry?,
        availableScreens: [WebAppWindowPlacementScreen],
        fallbackDisplayID: UInt32?
    ) -> WebAppWindowPlacementScreen? {
        if let preferredDisplayID = preferredGeometry?.displayID,
           let screen = availableScreens.first(where: { $0.displayID == preferredDisplayID }) {
            return screen
        }

        if let preferredGeometry,
           let screen = availableScreens.first(where: { $0.frame == preferredGeometry.screenFrame }) {
            return screen
        }

        if let fallbackDisplayID,
           let screen = availableScreens.first(where: { $0.displayID == fallbackDisplayID }) {
            return screen
        }

        return availableScreens.first(where: { $0.notchGeometry != nil }) ?? availableScreens.first
    }

    private static func resolvePreferredNotch(
        preferredGeometry: ScreenNotchGeometry?,
        preferredScreen: WebAppWindowPlacementScreen?
    ) -> ScreenNotchGeometry? {
        if let preferredGeometry {
            return preferredGeometry
        }

        return preferredScreen?.notchGeometry
    }

    private static func clampedSize(
        _ size: CGSize,
        within availableSize: CGSize,
        minimumFrameSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(availableSize.width, max(minimumFrameSize.width, size.width)),
            height: min(availableSize.height, max(minimumFrameSize.height, size.height))
        )
    }

    private static func fallbackFrame(
        size: CGSize,
        preferredNotch: ScreenNotchGeometry?,
        visibleFrame: CGRect,
        placementBounds: CGRect
    ) -> CGRect {
        let origin: CGPoint

        if let preferredNotch {
            origin = CGPoint(
                x: preferredNotch.notchRect.midX - (size.width / 2),
                y: placementBounds.maxY - size.height
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.maxY - size.height - fallbackTopMargin
            )
        }

        return clamp(CGRect(origin: origin, size: size), into: placementBounds)
    }

    private static func fallbackPlacementBounds(
        preferredNotch: ScreenNotchGeometry?,
        visibleFrame: CGRect?
    ) -> CGRect? {
        guard let visibleFrame else {
            return nil
        }

        guard let preferredNotch else {
            return visibleFrame
        }

        let maxY = max(visibleFrame.minY, preferredNotch.notchRect.minY - notchSpacing)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: maxY - visibleFrame.minY
        )
    }

    private static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maxX = visibleFrame.maxX - width
        let maxY = visibleFrame.maxY - height

        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), maxX),
            y: min(max(frame.minY, visibleFrame.minY), maxY),
            width: width,
            height: height
        )
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
